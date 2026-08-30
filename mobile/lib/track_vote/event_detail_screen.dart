import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../auth/auth_api.dart';
import '../auth/auth_models.dart';
import '../auth/welcome_screen.dart';
import '../core/api/api_client.dart';
import '../core/auth/token_storage.dart';
import 'event_api.dart';
import 'event_models.dart';
import 'event_widgets.dart';
import 'event_guests_screen.dart';
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
  final _tokenStorage = TokenStorage();
  final Set<int> _changingVotes = <int>{};
  Timer? _pollTimer;
  var _isLoading = true;
  String? _loadError;
  String? _voteRestrictionReason;
  var _isPrivateAccessDenied = false;
  Event? _event;
  AuthUser? _authUser;
  List<EventSong> _queue = const [];

  @override
  void initState() {
    super.initState();
    _loadAll();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _pollQueue());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
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
      ]);
      if (!mounted) return;
      setState(() {
        _event = results[0] as Event;
        _queue = results[1] as List<EventSong>;
        _authUser = results[2] as AuthUser;
        _isLoading = false;
      });
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

  Future<void> _pollQueue() async {
    if (_isLoading || _changingVotes.isNotEmpty) return;
    try {
      final queue = await _eventApi.listQueue(widget.eventId);
      if (mounted) setState(() => _queue = queue);
    } on SessionExpiredException {
      await _signOutAndReturnToWelcome();
    } on ApiException {
      // Keep the last known live queue on a transient background failure.
    }
  }

  Future<void> _refetchQueue() async {
    final queue = await _eventApi.listQueue(widget.eventId);
    if (mounted) setState(() => _queue = queue);
  }

  Future<Position?> _positionFor(Event event) async {
    if (event.votePermission != eventVotePermissionLocationTimeRestricted) {
      return null;
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw 'Turn on location services to vote in this event.';
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw 'Location permission is required to vote in this event.';
    }
    return Geolocator.getCurrentPosition();
  }

  Future<void> _toggleVote(EventSong entry) async {
    final event = _event;
    if (event == null || _changingVotes.contains(entry.id)) return;
    setState(() => _changingVotes.add(entry.id));
    try {
      if (entry.hasVoted) {
        await _eventApi.retractVote(widget.eventId, entry.id);
      } else {
        final position = await _positionFor(event);
        await _eventApi.vote(
          widget.eventId,
          entry.id,
          latitude: position?.latitude,
          longitude: position?.longitude,
        );
      }
      await _refetchQueue();
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
    await _refetchQueue();
  }

  Future<void> _openGuestManagement() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EventGuestsScreen(eventId: widget.eventId),
      ),
    );
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

    final playing =
        _queue
            .where((entry) => entry.status == eventSongStatusPlaying)
            .firstOrNull ??
        (_queue.isEmpty ? null : _queue.first);
    final upNext = playing == null
        ? _queue
        : _queue.where((entry) => entry.id != playing.id).toList();
    final participants = <String>{
      event.host,
      ..._queue.map((entry) => entry.addedByEmail).whereType<String>(),
    }.toList();
    final isHost = _authUser?.email == event.host;
    final isVotingRestricted = _voteRestrictionReason != null;

    return Column(
      children: [
        _TopBar(
          title: event.title,
          onManageGuests: isHost ? _openGuestManagement : null,
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadAll,
            color: _EventColors.tertiary,
            backgroundColor: _EventColors.card,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              children: [
                Text(
                  event.title,
                  style: const TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: _EventColors.headline,
                  ),
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
                    EventLicenseBadge(votePermission: event.votePermission),
                  ],
                ),
                const SizedBox(height: 16),
                _ParticipantAvatars(emails: participants),
                const SizedBox(height: 28),
                const _SectionLabel('NOW PLAYING'),
                const SizedBox(height: 10),
                _NowPlayingCard(song: playing),
                const SizedBox(height: 28),
                if (isVotingRestricted) ...[
                  _VotingRestrictedCard(
                    message:
                        event.votePermission ==
                            eventVotePermissionLocationTimeRestricted
                        ? "You are currently outside the event geofence or the voting window hasn't started yet."
                        : _voteRestrictionReason!,
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
                OutlinedButton.icon(
                  onPressed: _openSuggestTrack,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Suggest a track'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _EventColors.tertiary,
                    side: const BorderSide(color: _EventColors.cardBorder),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
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
                      onVote: () => _toggleVote(entry),
                    ),
                    const SizedBox(height: 8),
                  ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.onManageGuests});
  final String title;
  final VoidCallback? onManageGuests;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 16, 4),
    child: Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded, color: _EventColors.body),
        ),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Sora',
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _EventColors.body,
            ),
          ),
        ),
        if (onManageGuests != null)
          IconButton(
            onPressed: onManageGuests,
            icon: const Icon(Icons.group_rounded, color: _EventColors.tertiary),
            tooltip: 'Manage guests',
          ),
      ],
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

class _ParticipantAvatars extends StatelessWidget {
  const _ParticipantAvatars({required this.emails});
  final List<String> emails;
  @override
  Widget build(BuildContext context) {
    const displayed = 4;
    final people = emails.take(displayed).toList();
    return Row(
      children: [
        for (var i = 0; i < people.length; i++)
          Transform.translate(
            offset: Offset(-i * 8.0, 0),
            child: _Avatar(people[i]),
          ),
        if (emails.length > displayed)
          Transform.translate(
            offset: Offset(-displayed * 8.0, 0),
            child: _CountAvatar(emails.length - displayed),
          ),
        const Spacer(),
        Text(
          '${emails.length} participant${emails.length == 1 ? '' : 's'}',
          style: const TextStyle(fontSize: 12, color: _EventColors.muted),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.email);
  final String email;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: email,
    child: CircleAvatar(
      radius: 15,
      backgroundColor: _EventColors.cardBorder,
      child: Text(
        email.isEmpty ? '?' : email[0].toUpperCase(),
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

class _NowPlayingCard extends StatelessWidget {
  const _NowPlayingCard({required this.song});
  final EventSong? song;
  @override
  Widget build(BuildContext context) {
    if (song == null) return const _EmptyNowPlaying();
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
          const Center(child: _AlbumArt(size: 112)),
          const SizedBox(height: 22),
          Text(
            song!.song.title,
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
            song!.song.artist,
            style: const TextStyle(
              fontFamily: 'Sora',
              fontWeight: FontWeight.w700,
              color: _EventColors.muted,
            ),
          ),
          const SizedBox(height: 20),
          const LinearProgressIndicator(
            value: 0,
            minHeight: 6,
            borderRadius: BorderRadius.all(Radius.circular(9)),
            color: _EventColors.tertiary,
            backgroundColor: _EventColors.cardBorder,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Not started',
                style: TextStyle(fontSize: 11, color: _EventColors.muted),
              ),
              Text(
                _duration(song!.song.durationSeconds),
                style: const TextStyle(fontSize: 11, color: _EventColors.muted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _duration(int? seconds) => seconds == null
      ? '--:--'
      : '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

class _AlbumArt extends StatelessWidget {
  const _AlbumArt({required this.size});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
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
    required this.onVote,
  });
  final EventSong entry;
  final bool isChanging;
  final bool isReadOnly;
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
        const _AlbumArt(size: 46),
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

class _VotingRequirementsSheet extends StatelessWidget {
  const _VotingRequirementsSheet({
    required this.event,
    required this.onTryAgain,
  });

  final Event event;
  final VoidCallback onTryAgain;

  @override
  Widget build(BuildContext context) => Padding(
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
        if (event.votePermission ==
            eventVotePermissionLocationTimeRestricted) ...[
          _RequirementRow(
            label: 'voting_opens_at',
            value: _dateTime(event.votingOpensAt),
          ),
          _RequirementRow(
            label: 'voting_closes_at',
            value: _dateTime(event.votingClosesAt),
          ),
          _RequirementRow(
            label: 'allowed_distance_meters',
            value: event.allowedDistanceMeters?.toString() ?? 'Not set',
          ),
          _RequirementRow(
            label: 'venue_center_latitude',
            value: event.venueCenterLatitude?.toStringAsFixed(5) ?? 'Not set',
          ),
          _RequirementRow(
            label: 'venue_center_longitude',
            value: event.venueCenterLongitude?.toStringAsFixed(5) ?? 'Not set',
          ),
        ],
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: onTryAgain,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Try voting again'),
        ),
      ],
    ),
  );

  static String _licenseText(String permission) => switch (permission) {
    eventVotePermissionInvitedOnly => 'Invited guests only',
    eventVotePermissionLocationTimeRestricted => 'Location and time restricted',
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
