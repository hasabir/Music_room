import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../auth/auth_api.dart';
import '../auth/auth_models.dart';
import '../auth/welcome_screen.dart';
import '../core/api/api_client.dart';
import '../core/auth/token_storage.dart';
import '../core/widgets/app_bottom_nav.dart';
import '../core/widgets/app_tab_navigation.dart';
import '../profile/profile_api.dart';
import '../profile/profile_avatar.dart';
import '../profile/profile_models.dart';
import '../track_vote/create_event_screen.dart';
import '../track_vote/event_api.dart';
import '../track_vote/event_detail_screen.dart';
import '../track_vote/event_models.dart';
import '../track_vote/location_label.dart';
import 'home_widgets.dart';

/// The Home tab — a Spotify/Apple-Music-style landing page: a greeting
/// header, a horizontal "Your Events" row (hosted, self-joined, or an
/// accepted private invite), a "Pending Invitations" section for private
/// invites still awaiting a response, and a "Discover" list of public
/// events the signed-in user isn't part of yet.
///
/// All of it is built from the existing `GET /api/v1/events/` list (see
/// `EventListCreateView.get_queryset`: public events, plus ones hosted or
/// invited-to) split client-side by the same host/`is_member` signals
/// `EventsLandingScreen` already uses — plus a private event's own
/// `rsvp_status`, resolved per-event via the existing
/// `GET /events/<id>/guests/` (see `_resolvePrivateInvites`), since the
/// list endpoint has no per-event RSVP field of its own.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _authApi = AuthApi();
  final _profileApi = ProfileApi();
  final _eventApi = EventApi();
  final _tokenStorage = TokenStorage();

  UserProfile? _profile;
  AuthUser? _authUser;

  /// Hosted + self-joined events, later joined by accepted-private invites
  /// once [_resolvePrivateInvites] finishes. `null` only before the first
  /// load completes.
  List<Event>? _yourEvents;
  List<Event>? _discoverEvents;

  /// Private, non-hosted events still awaiting this user's RSVP. `null`
  /// while unresolved (section stays hidden, same as an empty list) —
  /// resolving takes a follow-up request per candidate event, so it lags
  /// slightly behind [_yourEvents]/[_discoverEvents] rather than blocking
  /// them.
  List<Event>? _pendingInvites;
  final Set<int> _respondingEventIds = {};

  Position? _devicePosition;

  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final results = await Future.wait([
        _profileApi.getMyProfile(),
        _authApi.getCurrentUser(),
        _eventApi.listEvents(),
      ]);
      final profile = results[0] as UserProfile;
      final authUser = results[1] as AuthUser;
      final events = results[2] as List<Event>;

      final yourEvents = <Event>[];
      final discover = <Event>[];
      final privateCandidates = <Event>[];

      for (final event in events) {
        final isHost = event.host == authUser.username;
        if (isHost || event.isMember) {
          yourEvents.add(event);
        } else if (event.visibility == eventVisibilityPrivate) {
          // Guaranteed (by EventListCreateView.get_queryset) to mean this
          // user has an EventGuest row here — otherwise a private,
          // non-hosted event could never have appeared in the list at all.
          privateCandidates.add(event);
        } else {
          discover.add(event);
        }
      }

      if (!mounted) return;
      setState(() {
        _profile = profile;
        _authUser = authUser;
        _yourEvents = yourEvents;
        _discoverEvents = discover;
        _pendingInvites = null;
        _loading = false;
      });

      unawaited(_resolvePrivateInvites(privateCandidates, authUser.id));
      unawaited(_resolveDevicePosition());
    } on SessionExpiredException {
      await _signOutAndReturnToWelcome();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error.message;
      });
    }
  }

  /// For each non-hosted private event, looks up the signed-in user's own
  /// guest row to read its real `rsvp_status` — `accepted` moves it into
  /// "Your Events", `pending` surfaces it under "Pending Invitations",
  /// `declined` (or a guest row that 404s/403s, e.g. the event was
  /// canceled since the initial fetch) drops it from both.
  Future<void> _resolvePrivateInvites(
    List<Event> candidates,
    int myUserId,
  ) async {
    final accepted = <Event>[];
    final pending = <Event>[];

    await Future.wait(
      candidates.map((event) async {
        try {
          final guests = await _eventApi.listGuests(event.id);
          EventGuest? mine;
          for (final guest in guests) {
            if (guest.guest == myUserId) {
              mine = guest;
              break;
            }
          }
          if (mine == null) return;
          if (mine.rsvpStatus == eventGuestRsvpAccepted) {
            accepted.add(event);
          } else if (mine.rsvpStatus == eventGuestRsvpPending) {
            pending.add(event);
          }
        } on ApiException {
          // See doc comment above — skip rather than fail the whole screen.
        }
      }),
    );

    if (!mounted) return;
    setState(() {
      _yourEvents = [...?_yourEvents, ...accepted];
      _pendingInvites = pending;
    });
  }

  /// Best-effort device position for Discover's distance line — checks
  /// whatever permission is already granted without prompting for one, so
  /// Home never interrupts loading with a permission dialog. Silently
  /// leaves [_devicePosition] `null` on any failure or if permission
  /// hasn't already been granted; Discover renders fine without it.
  Future<void> _resolveDevicePosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      final permission = await Geolocator.checkPermission();
      final granted =
          permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
      if (!granted) return;
      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() => _devicePosition = position);
    } catch (_) {
      // Best-effort only.
    }
  }

  Future<void> _signOutAndReturnToWelcome() async {
    await _tokenStorage.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  Future<void> _onCreateEvent() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CreateEventScreen()));
    await _load();
  }

  Future<void> _onOpenEvent(Event event) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EventDetailScreen(eventId: event.id)),
    );
    _load();
  }

  void _onOpenProfile() => navigateToTab(context, AppTab.home, AppTab.profile);

  Future<void> _onRespond(Event event, {required bool accept}) async {
    setState(() => _respondingEventIds.add(event.id));
    try {
      await _eventApi.respondToInvite(event.id, accept: accept);
      if (!mounted) return;
      setState(() {
        _pendingInvites = _pendingInvites
            ?.where((e) => e.id != event.id)
            .toList();
        _respondingEventIds.remove(event.id);
        if (accept) _yourEvents = [...?_yourEvents, event];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accept ? 'Joined "${event.title}".' : 'Declined "${event.title}".',
          ),
        ),
      );
    } on SessionExpiredException {
      await _signOutAndReturnToWelcome();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _respondingEventIds.remove(event.id));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  String? _distanceLabelFor(Event event) {
    final position = _devicePosition;
    final lat = event.venueCenterLatitude;
    final lng = event.venueCenterLongitude;
    if (position == null ||
        !event.locationRestrictionEnabled ||
        lat == null ||
        lng == null) {
      return null;
    }
    final meters = distanceInMeters(
      position.latitude,
      position.longitude,
      lat,
      lng,
    );
    return formatDistance(meters);
  }

  String _greetingName() {
    final profile = _profile;
    if (profile != null && profile.displayName.isNotEmpty) {
      return profile.displayName;
    }
    final authUser = _authUser;
    if (authUser != null) {
      final name = '${authUser.firstName} ${authUser.lastName}'.trim();
      if (name.isNotEmpty) return name;
      return authUser.email;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HomeColors.background,
      body: SafeArea(
        child: _loadError != null
            ? HomeErrorPanel(message: _loadError!, onRetry: _load)
            : RefreshIndicator(
                onRefresh: _load,
                color: HomeColors.headline,
                backgroundColor: HomeColors.card,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(top: 8, bottom: 110),
                  children: [
                    _loading
                        ? const HomeHeaderSkeleton()
                        : _Header(
                            greetingName: _greetingName(),
                            profile: _profile,
                            onTapAvatar: _onOpenProfile,
                          ),
                    const SizedBox(height: 28),
                    const HomeSectionHeader(title: 'Your Events'),
                    _buildYourEvents(),
                    if (_pendingInvites != null &&
                        _pendingInvites!.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      const HomeSectionHeader(title: 'Pending Invitations'),
                      _buildPendingInvites(),
                    ],
                    const SizedBox(height: 28),
                    const HomeSectionHeader(title: 'Discover'),
                    _buildDiscover(),
                  ],
                ),
              ),
      ),
      floatingActionButton: _CreateEventFab(onTap: _onCreateEvent),
      bottomNavigationBar: AppBottomNav(
        currentTab: AppTab.home,
        onTabSelected: (tab) => navigateToTab(context, AppTab.home, tab),
      ),
    );
  }

  Widget _buildYourEvents() {
    if (_loading) return const YourEventsSkeletonRow();

    final events = _yourEvents ?? const [];
    if (events.isEmpty) {
      return HomeEmptyPanel(
        icon: Icons.celebration_rounded,
        message:
            "You're not hosting or attending anything yet.\n"
            'Start your own event and get the votes going.',
        ctaLabel: 'Create Event',
        onCta: _onCreateEvent,
      );
    }

    return SizedBox(
      height: yourEventCardHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: events.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final event = events[index];
          return YourEventCard(event: event, onTap: () => _onOpenEvent(event));
        },
      ),
    );
  }

  Widget _buildPendingInvites() {
    final invites = _pendingInvites!;
    return Column(
      children: [
        for (var i = 0; i < invites.length; i++)
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              i == invites.length - 1 ? 0 : 12,
            ),
            child: PendingInviteCard(
              event: invites[i],
              isBusy: _respondingEventIds.contains(invites[i].id),
              onAccept: () => _onRespond(invites[i], accept: true),
              onDecline: () => _onRespond(invites[i], accept: false),
            ),
          ),
      ],
    );
  }

  Widget _buildDiscover() {
    if (_loading) return const DiscoverSkeletonList();

    final events = _discoverEvents ?? const [];
    if (events.isEmpty) {
      return const HomeEmptyPanel(
        icon: Icons.explore_off_rounded,
        message: 'Nothing nearby yet — check back soon.',
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          for (var i = 0; i < events.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == events.length - 1 ? 0 : 14),
              child: DiscoverEventTile(
                event: events[i],
                distanceLabel: _distanceLabelFor(events[i]),
                onTap: () => _onOpenEvent(events[i]),
              ),
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.greetingName,
    required this.profile,
    required this.onTapAvatar,
  });

  final String greetingName;
  final UserProfile? profile;
  final VoidCallback onTapAvatar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Welcome back',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: HomeColors.muted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  greetingName.isEmpty ? 'there' : greetingName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Sora',
                    fontWeight: FontWeight.w800,
                    fontSize: 26,
                    color: HomeColors.body,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          InkWell(
            onTap: onTapAvatar,
            customBorder: const CircleBorder(),
            child: Container(
              width: 52,
              height: 52,
              padding: const EdgeInsets.all(2.5),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [HomeColors.tertiary, HomeColors.gradientStart],
                ),
              ),
              child: ClipOval(
                child: profile == null
                    ? const _AvatarFallback()
                    : ProfileAvatarImage(
                        avatar: profile!.avatar,
                        avatarType: profile!.avatarType,
                        fallback: const _AvatarFallback(),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback();

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: HomeColors.card,
    child: Icon(Icons.person_rounded, color: HomeColors.muted, size: 26),
  );
}

class _CreateEventFab extends StatelessWidget {
  const _CreateEventFab({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [HomeColors.gradientStart, HomeColors.gradientEnd],
        ),
        boxShadow: [
          BoxShadow(
            color: HomeColors.gradientStart.withValues(alpha: 0.45),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: FloatingActionButton(
        onPressed: onTap,
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
      ),
    );
  }
}
