import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/auth_api.dart';
import '../auth/auth_models.dart';
import '../auth/welcome_screen.dart';
import '../core/api/api_client.dart';
import '../core/auth/token_storage.dart';
import '../core/playback/playback_controller.dart';
import '../playlists/playlist_api.dart';
import '../profile/profile_api.dart';
import '../profile/profile_avatar.dart';
import '../profile/profile_models.dart';
import '../profile/profile_preview_sheet.dart';
import 'event_api.dart';
import 'event_models.dart';
import 'event_widgets.dart';
import 'event_guests_screen.dart';
import 'event_settings_screen.dart';
import 'location_label.dart';
import 'suggest_track_screen.dart';

class _EventColors {
  static const background = Color(0xFF0E0E15);
  static const card = Color(0xFF17161F);
  static const cardBorder = Color(0xFF2A2935);
  static const headline = Color(0xFFC0C1FF);
  static const body = Color(0xFFE4E1EB);
  static const muted = Color(0xFF908FA0);
  static const tertiary = Color(0xFF2FD9F4);
}

/// The shared live queue. Polls and post-vote refreshes always replace the
/// local list with the server response, which owns vote ordering.
class EventDetailScreen extends StatefulWidget {
  const EventDetailScreen({super.key, required this.eventId});
  final int eventId;

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  static const _pollInterval = Duration(seconds: 5);

  final _eventApi = EventApi();
  final _authApi = AuthApi();
  final _profileApi = ProfileApi();
  final _tokenStorage = TokenStorage();
  final _playback = PlaybackController.instance;
  final _trackApi = PlaylistApi();
  final Set<int> _changingVotes = <int>{};
  var _isTogglingLike = false;
  Timer? _pollTimer;
  StreamSubscription<String>? _previewCompleteSub;
  var _isLoading = true;
  String? _loadError;
  String? _voteRestrictionReason;
  var _isPrivateAccessDenied = false;
  Event? _event;
  AuthUser? _authUser;
  List<EventSong> _queue = const [];

  /// Invited guests — the "Invited" tab of the participants sheet.
  /// Visible to anyone who can see the event at all: `GET .../guests/`
  /// is gated by the same `can_user_see_event` check as the event detail
  /// fetch itself, so there's no extra permission concern in fetching
  /// this unconditionally alongside it.
  List<EventGuest> _guests = const [];

  /// Everyone who's self-joined the event — the "Joined" tab. Same
  /// visibility gate as [_guests]; see `GET .../attendees/`.
  List<EventMembership> _attendees = const [];

  /// The signed-in user's own profile — specifically [UserProfile.location]
  /// (a free-text field like "Paris, France", set in Edit Profile), which
  /// is what a location-restricted event's voting check is resolved
  /// against instead of a live GPS fix; see [_voterCoordinates].
  UserProfile? _myProfile;

  /// A song this screen already tried to auto-play and found unplayable
  /// (no preview URL) — guards against retrying it on every poll tick
  /// until the leader actually changes.
  int? _autoPlayFailedSongId;

  /// The event's "now playing" song — straight from the backend's
  /// authoritative `Event.currentSong` (see DECISIONS.md). This screen
  /// never computes "what's current" itself from the local queue; it only
  /// ever displays and plays whatever the server last reported, which the
  /// server keeps advancing by wall-clock time on its own regardless of
  /// whether any client is connected.
  EventSong? get _currentlyPlaying => _event?.currentSong;

  /// `event.host` renders server-side as `str(user)` (`StringRelatedField`),
  /// which is the user's `username`, not their `email` — see the same note
  /// on `_isMine` in events_landing_screen.dart. This is the single gate on
  /// both the cover's "..." menu button and the participants sheet's
  /// invite/remove actions — nothing else checks host status separately.
  bool get _isHost => _authUser?.username == _event?.host;

  @override
  void initState() {
    super.initState();
    _playback.visibleEventId = widget.eventId;
    _previewCompleteSub = _playback.onCompleted.listen((trackKey) {
      if (mounted && trackKey.startsWith('event:${widget.eventId}:')) {
        unawaited(_onLocalPlaybackFinished(trackKey));
      }
    });
    _loadAll();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _pollState());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _previewCompleteSub?.cancel();
    if (_playback.visibleEventId == widget.eventId) {
      _playback.visibleEventId = null;
    }
    // Leaving only ever stops what *this device* renders — it never
    // mutates the event's shared state, which keeps moving forward for
    // everyone else regardless (see DECISIONS.md).
    if (_playback.state.value.trackKey?.startsWith('event:${widget.eventId}:') ??
        false) {
      unawaited(_playback.stop());
    }
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait([
        _eventApi.getEvent(widget.eventId),
        _eventApi.listQueue(widget.eventId),
        _authApi.getCurrentUser(),
        _eventApi.listGuests(widget.eventId),
        _eventApi.listAttendees(widget.eventId),
        _profileApi.getMyProfile(),
      ]);
      if (!mounted) return;
      final event = results[0] as Event;
      setState(() {
        _event = event;
        _queue = results[1] as List<EventSong>;
        _authUser = results[2] as AuthUser;
        _guests = results[3] as List<EventGuest>;
        _attendees = results[4] as List<EventMembership>;
        _myProfile = results[5] as UserProfile;
        _isLoading = false;
      });
      _syncAutoPlay();
      unawaited(_checkLocationRestrictionUpfront(event));
    } on SessionExpiredException {
      await _signOutAndReturnToWelcome();
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.statusCode == 403) {
        _pollTimer?.cancel();
        setState(() {
          _isLoading = false;
          _isPrivateAccessDenied = true;
        });
        return;
      }
      setState(() {
        _isLoading = false;
        _loadError = error.message;
      });
    }
  }

  Future<void> _pollState() async {
    if (_isLoading || _changingVotes.isNotEmpty) return;
    try {
      await _refetchState();
    } on SessionExpiredException {
      await _signOutAndReturnToWelcome();
    } on ApiException {
      // Keep the last known live state on a transient background failure.
    }
  }

  /// Re-fetches both the event (for `currentSong`/`currentPositionSeconds`)
  /// and the queue, and replaces local state with the response wholesale —
  /// this is the only source of truth for what's current; nothing here is
  /// ever computed or assumed locally (see DECISIONS.md).
  Future<void> _refetchState() async {
    final results = await Future.wait([
      _eventApi.getEvent(widget.eventId),
      _eventApi.listQueue(widget.eventId),
    ]);
    if (!mounted) return;
    setState(() {
      _event = results[0] as Event;
      _queue = results[1] as List<EventSong>;
    });
    _syncAutoPlay();
  }

  /// Fires when this device's local audio naturally reaches the end of
  /// whatever it was playing for this event. Always refetches so the
  /// backend's authoritative state — which may already have moved on — is
  /// picked up promptly, without waiting out the rest of the poll interval
  /// for a track change this device has already heard end.
  ///
  /// A [songPlaybackTypePreview] clip is physically only
  /// [songPreviewClipSeconds] of actual audio, however much longer the
  /// backend is treating the song as "current" for (see DECISIONS.md).
  /// [_refetchState]'s own [_syncAutoPlay] call already starts whatever
  /// *new* song the backend reports — but if it reports the *same* song
  /// still current, that guard deliberately won't restart a track it
  /// thinks is already playing. Here, we know better: this specific track
  /// just genuinely ran out locally, so the only alternative to sitting in
  /// silence for however much of the song's real duration remains is
  /// looping that same clip again from the top.
  Future<void> _onLocalPlaybackFinished(String finishedTrackKey) async {
    await _refetchState();
    if (!mounted) return;
    final playing = _currentlyPlaying;
    if (playing != null && _playbackKey(playing.id) == finishedTrackKey) {
      await _startAutoPlay(playing, _localStartPosition(playing));
    }
  }

  /// Where this device should start local playback of [entry], derived
  /// from the backend's authoritative `currentPositionSeconds`. A
  /// [songPlaybackTypePreview] clip only ever contains
  /// [songPreviewClipSeconds] of real audio no matter how long the backend
  /// considers the song "current" for, so its position is wrapped into
  /// that window — otherwise a song already minutes into its backend
  /// timer would seek past the end of the ~30-second file that's all
  /// there actually is. A [songPlaybackTypeFull] stream has no such gap,
  /// so its real elapsed position is used as-is.
  Duration _localStartPosition(EventSong entry) {
    final seconds = _event?.currentPositionSeconds ?? 0;
    final wrapped = entry.song.playbackType == songPlaybackTypePreview
        ? seconds % songPreviewClipSeconds
        : seconds;
    return Duration(milliseconds: (wrapped * 1000).round());
  }

  /// Resolves the coordinates to submit with a vote when [event] is
  /// location-restricted — sourced from the signed-in user's *profile*
  /// location (`Profile.location`, a free-text field like "Paris, France",
  /// set in Edit Profile), not a live GPS fix — see DECISIONS.md. Throws a
  /// [String] with a user-facing reason (surfaced via
  /// [VoteNotPermittedException]'s handling, same as any other rejection)
  /// if the profile has no location set, or if it can't be resolved to
  /// real-world coordinates at all. Whether those coordinates end up
  /// *close enough* to the venue is left to the backend's existing
  /// `can_user_vote` distance check — this only ever resolves and hands
  /// off a coordinate, it doesn't itself decide "too far".
  Future<({double latitude, double longitude})?> _voterCoordinates(Event event) async {
    if (!event.locationRestrictionEnabled) return null;

    final location = _myProfile?.location.trim() ?? '';
    if (location.isEmpty) {
      throw 'Set your location in your profile to vote in this event.';
    }

    final coordinates = await forwardGeocodeCoordinates(location);
    if (coordinates == null) {
      throw 'We couldn\'t find "$location" — check your location in your profile.';
    }
    return coordinates;
  }

  /// Proactive counterpart to [_voterCoordinates] — run once after
  /// [_loadAll] (not on every poll tick) so a location-restricted event
  /// that's clearly unvotable shows the "Voting Restricted" card
  /// immediately, rather than only after the user taps vote and hits a
  /// 403. Only ever *sets* [_voteRestrictionReason]; it never clears one,
  /// since a reason already showing might be for an unrelated restriction
  /// (time, invited-only) that this check has no way to re-verify without
  /// an actual vote attempt.
  Future<void> _checkLocationRestrictionUpfront(Event event) async {
    if (!event.locationRestrictionEnabled) return;

    String? reason;
    try {
      final coordinates = await _voterCoordinates(event);
      final venueLatitude = event.venueCenterLatitude;
      final venueLongitude = event.venueCenterLongitude;
      final allowedDistance = event.allowedDistanceMeters;
      if (coordinates != null &&
          venueLatitude != null &&
          venueLongitude != null &&
          allowedDistance != null) {
        final distance = distanceInMeters(
          venueLatitude,
          venueLongitude,
          coordinates.latitude,
          coordinates.longitude,
        );
        if (distance > allowedDistance) {
          reason = 'Your profile location is too far from the venue to vote on this event.';
        }
      }
    } on String catch (message) {
      reason = message;
    }
    if (mounted && reason != null) setState(() => _voteRestrictionReason = reason);
  }

  String _playbackKey(int? songId) => 'event:${widget.eventId}:$songId';

  /// There is no manual playback control in an event — this is the only
  /// thing that starts (or restarts) audio, and it always targets whatever
  /// [_currentlyPlaying] currently resolves to. If that song is already
  /// the active track, this is a no-op, so calling it on every poll tick
  /// doesn't restart playback mid-clip for no reason — the client never
  /// re-seeks a track it's already playing to "correct" small drift, it
  /// only ever seeks once, at the moment it starts a track it wasn't
  /// already playing (a fresh join, a rejoin, or a genuine track change).
  /// That's what puts a newly (re)joining listener wherever everyone else
  /// already is, per [_event]'s `currentPositionSeconds`.
  void _syncAutoPlay() {
    final playing = _currentlyPlaying;
    if (playing == null) return;
    if (playing.id == _autoPlayFailedSongId) return;
    if (_playback.state.value.trackKey == _playbackKey(playing.id)) return;
    unawaited(_startAutoPlay(playing, _localStartPosition(playing)));
  }

  /// Re-resolves a fresh preview URL from [entry.song.externalId] when one
  /// is present — Deezer preview URLs can go stale — falling back to the
  /// stored [Song.previewUrl] for manually-added songs. Starts at
  /// [position] rather than 0 so this device lands in sync with everyone
  /// else already listening, per the backend's authoritative elapsed time.
  Future<void> _startAutoPlay(EventSong entry, Duration position) async {
    try {
      final previewUrl = entry.song.externalId.isEmpty
          ? entry.song.previewUrl
          : await _trackApi.resolvePreviewUrl(entry.song.externalId);
      if (previewUrl.isEmpty) throw StateError('No preview URL available.');
      await _playback.play(
        url: previewUrl,
        trackKey: _playbackKey(entry.id),
        title: entry.song.title,
        artist: entry.song.artist,
        artworkUrl: entry.song.albumArtUrl,
        position: position,
      );
      if (mounted) setState(() => _autoPlayFailedSongId = null);
    } catch (_) {
      // Silent — this is background/automatic, not a user action; a
      // snackbar every poll tick for a song with no preview would spam.
      if (mounted) setState(() => _autoPlayFailedSongId = entry.id);
    }
  }

  Future<void> _toggleVote(EventSong entry) async {
    final event = _event;
    if (event == null || _changingVotes.contains(entry.id)) return;
    setState(() => _changingVotes.add(entry.id));
    try {
      if (entry.hasVoted) {
        await _eventApi.retractVote(widget.eventId, entry.id);
      } else {
        final coordinates = await _voterCoordinates(event);
        await _eventApi.vote(
          widget.eventId,
          entry.id,
          latitude: coordinates?.latitude,
          longitude: coordinates?.longitude,
        );
      }
      await _refetchState();
    } on SessionExpiredException {
      await _signOutAndReturnToWelcome();
    } on VoteNotPermittedException catch (error) {
      if (mounted) setState(() => _voteRestrictionReason = error.message);
    } on ApiException catch (error) {
      _showMessage(error.message);
    } on String catch (message) {
      _showMessage(message);
    } finally {
      if (mounted) setState(() => _changingVotes.remove(entry.id));
    }
  }

  /// Likes/unlikes the event itself (`Event.hasLiked`/`likeCount`) — not
  /// tied to hosting, joining, or voting; anyone who can see the event
  /// can toggle this. Always refetches afterward rather than updating
  /// [_event] locally, same as [_toggleVote].
  Future<void> _toggleLike() async {
    final event = _event;
    if (event == null || _isTogglingLike) return;
    setState(() => _isTogglingLike = true);
    try {
      if (event.hasLiked) {
        await _eventApi.unlikeEvent(widget.eventId);
      } else {
        await _eventApi.likeEvent(widget.eventId);
      }
      await _refetchState();
    } on SessionExpiredException {
      await _signOutAndReturnToWelcome();
    } on ApiException catch (error) {
      _showMessage(error.message);
    } finally {
      if (mounted) setState(() => _isTogglingLike = false);
    }
  }

  Future<void> _signOutAndReturnToWelcome() async {
    _pollTimer?.cancel();
    await _tokenStorage.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (_) => false,
    );
  }

  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _openSuggestTrack() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SuggestTrackScreen(eventId: widget.eventId),
      ),
    );
    await _refetchState();
  }

  Future<void> _openGuestManagement() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EventGuestsScreen(eventId: widget.eventId),
      ),
    );
    // The guest list may have just changed on that screen — keep the
    // "members" row in sync without a full reload/spinner.
    try {
      final guests = await _eventApi.listGuests(widget.eventId);
      if (mounted) setState(() => _guests = guests);
    } on ApiException {
      // Keep showing the last known guest list on a transient failure.
    }
  }

  Future<void> _openEventSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EventSettingsScreen(eventId: widget.eventId),
      ),
    );
    // The status may have just changed (e.g. closed/canceled) — refresh so
    // the badge and the "Suggest a track" gating below reflect it.
    await _refetchState();
  }

  void _showRequirements(Event event) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _EventColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => _VotingRequirementsSheet(
        event: event,
        onTryAgain: () {
          Navigator.pop(sheetContext);
          setState(() => _voteRestrictionReason = null);
        },
      ),
    );
  }

  /// Opens the "Joined"/"Invited" participants panel. Invite/remove actions
  /// inside it are gated on [_isHost] by the sheet itself — see
  /// [_ParticipantsSheet]'s own doc comment.
  void _openParticipantsSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _EventColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => _ParticipantsSheet(
        attendees: _attendees,
        guests: _guests,
        isHost: _isHost,
        currentUserId: _authUser?.id,
        onInviteMore: () {
          Navigator.pop(sheetContext);
          _openGuestManagement();
        },
        onRemoveAttendee: _removeAttendee,
        onRemoveGuest: _removeGuest,
      ),
    );
  }

  /// Host-only (see [_ParticipantsSheet]) — revokes [membership] via
  /// `DELETE .../attendees/<user_id>/` and drops it locally on success.
  Future<void> _removeAttendee(EventMembership membership) async {
    try {
      await _eventApi.removeAttendee(widget.eventId, membership.member);
      if (mounted) {
        setState(() {
          _attendees = _attendees.where((a) => a.id != membership.id).toList();
        });
      }
    } on ApiException catch (error) {
      _showMessage(error.message);
    }
  }

  /// Host-only (see [_ParticipantsSheet]) — revokes [guest]'s invitation via
  /// `DELETE .../guests/<user_id>/` and drops it locally on success.
  Future<void> _removeGuest(EventGuest guest) async {
    try {
      await _eventApi.removeGuest(widget.eventId, guest.guest);
      if (mounted) {
        setState(() {
          _guests = _guests.where((g) => g.id != guest.id).toList();
        });
      }
    } on ApiException catch (error) {
      _showMessage(error.message);
    }
  }

  /// Host-only — see the `if (isHost) ...` gate at the call site in
  /// [_buildBody] (the "..." button on the cover only exists in the tree
  /// at all when `isHost` is true; a non-host has no way to trigger this).
  /// Opens a plain bottom sheet rather than a `PopupMenuButton` — that
  /// was tried first, but `PopupMenuButton`'s own `Overlay`/`RenderBox`
  /// anchor positioning is fragile mid-route-transition and crashed with
  /// "Infinity or NaN toInt" on both entering and leaving this screen.
  void _showEventMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _EventColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => _EventMenuSheet(
        onManageGuests: () {
          Navigator.pop(sheetContext);
          _openGuestManagement();
        },
        onOpenSettings: () {
          Navigator.pop(sheetContext);
          _openEventSettings();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isPrivateAccessDenied) return const PrivateEventAccessDeniedScreen();
    return Scaffold(
      backgroundColor: _EventColors.background,
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: _EventColors.headline),
      );
    }
    final event = _event;
    if (event == null || _loadError != null) {
      return _ErrorState(
        message: _loadError ?? 'Could not load this event.',
        onRetry: _loadAll,
      );
    }

    final playing = _currentlyPlaying;
    final upNext = playing == null
        ? _queue
        : _queue.where((entry) => entry.id != playing.id).toList();
    final isVotingRestricted = _voteRestrictionReason != null;

    return RefreshIndicator(
      onRefresh: _loadAll,
      color: _EventColors.tertiary,
      backgroundColor: _EventColors.card,
      child: ValueListenableBuilder<PlaybackState>(
        valueListenable: _playback.state,
        builder: (context, playbackState, _) {
          final isPlayingHere = playing != null &&
              playbackState.trackKey == _playbackKey(playing.id);
          return ListView(
            // Horizontal inset moved to the Padding below the cover, so
            // the cover alone can span the full screen width — see
            // _CoverHeader's own doc comment for why (two fancier
            // one-item-only tricks were tried and both hit real Flutter
            // framework issues; this plain nested-Column approach has
            // none of that risk).
            padding: const EdgeInsets.only(top: 4, bottom: 32),
            children: [
              _CoverHeader(
                event: event,
                isHost: _isHost,
                onBack: () => Navigator.of(context).pop(),
                onOpenMenu: _showEventMenu,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 18),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            event.title,
                            style: const TextStyle(
                              fontFamily: 'Sora',
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: _EventColors.headline,
                            ),
                          ),
                        ),
                        _LikeButton(
                          hasLiked: event.hasLiked,
                          likeCount: event.likeCount,
                          isBusy: _isTogglingLike,
                          onTap: _toggleLike,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.person_rounded,
                          size: 15,
                          color: _EventColors.tertiary,
                        ),
                        const SizedBox(width: 4),
                        Text.rich(
                          TextSpan(
                            style: const TextStyle(
                              fontSize: 13,
                              color: _EventColors.muted,
                            ),
                            children: [
                              const TextSpan(text: 'Hosted by '),
                              TextSpan(
                                text: event.host,
                                style: const TextStyle(
                                  fontFamily: 'Sora',
                                  fontWeight: FontWeight.w700,
                                  color: _EventColors.tertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (event.description.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        event.description,
                        style: const TextStyle(
                          color: _EventColors.muted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        EventVisibilityBadge(visibility: event.visibility),
                        EventStatusBadge(status: event.status),
                        EventLicenseBadge(votePermission: event.votePermission),
                        if (event.timeRestrictionEnabled)
                          const EventTimeRestrictionBadge(),
                        if (event.locationRestrictionEnabled)
                          const EventLocationRestrictionBadge(),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _ParticipantsSummaryCard(
                      attendees: _attendees,
                      participantCount: event.participantCount,
                      maxParticipants: event.maxParticipants,
                      onTap: _openParticipantsSheet,
                    ),
                    const SizedBox(height: 28),
                    const _SectionLabel('NOW PLAYING'),
                    const SizedBox(height: 10),
                    _NowPlayingCard(
                      song: playing,
                      isPlaying: isPlayingHere && playbackState.isPlaying,
                      position: isPlayingHere ? playbackState.position : Duration.zero,
                      duration: isPlayingHere ? playbackState.duration : Duration.zero,
                    ),
                    const SizedBox(height: 28),
                    if (isVotingRestricted) ...[
                      _VotingRestrictedCard(
                        // The backend already returns a specific reason
                        // for whichever check failed (2-songs minimum,
                        // invited-only, time window, or venue distance —
                        // see can_user_vote in events/permissions.py) —
                        // no need for a generic fallback here now that
                        // time/location are independent, separately
                        // reported restrictions rather than one bundled
                        // license value.
                        message: _voteRestrictionReason!,
                        onCheckRequirements: () => _showRequirements(event),
                      ),
                      const SizedBox(height: 22),
                    ],
                    Row(
                      children: [
                        const Expanded(child: _SectionLabel('UP NEXT')),
                        Text(
                          '${upNext.length} TRACK${upNext.length == 1 ? '' : 'S'}',
                          style: const TextStyle(
                            fontFamily: 'Sora',
                            fontSize: 11,
                            letterSpacing: 1,
                            fontWeight: FontWeight.w800,
                            color: _EventColors.tertiary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // The backend only 403s POST .../queue/ for closed or
                    // canceled — NOT for the three automatic
                    // ghost_town/rip_attendance/party_of_nobody statuses,
                    // which stay fully functional (suggesting a track is
                    // exactly what un-ghosts one — see
                    // eventStatusIsAutoInactive). Gating on "isn't live"
                    // instead of "is actually blocked" was a bug: it
                    // hid this button and showed a false "this event is
                    // closed" message the moment an event went quiet.
                    if (event.status == eventStatusClosed ||
                        event.status == eventStatusCanceled ||
                        event.status == eventStatusDeleted)
                      Text(
                        event.status == eventStatusDeleted
                            ? 'This event has been deleted by the host.'
                            : event.status == eventStatusCanceled
                                ? 'This event has been canceled.'
                                : 'This event is closed — no new tracks can be suggested.',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: _EventColors.muted,
                          fontStyle: FontStyle.italic,
                        ),
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _openSuggestTrack,
                          icon: const Icon(Icons.add_rounded, size: 20),
                          label: const Text('Suggest a track'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _EventColors.tertiary,
                            side: const BorderSide(color: _EventColors.cardBorder),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    if (upNext.isEmpty)
                      const _EmptyQueue()
                    else
                      for (final entry in upNext) ...[
                        _QueueRow(
                          entry: entry,
                          isChanging: _changingVotes.contains(entry.id),
                          isReadOnly: isVotingRestricted,
                          isPlaying: playbackState.trackKey == _playbackKey(entry.id) &&
                              playbackState.isPlaying,
                          onVote: () => _toggleVote(entry),
                        ),
                        const SizedBox(height: 8),
                      ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The event's cover — full screen width, 30% of screen height, edge to
/// edge. The back button and the host-only "..." button float on top of
/// it, bottom-left carries the live/closed/canceled + visibility badges.
///
/// **The "..." button only exists in this tree at all when `isHost` is
/// true** (`if (isHost) _CircleIconButton(...)` below) — a non-host gets
/// no menu button here, full stop, not a disabled/hidden one; there is
/// no other path to open it.
class _CoverHeader extends StatelessWidget {
  const _CoverHeader({
    required this.event,
    required this.isHost,
    required this.onBack,
    required this.onOpenMenu,
  });

  final Event event;
  final bool isHost;
  final VoidCallback onBack;

  /// Host-only — opens the "Manage guests"/"Event settings" bottom sheet
  /// (`_EventDetailScreenState._showEventMenu`). A plain bottom sheet,
  /// not a `PopupMenuButton`: that was tried first, but its `Overlay`/
  /// `RenderBox` anchor positioning is fragile mid-route-transition and
  /// crashed with "Infinity or NaN toInt" on both entering and leaving
  /// this screen.
  final VoidCallback onOpenMenu;

  @override
  Widget build(BuildContext context) {
    final preset = EventCoverPreset.byId(event.coverPreset);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.3,
      width: MediaQuery.sizeOf(context).width,
      child: Stack(
        fit: StackFit.expand,
        children: [
          preset == null
              ? const _CoverHeaderFallback()
              : Image.asset(
                  preset.assetPath,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const _CoverHeaderFallback(),
                ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black87],
                stops: [0.45, 1],
              ),
            ),
          ),
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _CircleIconButton(
                  icon: Icons.arrow_back_rounded,
                  onTap: onBack,
                ),
                if (isHost)
                  _CircleIconButton(
                    icon: Icons.more_vert_rounded,
                    onTap: onOpenMenu,
                  ),
              ],
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (event.status == eventStatusClosed)
                  const EventOverlayStatusBadge(
                    label: 'CLOSED',
                    color: EventBadgeColors.statusClosed,
                  )
                else if (event.status == eventStatusCanceled)
                  const EventOverlayStatusBadge(
                    label: 'CANCELED',
                    color: EventBadgeColors.statusCanceled,
                  )
                else if (event.status == eventStatusDeleted)
                  const EventOverlayStatusBadge(
                    label: 'DELETED',
                    color: EventBadgeColors.statusDeleted,
                  )
                // The three auto-inactive rungs (see eventStatusIsAutoInactive)
                // are a label only — voting/joining/suggesting all stay open
                // exactly as on a live event — but "LIVE" pulsing here would
                // actively contradict what the event card / status badge
                // elsewhere already say, so this overlay spot goes to
                // whichever's currently true instead.
                else if (event.status == eventStatusGhostTown)
                  const EventOverlayStatusBadge(
                    label: 'GHOST TOWN 👻',
                    color: EventBadgeColors.statusGhostTown,
                  )
                else if (event.status == eventStatusRipAttendance)
                  const EventOverlayStatusBadge(
                    label: 'RIP ATTENDANCE',
                    color: EventBadgeColors.statusRipAttendance,
                  )
                else if (event.status == eventStatusPartyOfNobody)
                  const EventOverlayStatusBadge(
                    label: 'PARTY OF NOBODY',
                    color: EventBadgeColors.statusPartyOfNobody,
                  )
                else if (event.votingIsOpen)
                  const LiveBadge(),
                EventVisibilityBadge(visibility: event.visibility),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverHeaderFallback extends StatelessWidget {
  const _CoverHeaderFallback();
  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF8083FF), Color(0xFF494BD6)],
      ),
    ),
    child: Center(
      child: Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 48),
    ),
  );
}

/// A small circular button matching the semi-transparent-over-photo style
/// both the back button and the cover's host-only menu button use.
class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black.withValues(alpha: 0.35),
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    ),
  );
}

/// The host-only "Manage guests"/"Event settings" bottom sheet opened by
/// tapping the cover's "..." button (see `_EventDetailScreenState._showEventMenu`
/// — that method is only ever wired to a button that exists for the host).
class _EventMenuSheet extends StatelessWidget {
  const _EventMenuSheet({
    required this.onManageGuests,
    required this.onOpenSettings,
  });
  final VoidCallback onManageGuests;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.group_rounded, color: _EventColors.tertiary),
            title: const Text('Manage guests', style: TextStyle(color: _EventColors.body)),
            onTap: onManageGuests,
          ),
          ListTile(
            leading: const Icon(Icons.settings_rounded, color: _EventColors.tertiary),
            title: const Text('Event settings', style: TextStyle(color: _EventColors.body)),
            onTap: onOpenSettings,
          ),
        ],
      ),
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(
      fontFamily: 'Sora',
      fontSize: 11,
      letterSpacing: 1.1,
      fontWeight: FontWeight.w800,
      color: _EventColors.body,
    ),
  );
}

/// Heart icon + like count, sat next to the event title. Tapping toggles
/// [Event.hasLiked] via [_EventDetailScreenState._toggleLike] — anyone who
/// can see the event can like it, independent of hosting/joining/voting.
class _LikeButton extends StatelessWidget {
  const _LikeButton({
    required this.hasLiked,
    required this.likeCount,
    required this.isBusy,
    required this.onTap,
  });

  final bool hasLiked;
  final int likeCount;
  final bool isBusy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: isBusy ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          children: [
            Icon(
              hasLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: hasLiked ? EventBadgeColors.statusCanceled : _EventColors.muted,
              size: 24,
            ),
            const SizedBox(height: 2),
            Text(
              '$likeCount',
              style: TextStyle(
                fontFamily: 'Sora',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: hasLiked ? EventBadgeColors.statusCanceled : _EventColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The collapsed "Participants" card — a stack of the first few joined
/// people's avatars + a count, tapping into the full [_ParticipantsSheet]
/// (Joined/Invited tabs). The avatar stack shows [EventMembership]
/// ("Joined") people specifically, matching the shared mockup's collapsed
/// state — the "Invited" list lives one tap away, inside the sheet. The
/// count text always shows the combined guests+members [participantCount]
/// against [maxParticipants], since that's what the limit is actually
/// measured against — a "3 joined" reading would be misleading against a
/// "10" cap that also counts invited guests.
class _ParticipantsSummaryCard extends StatelessWidget {
  const _ParticipantsSummaryCard({
    required this.attendees,
    required this.participantCount,
    required this.maxParticipants,
    required this.onTap,
  });
  final List<EventMembership> attendees;

  /// Combined distinct guests + members (`Event.participantCount`) — what
  /// [maxParticipants] caps. Shown here instead of `attendees.length`,
  /// since the limit applies to the combined total, not just self-joined
  /// members.
  final int participantCount;

  /// `Event.maxParticipants` — always set (2-100); there's no "unlimited"
  /// option.
  final int maxParticipants;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final names = attendees
        .map((a) => a.memberDisplayName.isNotEmpty ? a.memberDisplayName : a.memberEmail)
        .toList();
    final isFull = participantCount >= maxParticipants;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _EventColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _EventColors.cardBorder),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Row(
          children: [
            _AvatarStack(names: names),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'PARTICIPANTS',
                    style: TextStyle(
                      fontFamily: 'Sora',
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: _EventColors.tertiary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$participantCount / $maxParticipants joined',
                    style: TextStyle(
                      fontFamily: 'Sora',
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: isFull ? EventBadgeColors.statusCanceled : _EventColors.body,
                    ),
                  ),
                  if (isFull) ...[
                    const SizedBox(height: 2),
                    const Text(
                      'Full',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: EventBadgeColors.statusCanceled,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: _EventColors.muted),
          ],
        ),
      ),
    );
  }
}

/// Just the overlapping avatar circles (+ overflow count) — used inside
/// [_ParticipantsSummaryCard], which supplies its own label and count text
/// around it.
class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.names});
  final List<String> names;
  @override
  Widget build(BuildContext context) {
    const displayed = 4;
    final people = names.take(displayed).toList();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < people.length; i++)
          Transform.translate(
            offset: Offset(-i * 8.0, 0),
            child: _Avatar(people[i]),
          ),
        if (names.length > displayed)
          Transform.translate(
            offset: Offset(-displayed * 8.0, 0),
            child: _CountAvatar(names.length - displayed),
          ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: CircleAvatar(
      radius: 15,
      backgroundColor: _EventColors.cardBorder,
      child: Text(
        label.isEmpty ? '?' : label[0].toUpperCase(),
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 12,
          color: _EventColors.tertiary,
        ),
      ),
    ),
  );
}

class _CountAvatar extends StatelessWidget {
  const _CountAvatar(this.count);
  final int count;
  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: 15,
    backgroundColor: _EventColors.cardBorder,
    child: Text(
      '+$count',
      style: const TextStyle(fontSize: 10, color: _EventColors.body),
    ),
  );
}

/// Opened by tapping [_ParticipantsSummaryCard] — "Joined" ([EventMembership])
/// and "Invited" ([EventGuest]) as two searchable tabs.
///
/// Inviting and removing are both host-only ("the host is the only one who
/// can invite people") — gated purely on [isHost]: a non-host sees neither
/// the "Invite More Friends" button nor any row's "..." action, full stop,
/// matching the same all-or-nothing gating `_CoverHeader` uses for its own
/// host-only menu button.
///
/// Keeps its own local copies of [attendees]/[guests] (seeded from the
/// constructor in `initState`) rather than reading `widget.attendees`/
/// `widget.guests` directly — this sheet is a separate overlay route, so it
/// wouldn't otherwise see the parent screen's list update after a removal
/// until closed and reopened.
class _ParticipantsSheet extends StatefulWidget {
  const _ParticipantsSheet({
    required this.attendees,
    required this.guests,
    required this.isHost,
    required this.currentUserId,
    required this.onInviteMore,
    required this.onRemoveAttendee,
    required this.onRemoveGuest,
  });

  final List<EventMembership> attendees;
  final List<EventGuest> guests;
  final bool isHost;

  /// The signed-in user's own id — threaded through to [showProfilePreview]
  /// so tapping your own row (you can be a plain member/guest of an event
  /// you don't host) is a no-op instead of previewing yourself.
  final int? currentUserId;
  final VoidCallback onInviteMore;
  final Future<void> Function(EventMembership) onRemoveAttendee;
  final Future<void> Function(EventGuest) onRemoveGuest;

  @override
  State<_ParticipantsSheet> createState() => _ParticipantsSheetState();
}

class _ParticipantsSheetState extends State<_ParticipantsSheet> {
  var _tab = 0;
  var _query = '';
  late List<EventMembership> _attendees;
  late List<EventGuest> _guests;

  @override
  void initState() {
    super.initState();
    _attendees = widget.attendees;
    _guests = widget.guests;
  }

  @override
  Widget build(BuildContext context) {
    final joined = _attendees.where(_matchesMember).toList();
    final invited = _guests.where(_matchesGuest).toList();

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.85,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Participants',
                style: TextStyle(
                  fontFamily: 'Sora',
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _EventColors.body,
                ),
              ),
              const SizedBox(height: 16),
              _ParticipantsTabSwitcher(
                joinedLabel: 'Joined (${_attendees.length})',
                invitedLabel: 'Invited (${_guests.length})',
                selectedIndex: _tab,
                onChanged: (index) => setState(() => _tab = index),
              ),
              const SizedBox(height: 14),
              TextField(
                onChanged: (value) => setState(() => _query = value),
                style: const TextStyle(color: _EventColors.body),
                decoration: InputDecoration(
                  hintText: 'Search participants',
                  hintStyle: const TextStyle(color: _EventColors.muted),
                  prefixIcon: const Icon(Icons.search_rounded, color: _EventColors.tertiary),
                  filled: true,
                  fillColor: _EventColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: _tab == 0
                    ? (joined.isEmpty
                        ? const _EmptyParticipants(message: 'No one has joined yet.')
                        : ListView.separated(
                            itemCount: joined.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final entry = joined[index];
                              final name = entry.memberDisplayName.isNotEmpty
                                  ? entry.memberDisplayName
                                  : entry.memberEmail;
                              return _ParticipantRow(
                                name: name,
                                username: entry.memberUsername,
                                avatar: entry.memberAvatar,
                                avatarType: entry.memberAvatarType,
                                onTap: () => showProfilePreview(
                                  context,
                                  userId: entry.member,
                                  currentUserId: widget.currentUserId,
                                  initialName: name,
                                  initialUsername: entry.memberUsername,
                                  initialAvatar: entry.memberAvatar,
                                  initialAvatarType: entry.memberAvatarType,
                                ),
                                onRemove: widget.isHost
                                    ? () => _confirmAndRemoveAttendee(entry)
                                    : null,
                              );
                            },
                          ))
                    : (invited.isEmpty
                        ? const _EmptyParticipants(message: 'No one has been invited yet.')
                        : ListView.separated(
                            itemCount: invited.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final entry = invited[index];
                              final name = entry.guestDisplayName.isNotEmpty
                                  ? entry.guestDisplayName
                                  : entry.guestEmail;
                              return _ParticipantRow(
                                name: name,
                                username: entry.guestUsername,
                                avatar: entry.guestAvatar,
                                avatarType: entry.guestAvatarType,
                                onTap: () => showProfilePreview(
                                  context,
                                  userId: entry.guest,
                                  currentUserId: widget.currentUserId,
                                  initialName: name,
                                  initialUsername: entry.guestUsername,
                                  initialAvatar: entry.guestAvatar,
                                  initialAvatarType: entry.guestAvatarType,
                                ),
                                onRemove:
                                    widget.isHost ? () => _confirmAndRemoveGuest(entry) : null,
                              );
                            },
                          )),
              ),
              if (widget.isHost) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: widget.onInviteMore,
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                    label: const Text('Invite More Friends'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _EventColors.tertiary,
                      foregroundColor: const Color(0xFF15151C),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: const StadiumBorder(),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  bool _matchesMember(EventMembership m) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return m.memberDisplayName.toLowerCase().contains(q) ||
        m.memberUsername.toLowerCase().contains(q) ||
        m.memberEmail.toLowerCase().contains(q);
  }

  bool _matchesGuest(EventGuest g) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return g.guestDisplayName.toLowerCase().contains(q) ||
        g.guestUsername.toLowerCase().contains(q) ||
        g.guestEmail.toLowerCase().contains(q);
  }

  Future<void> _confirmAndRemoveAttendee(EventMembership entry) async {
    final name = entry.memberDisplayName.isNotEmpty ? entry.memberDisplayName : entry.memberEmail;
    if (!await _confirmRemoveFromEvent(context, name)) return;
    await widget.onRemoveAttendee(entry);
    if (mounted) {
      setState(() => _attendees = _attendees.where((a) => a.id != entry.id).toList());
    }
  }

  Future<void> _confirmAndRemoveGuest(EventGuest entry) async {
    final name = entry.guestDisplayName.isNotEmpty ? entry.guestDisplayName : entry.guestEmail;
    if (!await _confirmRemoveFromEvent(context, name)) return;
    await widget.onRemoveGuest(entry);
    if (mounted) {
      setState(() => _guests = _guests.where((g) => g.id != entry.id).toList());
    }
  }
}

/// Confirms a host-only removal before it fires — mirrors
/// `EventSettingsScreen`'s own cancel-event confirmation dialog.
Future<bool> _confirmRemoveFromEvent(BuildContext context, String name) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: _EventColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        'Remove from event?',
        style: TextStyle(fontFamily: 'Sora', color: _EventColors.body),
      ),
      content: Text(
        '${name.isEmpty ? 'This person' : name} will lose access and have to be invited '
        'again to rejoin.',
        style: const TextStyle(color: _EventColors.muted),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel', style: TextStyle(color: _EventColors.muted)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Remove', style: TextStyle(color: Color(0xFFFFB4AB))),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

class _ParticipantsTabSwitcher extends StatelessWidget {
  const _ParticipantsTabSwitcher({
    required this.joinedLabel,
    required this.invitedLabel,
    required this.selectedIndex,
    required this.onChanged,
  });
  final String joinedLabel;
  final String invitedLabel;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: _EventColors.background,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      children: [
        Expanded(
          child: _ParticipantsTabButton(
            label: joinedLabel,
            isSelected: selectedIndex == 0,
            onTap: () => onChanged(0),
          ),
        ),
        Expanded(
          child: _ParticipantsTabButton(
            label: invitedLabel,
            isSelected: selectedIndex == 1,
            onTap: () => onChanged(1),
          ),
        ),
      ],
    ),
  );
}

class _ParticipantsTabButton extends StatelessWidget {
  const _ParticipantsTabButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
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
          fontSize: 13,
          color: isSelected ? _EventColors.body : _EventColors.muted,
        ),
      ),
    ),
  );
}

/// One row in [_ParticipantsSheet] — avatar, display name, "@username"
/// (hidden when empty), and a host-only "..." that confirms-then-removes
/// (see [_confirmRemoveFromEvent]). [onRemove] is only ever non-null when
/// the signed-in user is the host — a non-host gets no trailing icon here
/// at all, not a disabled one.
/// One row in [_ParticipantsSheet]'s Joined/Invited list. The whole row
/// (avatar included) opens [showProfilePreview] on tap — a separate
/// tap target from the trailing "..." remove button, which stays
/// host-only and independent of it.
class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({
    required this.name,
    required this.username,
    required this.avatar,
    required this.avatarType,
    required this.onTap,
    required this.onRemove,
  });
  final String name;
  final String username;
  final String? avatar;
  final String avatarType;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: _EventColors.background,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _EventColors.cardBorder),
    ),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            _ParticipantAvatar(name: name, avatar: avatar, avatarType: avatarType),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? 'Unknown' : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, color: _EventColors.body),
                  ),
                  if (username.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      '@$username',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: _EventColors.muted),
                    ),
                  ],
                ],
              ),
            ),
            if (onRemove != null)
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.more_vert_rounded, color: _EventColors.muted, size: 20),
                tooltip: 'Remove from event',
              ),
          ],
        ),
      ),
    ),
  );
}

/// The real profile photo when [avatar] is set, falling back to the
/// initials-based [_Avatar] otherwise — same 30x30 footprint either way.
class _ParticipantAvatar extends StatelessWidget {
  const _ParticipantAvatar({required this.name, required this.avatar, required this.avatarType});
  final String name;
  final String? avatar;
  final String avatarType;

  @override
  Widget build(BuildContext context) => ClipOval(
    child: SizedBox(
      width: 30,
      height: 30,
      child: ProfileAvatarImage(
        avatar: avatar,
        avatarType: avatarType,
        fallback: _Avatar(name),
      ),
    ),
  );
}

class _EmptyParticipants extends StatelessWidget {
  const _EmptyParticipants({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Center(
    child: Text(message, style: const TextStyle(color: _EventColors.muted)),
  );
}

class _NowPlayingCard extends StatelessWidget {
  const _NowPlayingCard({
    required this.song,
    required this.isPlaying,
    required this.position,
    required this.duration,
  });
  final EventSong? song;

  /// Whether *this* song is the one actually coming out of the speaker
  /// right now. There's no play/pause control here — playback always
  /// tracks the vote leader on its own (see `_syncAutoPlay`), so this is
  /// purely informational.
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  @override
  Widget build(BuildContext context) {
    final song = this.song;
    if (song == null) return const _EmptyNowPlaying();
    final progress = duration == Duration.zero
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0, 1).toDouble();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _EventColors.card,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _EventColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: _EventColors.tertiary.withValues(alpha: .12),
            blurRadius: 24,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: _AlbumArt(size: 112, url: song.song.albumArtUrl, isPlaying: isPlaying),
          ),
          const SizedBox(height: 22),
          Text(
            song.song.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Sora',
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: _EventColors.body,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            song.song.artist,
            style: const TextStyle(
              fontFamily: 'Sora',
              fontWeight: FontWeight.w700,
              color: _EventColors.muted,
            ),
          ),
          const SizedBox(height: 20),
          LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            borderRadius: const BorderRadius.all(Radius.circular(9)),
            color: _EventColors.tertiary,
            backgroundColor: _EventColors.cardBorder,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isPlaying ? _formatTime(position) : 'Not started',
                style: const TextStyle(fontSize: 11, color: _EventColors.muted),
              ),
              Text(
                duration != Duration.zero ? _formatTime(duration) : _duration(song.song.durationSeconds),
                style: const TextStyle(fontSize: 11, color: _EventColors.muted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatTime(Duration value) {
    final minutes = value.inMinutes;
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  static String _duration(int? seconds) => seconds == null
      ? '--:--'
      : '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// A song's album art. Purely informational — there's no tap-to-play or
/// tap-to-stop in an event; [isPlaying] just shows a small "now playing"
/// indicator over whichever song the shared queue is actually playing.
class _AlbumArt extends StatelessWidget {
  const _AlbumArt({required this.size, this.url = '', this.isPlaying = false});

  final double size;
  final String url;
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    final art = ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: url.isEmpty
          ? _fallback()
          : Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _fallback(),
            ),
    );

    if (!isPlaying) return SizedBox(width: size, height: size, child: art);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          art,
          Positioned(
            right: size * .08,
            bottom: size * .08,
            child: Container(
              padding: EdgeInsets.all(size * .07),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.graphic_eq_rounded, color: _EventColors.tertiary, size: size * .22),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallback() => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF35306D), Color(0xFF0E758C), Color(0xFFEF4A9A)],
      ),
      boxShadow: [
        BoxShadow(
          color: _EventColors.tertiary.withValues(alpha: .24),
          blurRadius: 16,
        ),
      ],
    ),
    child: Icon(
      Icons.graphic_eq_rounded,
      color: Colors.white.withValues(alpha: .88),
      size: size * .4,
    ),
  );
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.entry,
    required this.isChanging,
    required this.isReadOnly,
    required this.isPlaying,
    required this.onVote,
  });
  final EventSong entry;
  final bool isChanging;
  final bool isReadOnly;
  final bool isPlaying;
  final VoidCallback onVote;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
    decoration: BoxDecoration(
      color: _EventColors.card,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _EventColors.cardBorder),
    ),
    child: Row(
      children: [
        _AlbumArt(size: 46, url: entry.song.albumArtUrl, isPlaying: isPlaying),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Sora',
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: _EventColors.body,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                entry.song.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: _EventColors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        _VoteButton(
          count: entry.voteCount,
          hasVoted: entry.hasVoted,
          isChanging: isChanging,
          isReadOnly: isReadOnly,
          onTap: onVote,
        ),
      ],
    ),
  );
}

class _VoteButton extends StatelessWidget {
  const _VoteButton({
    required this.count,
    required this.hasVoted,
    required this.isChanging,
    required this.isReadOnly,
    required this.onTap,
  });
  final int count;
  final bool hasVoted;
  final bool isChanging;
  final bool isReadOnly;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: isReadOnly
        ? _EventColors.card
        : hasVoted
        ? _EventColors.tertiary.withValues(alpha: .2)
        : _EventColors.background,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: isChanging || isReadOnly ? null : onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 72,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isReadOnly
                ? _EventColors.cardBorder
                : hasVoted
                ? _EventColors.tertiary
                : _EventColors.cardBorder,
          ),
        ),
        child: isChanging
            ? const SizedBox(
                height: 18,
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _EventColors.tertiary,
                  ),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$count',
                    style: TextStyle(
                      fontFamily: 'Sora',
                      fontWeight: FontWeight.w800,
                      color: isReadOnly
                          ? _EventColors.muted
                          : hasVoted
                          ? _EventColors.tertiary
                          : _EventColors.body,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    isReadOnly
                        ? Icons.lock_rounded
                        : hasVoted
                        ? Icons.check_rounded
                        : Icons.arrow_upward_rounded,
                    size: 15,
                    color: isReadOnly
                        ? _EventColors.muted
                        : hasVoted
                        ? _EventColors.tertiary
                        : _EventColors.muted,
                  ),
                ],
              ),
      ),
    ),
  );
}

class _EmptyNowPlaying extends StatelessWidget {
  const _EmptyNowPlaying();
  @override
  Widget build(BuildContext context) => Container(
    height: 230,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: _EventColors.card,
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: _EventColors.cardBorder),
    ),
    child: const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.queue_music_rounded, size: 40, color: _EventColors.muted),
        SizedBox(height: 10),
        Text(
          'Nothing is playing yet',
          style: TextStyle(color: _EventColors.body),
        ),
      ],
    ),
  );
}

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 28),
    child: Center(
      child: Text(
        'Be the first to suggest a track.',
        style: TextStyle(color: _EventColors.muted),
      ),
    ),
  );
}

class _VotingRestrictedCard extends StatelessWidget {
  const _VotingRestrictedCard({
    required this.message,
    required this.onCheckRequirements,
  });

  final String message;
  final VoidCallback onCheckRequirements;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: _EventColors.card,
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: const Color(0xFF70555B)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            CircleAvatar(
              radius: 21,
              backgroundColor: Color(0xFF39282D),
              child: Icon(Icons.lock_rounded, color: Color(0xFFFFB4AB)),
            ),
            SizedBox(width: 12),
            Text(
              'Voting Restricted',
              style: TextStyle(
                fontFamily: 'Sora',
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: _EventColors.body,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          message,
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: _EventColors.headline,
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: onCheckRequirements,
          iconAlignment: IconAlignment.end,
          icon: const Icon(Icons.arrow_forward_rounded, size: 18),
          label: const Text('Check Requirements'),
          style: TextButton.styleFrom(foregroundColor: _EventColors.headline),
        ),
      ],
    ),
  );
}

class _VotingRequirementsSheet extends StatefulWidget {
  const _VotingRequirementsSheet({
    required this.event,
    required this.onTryAgain,
  });

  final Event event;
  final VoidCallback onTryAgain;

  @override
  State<_VotingRequirementsSheet> createState() => _VotingRequirementsSheetState();
}

class _VotingRequirementsSheetState extends State<_VotingRequirementsSheet> {
  /// Reverse-geocoded ("Neighborhood, City, Country") label for the venue —
  /// see [reverseGeocodeLabel]. `null` while resolving or if the lookup
  /// failed/found nothing, in which case [_venueValue] falls back to the
  /// raw coordinates.
  String? _venueLabel;
  var _isResolvingVenue = false;

  @override
  void initState() {
    super.initState();
    final latitude = widget.event.venueCenterLatitude;
    final longitude = widget.event.venueCenterLongitude;
    if (widget.event.locationRestrictionEnabled && latitude != null && longitude != null) {
      _isResolvingVenue = true;
      unawaited(_resolveVenueLabel(latitude, longitude));
    }
  }

  Future<void> _resolveVenueLabel(double latitude, double longitude) async {
    final label = await reverseGeocodeLabel(latitude, longitude);
    if (!mounted) return;
    setState(() {
      _venueLabel = label;
      _isResolvingVenue = false;
    });
  }

  String _venueValue() {
    final event = widget.event;
    if (_venueLabel != null) return _venueLabel!;
    if (_isResolvingVenue) return 'Locating…';
    final latitude = event.venueCenterLatitude;
    final longitude = event.venueCenterLongitude;
    if (latitude == null || longitude == null) return 'Not set';
    return '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Voting requirements',
            style: TextStyle(
              fontFamily: 'Sora',
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _EventColors.body,
            ),
          ),
          const SizedBox(height: 16),
          _RequirementRow(
            label: 'License',
            value: _licenseText(event.votePermission),
          ),
          // Time and location are independent restrictions — each shown
          // only when its own toggle is on, not gated by the other or by
          // `votePermission` (see Event.timeRestrictionEnabled /
          // Event.locationRestrictionEnabled).
          if (event.timeRestrictionEnabled) ...[
            _RequirementRow(
              label: 'voting_opens_at',
              value: _dateTime(event.votingOpensAt),
            ),
            _RequirementRow(
              label: 'voting_closes_at',
              value: _dateTime(event.votingClosesAt),
            ),
          ],
          if (event.locationRestrictionEnabled) ...[
            _RequirementRow(
              label: 'allowed_distance_meters',
              value: event.allowedDistanceMeters?.toString() ?? 'Not set',
            ),
            _RequirementRow(label: 'venue_location', value: _venueValue()),
          ],
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: widget.onTryAgain,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try voting again'),
          ),
        ],
      ),
    );
  }

  static String _licenseText(String permission) => switch (permission) {
    eventVotePermissionInvitedOnly => 'Invited guests only',
    _ => 'Everyone can vote',
  };

  static String _dateTime(DateTime? value) {
    if (value == null) return 'Not set';
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} ${two(value.hour)}:${two(value.minute)} local time';
  }
}

class _RequirementRow extends StatelessWidget {
  const _RequirementRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Sora',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: _EventColors.muted,
          ),
        ),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(color: _EventColors.body)),
      ],
    ),
  );
}

/// Shown only for a 403 on the event-detail or event-join endpoint. Public
/// events never return this access denial, so the backend signal is specific
/// to a private event the caller has not been invited to.
class PrivateEventAccessDeniedScreen extends StatelessWidget {
  const PrivateEventAccessDeniedScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _EventColors.background,
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 30, 24, 26),
            decoration: BoxDecoration(
              color: _EventColors.card,
              borderRadius: BorderRadius.circular(40),
              border: Border.all(color: _EventColors.cardBorder),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircleAvatar(
                  radius: 43,
                  backgroundColor: Color(0xFF39282D),
                  child: Icon(
                    Icons.lock_rounded,
                    size: 42,
                    color: Color(0xFFFFB4AB),
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  'Private Event',
                  style: TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: _EventColors.body,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'This event is private — ask the host to invite you to join the session.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.45,
                    color: _EventColors.muted,
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('Return to Landing'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _EventColors.tertiary,
                      foregroundColor: const Color(0xFF15151C),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: const StadiumBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.wifi_off_rounded,
            color: _EventColors.muted,
            size: 40,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _EventColors.body),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: onRetry,
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
