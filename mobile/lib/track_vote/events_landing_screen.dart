import 'package:flutter/material.dart';

import '../auth/auth_api.dart';
import '../auth/auth_models.dart';
import '../auth/welcome_screen.dart';
import '../core/api/api_client.dart';
import '../core/auth/token_storage.dart';
import '../core/widgets/app_bottom_nav.dart';
import '../core/widgets/app_tab_navigation.dart';
import 'create_event_screen.dart';
import 'event_api.dart';
import 'event_detail_screen.dart';
import 'event_models.dart';
import 'event_widgets.dart';

class _EventColors {
  static const background = Color(0xFF0E0E15);
  static const card = Color(0xFF17161F);
  static const cardBorder = Color(0xFF2A2935);
  static const headline = Color(0xFFC0C1FF);
  static const body = Color(0xFFE4E1EB);
  static const muted = Color(0xFF908FA0);
  static const tertiary = Color(0xFF2FD9F4);
  static const gradientStart = Color(0xFF8083FF);
  static const gradientEnd = Color(0xFF494BD6);
}

/// The "Track Vote" tab — public events plus the ones the signed-in user
/// hosts or is privately invited to ("My Events"), and public events they
/// aren't part of yet ("Discover"). Reachable from the bottom nav.
///
/// Loads `GET /api/v1/events/` (which already returns public + hosted +
/// invited-private, deduped — same shape as the playlists list endpoint)
/// and splits it into the two tabs client-side by comparing each event's
/// `host` against the signed-in user's email, since the backend has no
/// separate "discover" endpoint or "is mine" flag.
///
/// TODO(events): the backend also has no `is_member`-style flag for a
/// *public* event the user has already joined via `POST .../join/`
/// (`EventMembership` isn't reflected on the `Event` object at all) — so a
/// public event the user already joined still shows up under "Discover"
/// here, with a "Join Event" button that will 400 as "already joined".
/// Fix once there's either a dedicated discover endpoint or a membership
/// flag on the list response.
class EventsLandingScreen extends StatefulWidget {
  const EventsLandingScreen({super.key});

  @override
  State<EventsLandingScreen> createState() => _EventsLandingScreenState();
}

class _EventsLandingScreenState extends State<EventsLandingScreen> {
  final _eventApi = EventApi();
  final _authApi = AuthApi();
  final _tokenStorage = TokenStorage();

  Future<_ListData>? _dataFuture;
  var _tab = _EventTab.mine;

  @override
  void initState() {
    super.initState();
    _dataFuture = _load();
  }

  Future<_ListData> _load() async {
    try {
      final results = await Future.wait([_eventApi.listEvents(), _authApi.getCurrentUser()]);
      return _ListData(events: results[0] as List<Event>, authUser: results[1] as AuthUser);
    } on SessionExpiredException {
      await _signOutAndReturnToWelcome();
      rethrow;
    }
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() => _dataFuture = future);
    await future.catchError((_) => const _ListData(events: [], authUser: null));
  }

  Future<void> _signOutAndReturnToWelcome() async {
    await _tokenStorage.clear();
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const WelcomeScreen()), (route) => false);
  }

  Future<void> _onCreateEvent() async {
    // CreateEventScreen navigates straight into the new event's detail
    // screen on success (pushReplacement) rather than popping back here,
    // so this await only resolves once the user backs all the way out to
    // this screen again — a good moment for a full refresh.
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CreateEventScreen()));
    await _refresh();
  }

  Future<void> _onOpenEvent(Event event) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => EventDetailScreen(eventId: event.id)));
    _refresh();
  }

  Future<void> _onJoinEvent(Event event) async {
    try {
      await _eventApi.joinEvent(event.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Joined "${event.title}".')));
      await _onOpenEvent(event);
    } on SessionExpiredException {
      await _signOutAndReturnToWelcome();
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _EventColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _ListHeader(onCreate: _onCreateEvent),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _TabSwitcher(tab: _tab, onChanged: (tab) => setState(() => _tab = tab)),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<_ListData>(
                future: _dataFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: _EventColors.headline),
                    );
                  }

                  if (snapshot.hasError || !snapshot.hasData) {
                    final message = snapshot.error is ApiException
                        ? (snapshot.error as ApiException).message
                        : 'Could not load events.';
                    return _ErrorState(message: message, onRetry: _refresh);
                  }

                  final data = snapshot.data!;
                  final email = data.authUser?.email ?? '';
                  final visible = data.events
                      .where((e) => _tab == _EventTab.mine ? _isMine(e, email) : !_isMine(e, email))
                      .toList();

                  return RefreshIndicator(
                    onRefresh: _refresh,
                    color: _EventColors.headline,
                    backgroundColor: _EventColors.card,
                    child: visible.isEmpty
                        ? ListView(
                            padding: const EdgeInsets.fromLTRB(16, 40, 16, 24),
                            children: [
                              _EmptyState(
                                tab: _tab,
                                onCreate: _tab == _EventTab.mine ? _onCreateEvent : null,
                              ),
                            ],
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                            itemCount: visible.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 16),
                            itemBuilder: (context, index) {
                              final event = visible[index];
                              return _EventHeroCard(
                                event: event,
                                showJoinButton: _tab == _EventTab.discover,
                                onTap: () => _onOpenEvent(event),
                                onJoin: () => _onJoinEvent(event),
                              );
                            },
                          ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNav(
        currentTab: AppTab.vote,
        onTabSelected: (tab) => navigateToTab(context, AppTab.vote, tab),
      ),
    );
  }
}

enum _EventTab { mine, discover }

/// An event counts as "mine" if the signed-in user hosts it, or if it's
/// private (the list endpoint only ever returns a private event to its
/// host or an invited guest, so either way it's not something to
/// "discover"). See the TODO on [EventsLandingScreen] for the one case
/// this can't detect: a public event the user has already joined.
bool _isMine(Event event, String currentUserEmail) =>
    event.host == currentUserEmail || event.visibility == eventVisibilityPrivate;

class _ListData {
  const _ListData({required this.events, required this.authUser});

  final List<Event> events;
  final AuthUser? authUser;
}

class _ListHeader extends StatelessWidget {
  const _ListHeader({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Track Vote',
              style: TextStyle(
                fontFamily: 'Sora',
                fontWeight: FontWeight.w800,
                fontSize: 28,
                color: _EventColors.body,
              ),
            ),
          ),
          IconButton(
            onPressed: onCreate,
            style: IconButton.styleFrom(backgroundColor: _EventColors.card, shape: const CircleBorder()),
            icon: const Icon(Icons.add_rounded, color: _EventColors.body),
          ),
        ],
      ),
    );
  }
}

class _TabSwitcher extends StatelessWidget {
  const _TabSwitcher({required this.tab, required this.onChanged});

  final _EventTab tab;
  final ValueChanged<_EventTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: _EventColors.card, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          Expanded(
            child: _TabButton(
              label: 'My Events',
              isSelected: tab == _EventTab.mine,
              onTap: () => onChanged(_EventTab.mine),
            ),
          ),
          Expanded(
            child: _TabButton(
              label: 'Discover',
              isSelected: tab == _EventTab.discover,
              onTap: () => onChanged(_EventTab.discover),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({required this.label, required this.isSelected, required this.onTap});

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? _EventColors.cardBorder : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Sora',
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: isSelected ? _EventColors.body : _EventColors.muted,
          ),
        ),
      ),
    );
  }
}

class _EventHeroCard extends StatelessWidget {
  const _EventHeroCard({
    required this.event,
    required this.showJoinButton,
    required this.onTap,
    required this.onJoin,
  });

  final Event event;

  /// Only public events not already hosted by the signed-in user offer a
  /// "Join Event" action — everything under "My Events" already has
  /// access, so it gets "View Details" instead.
  final bool showJoinButton;
  final VoidCallback onTap;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          color: _EventColors.card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _EventColors.cardBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  height: 140,
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [_EventColors.gradientStart, _EventColors.gradientEnd],
                    ),
                  ),
                  child: const Center(
                    child: Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 56),
                  ),
                ),
                if (event.votingIsOpen) const Positioned(top: 12, left: 12, child: LiveBadge()),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${event.songCount} ${event.songCount == 1 ? 'song' : 'songs'}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: const TextStyle(
                      fontFamily: 'Sora',
                      fontWeight: FontWeight.w800,
                      fontSize: 19,
                      color: _EventColors.body,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Hosted by ${event.host}',
                    style: const TextStyle(fontSize: 13, color: _EventColors.muted),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      EventVisibilityBadge(visibility: event.visibility),
                      EventLicenseBadge(votePermission: event.votePermission),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    event.votingIsOpen
                        ? '${event.songCount} songs queued — voting is live'
                        : 'Waiting for songs — need at least 2 to start voting',
                    style: const TextStyle(fontSize: 12.5, color: _EventColors.muted, fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerRight,
                    child: showJoinButton
                        ? _GradientButton(label: 'Join Event', onTap: onJoin)
                        : _OutlinedPillButton(label: 'View Details', onTap: onTap),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(colors: [_EventColors.gradientStart, _EventColors.gradientEnd]),
      ),
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: Text(label, style: const TextStyle(fontFamily: 'Sora', fontWeight: FontWeight.w700, fontSize: 13)),
      ),
    );
  }
}

class _OutlinedPillButton extends StatelessWidget {
  const _OutlinedPillButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: _EventColors.body,
        side: const BorderSide(color: _EventColors.cardBorder),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Text(label, style: const TextStyle(fontFamily: 'Sora', fontWeight: FontWeight.w700, fontSize: 13)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.tab, required this.onCreate});

  final _EventTab tab;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final message = tab == _EventTab.mine
        ? "You don't have any events yet."
        : 'Nothing public to discover right now.';

    return Column(
      children: [
        const Icon(Icons.how_to_vote_rounded, size: 40, color: _EventColors.muted),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center, style: const TextStyle(color: _EventColors.body)),
        if (onCreate != null) ...[
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: onCreate,
            style: OutlinedButton.styleFrom(
              foregroundColor: _EventColors.tertiary,
              side: const BorderSide(color: _EventColors.tertiary),
            ),
            child: const Text('Host an Event'),
          ),
        ],
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, color: _EventColors.muted, size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: _EventColors.body)),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => onRetry(),
              style: OutlinedButton.styleFrom(
                foregroundColor: _EventColors.tertiary,
                side: const BorderSide(color: _EventColors.tertiary),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
