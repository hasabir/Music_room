import 'package:flutter/material.dart';

import '../auth/auth_api.dart';
import '../auth/auth_models.dart';
import '../auth/welcome_screen.dart';
import '../core/api/api_client.dart';
import '../core/auth/token_storage.dart';
import '../core/responsive/responsive.dart';
import '../profile/profile_api.dart';
import '../profile/profile_avatar.dart';
import '../profile/profile_models.dart';
import '../playlists/playlist_api.dart';
import '../playlists/playlist_detail_screen.dart';
import '../playlists/playlist_models.dart';
import 'notification_api.dart';
import 'notification_models.dart';
import 'notification_service.dart';
import '../track_vote/event_api.dart';
import '../track_vote/event_detail_screen.dart';
import '../track_vote/event_models.dart';

/// Playlist invites carry no pending/accept state of their own (inviting a
/// collaborator grants access immediately), so there's nothing to keep
/// showing here forever — only ones from the last week surface as "new".
const _playlistInviteFreshness = Duration(days: 7);

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, required this.eventInvites});

  final List<Event> eventInvites;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const _background = Color(0xFF0E0E15);
  static const _card = Color(0xFF17161F);
  static const _border = Color(0xFF2A2935);
  static const _headline = Color(0xFFC0C1FF);
  static const _body = Color(0xFFE4E1EB);
  static const _muted = Color(0xFF908FA0);
  static const _accent = Color(0xFF2FD9F4);

  final _profileApi = ProfileApi();
  final _authApi = AuthApi();
  final _eventApi = EventApi();
  final _playlistApi = PlaylistApi();
  final _notificationApi = NotificationApi();
  final _tokenStorage = TokenStorage();
  final _notificationService = RealtimeNotificationService.instance;

  late List<Event> _eventInvites;
  List<FriendRequest> _friendRequests = const [];
  List<PlaylistCollaborator> _playlistInvites = const [];
  List<AppNotification> _history = const [];
  final Set<String> _busy = {};
  var _loadingFriends = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _eventInvites = List.of(widget.eventInvites);
    _loadNotifications();
    _notificationService.addListener(_onRealtimeNotification);
  }

  @override
  void dispose() {
    _notificationService.removeListener(_onRealtimeNotification);
    super.dispose();
  }

  void _onRealtimeNotification() {
    if (mounted) _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    try {
      final results = await Future.wait([
        _profileApi.getReceivedRequests(),
        _authApi.getCurrentUser(),
        _eventApi.listEvents(),
        _playlistApi.listMyCollaboratorInvites(),
        _notificationApi.listNotifications(),
      ]);
      final requests = results[0] as List<FriendRequest>;
      final currentUser = results[1] as AuthUser;
      final events = results[2] as List<Event>;
      final collaboratorInvites = results[3] as List<PlaylistCollaborator>;
      final history = results[4] as List<AppNotification>;
      final now = DateTime.now();
      final freshPlaylistInvites = collaboratorInvites
          .where((invite) => now.difference(invite.invitedAt) <= _playlistInviteFreshness)
          .toList();
      final privateInvites = events.where(
        (event) =>
            event.host != currentUser.username &&
            !event.isMember &&
            event.visibility == eventVisibilityPrivate,
      );
      final pendingEvents = <Event>[];
      await Future.wait(
        privateInvites.map((event) async {
          try {
            final guests = await _eventApi.listGuests(event.id);
            if (guests.any(
              (guest) =>
                  guest.guest == currentUser.id &&
                  guest.rsvpStatus == eventGuestRsvpPending,
            )) {
              pendingEvents.add(event);
            }
          } on ApiException {
            // The invitation may have been removed between the two requests.
          }
        }),
      );
      if (!mounted) return;
      setState(() {
        _friendRequests = requests;
        _eventInvites = pendingEvents;
        _playlistInvites = freshPlaylistInvites;
        _history = history;
        _loadingFriends = false;
        _error = null;
      });
    } on SessionExpiredException {
      await _tokenStorage.clear();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        (_) => false,
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingFriends = false;
        _error = error.message;
      });
    }
  }

  Future<void> _respondToFriend(FriendRequest request, bool accept) async {
    final key = 'friend:${request.id}';
    setState(() => _busy.add(key));
    try {
      if (accept) {
        await _profileApi.acceptFriendRequest(request.id);
      } else {
        await _profileApi.rejectFriendRequest(request.id);
      }
      if (!mounted) return;
      setState(() {
        _busy.remove(key);
        _friendRequests = _friendRequests
            .where((item) => item.id != request.id)
            .toList();
      });
      _showResult(
        accept ? 'Friend request accepted.' : 'Friend request declined.',
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _busy.remove(key));
      _showResult(error.message);
    }
  }

  Future<void> _respondToEvent(Event event, bool accept) async {
    final key = 'event:${event.id}';
    setState(() => _busy.add(key));
    try {
      await _eventApi.respondToInvite(event.id, accept: accept);
      if (!mounted) return;
      setState(() {
        _busy.remove(key);
        _eventInvites = _eventInvites
            .where((item) => item.id != event.id)
            .toList();
      });
      _showResult(
        accept ? 'Event invitation accepted.' : 'Event invitation declined.',
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _busy.remove(key));
      _showResult(error.message);
    }
  }

  void _showResult(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  void _dismissPlaylistInvite(PlaylistCollaborator invite) {
    setState(() {
      _playlistInvites =
          _playlistInvites.where((item) => item.id != invite.id).toList();
    });
  }

  void _openPlaylist(PlaylistCollaborator invite) {
    _dismissPlaylistInvite(invite);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlaylistDetailScreen(playlistId: invite.playlist),
      ),
    );
  }

  void _markHistoryRead(AppNotification notification) {
    if (notification.isRead) return;
    setState(() {
      _history = [
        for (final item in _history)
          if (item.id == notification.id) item.copyWith(isRead: true) else item,
      ];
    });
    _notificationApi.markRead(notification.id).catchError((_) {});
  }

  Future<void> _markAllHistoryRead() async {
    final hadUnread = _history.any((item) => !item.isRead);
    if (!hadUnread) return;
    setState(() {
      _history = [for (final item in _history) item.copyWith(isRead: true)];
    });
    try {
      await _notificationApi.markAllRead();
    } on ApiException catch (error) {
      _showResult(error.message);
    }
  }

  void _openHistoryNotification(AppNotification notification) {
    _markHistoryRead(notification);
    if (notification.playlistId != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              PlaylistDetailScreen(playlistId: notification.playlistId!),
        ),
      );
    } else if (notification.eventId != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EventDetailScreen(eventId: notification.eventId!),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEmpty = !_loadingFriends &&
        _friendRequests.isEmpty &&
        _eventInvites.isEmpty &&
        _playlistInvites.isEmpty;
    final hasUnreadHistory = _history.any((item) => !item.isRead);
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        title: const Text(
          'Notifications',
          style: TextStyle(
            fontFamily: 'Sora',
            fontWeight: FontWeight.w800,
            color: _headline,
          ),
        ),
        actions: [
          if (hasUnreadHistory)
            TextButton(
              onPressed: _markAllHistoryRead,
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: ResponsiveContent(
        maxWidth: 720,
        child: RefreshIndicator(
          onRefresh: _loadNotifications,
          color: _headline,
          backgroundColor: _card,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              if (_loadingFriends)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(color: _headline),
                  ),
                )
              else if (_error != null)
                _MessageCard(
                  icon: Icons.cloud_off_rounded,
                  message: _error!,
                  actionLabel: 'Retry',
                  onAction: _loadNotifications,
                ),
              for (final request in _friendRequests) ...[
                _NotificationCard(
                  avatar: ProfileAvatarImage(
                    avatar: request.otherUserAvatar,
                    avatarType: request.otherUserAvatarType,
                    fallback: const ColoredBox(
                      color: _border,
                      child: Icon(Icons.person_rounded, color: _muted),
                    ),
                  ),
                  title: request.otherUserFullName,
                  message: 'sent you a friend request',
                  busy: _busy.contains('friend:${request.id}'),
                  onAccept: () => _respondToFriend(request, true),
                  onDecline: () => _respondToFriend(request, false),
                ),
                const SizedBox(height: 12),
              ],
              for (final event in _eventInvites) ...[
                _NotificationCard(
                  avatar: const ColoredBox(
                    color: _border,
                    child: Icon(Icons.celebration_rounded, color: _accent),
                  ),
                  title: event.title,
                  message: 'You were invited to this event',
                  busy: _busy.contains('event:${event.id}'),
                  onAccept: () => _respondToEvent(event, true),
                  onDecline: () => _respondToEvent(event, false),
                ),
                const SizedBox(height: 12),
              ],
              for (final invite in _playlistInvites) ...[
                _InfoNotificationCard(
                  avatar: const ColoredBox(
                    color: _border,
                    child: Icon(Icons.queue_music_rounded, color: _accent),
                  ),
                  title: invite.playlistTitle,
                  message: "You've been invited to collaborate on this playlist",
                  actionLabel: 'View playlist',
                  onAction: () => _openPlaylist(invite),
                  onDismiss: () => _dismissPlaylistInvite(invite),
                ),
                const SizedBox(height: 12),
              ],
              if (isEmpty)
                const _MessageCard(
                  icon: Icons.notifications_none_rounded,
                  message: "You're all caught up.",
                ),
              if (!_loadingFriends && _history.isNotEmpty) ...[
                const SizedBox(height: 24),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'ALL NOTIFICATIONS',
                    style: TextStyle(
                      fontFamily: 'Sora',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: _muted,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                for (final notification in _history) ...[
                  _HistoryNotificationTile(
                    notification: notification,
                    onTap: () => _openHistoryNotification(notification),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.avatar,
    required this.title,
    required this.message,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
  });

  final Widget avatar;
  final String title;
  final String message;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _NotificationsScreenState._card,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _NotificationsScreenState._border),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipOval(child: SizedBox(width: 48, height: 48, child: avatar)),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _NotificationsScreenState._body,
                  fontFamily: 'Sora',
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                message,
                style: const TextStyle(color: _NotificationsScreenState._muted),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  FilledButton(
                    onPressed: busy ? null : onAccept,
                    child: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Accept'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: busy ? null : onDecline,
                    child: const Text('Decline'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// A notification with a single action and a dismiss — for things that
/// already took effect (e.g. a playlist invite, which grants access the
/// moment it's sent) rather than something to accept/decline.
class _InfoNotificationCard extends StatelessWidget {
  const _InfoNotificationCard({
    required this.avatar,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    required this.onDismiss,
  });

  final Widget avatar;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _NotificationsScreenState._card,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _NotificationsScreenState._border),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipOval(child: SizedBox(width: 48, height: 48, child: avatar)),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _NotificationsScreenState._body,
                  fontFamily: 'Sora',
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                message,
                style: const TextStyle(color: _NotificationsScreenState._muted),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  FilledButton(onPressed: onAction, child: Text(actionLabel)),
                  const SizedBox(width: 8),
                  TextButton(onPressed: onDismiss, child: const Text('Dismiss')),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// One row in the full notification history — a read-only record, unlike
/// [_NotificationCard]/[_InfoNotificationCard] above, since whatever it
/// describes already happened. Tapping it marks it read (and, for kinds
/// tied to a playlist/event, opens that).
class _HistoryNotificationTile extends StatelessWidget {
  const _HistoryNotificationTile({
    required this.notification,
    required this.onTap,
  });

  final AppNotification notification;
  final VoidCallback onTap;

  static const _iconsByKind = {
    'friend_request': Icons.person_add_alt_1_rounded,
    'friend_request_accepted': Icons.person_rounded,
    'friend_request_cancelled': Icons.person_off_rounded,
    'friend_removed': Icons.person_off_rounded,
    'event_invite': Icons.celebration_rounded,
    'event_guest_removed': Icons.event_busy_rounded,
    'event_rsvp_updated': Icons.how_to_reg_rounded,
    'event_access_request': Icons.lock_open_rounded,
    'event_access_cancelled': Icons.lock_outline_rounded,
    'event_access_decided': Icons.verified_user_rounded,
    'playlist_invite': Icons.queue_music_rounded,
    'playlist_collaborator_removed': Icons.playlist_remove_rounded,
    'playlist_permissions_updated': Icons.tune_rounded,
    'playlist_access_request': Icons.lock_open_rounded,
    'playlist_access_cancelled': Icons.lock_outline_rounded,
    'playlist_access_decided': Icons.verified_user_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final isRead = notification.isRead;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _NotificationsScreenState._card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isRead
                ? _NotificationsScreenState._border
                : _NotificationsScreenState._accent.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              _iconsByKind[notification.kind] ?? Icons.notifications_rounded,
              size: 20,
              color: isRead
                  ? _NotificationsScreenState._muted
                  : _NotificationsScreenState._accent,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: TextStyle(
                      color: _NotificationsScreenState._body,
                      fontFamily: 'Sora',
                      fontWeight: isRead ? FontWeight.w600 : FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    notification.body,
                    style: const TextStyle(
                      color: _NotificationsScreenState._muted,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatTimeAgo(notification.createdAt),
                    style: const TextStyle(
                      color: _NotificationsScreenState._muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (!isRead)
              Container(
                margin: const EdgeInsets.only(left: 8, top: 4),
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: _NotificationsScreenState._accent,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(32),
    decoration: BoxDecoration(
      color: _NotificationsScreenState._card,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _NotificationsScreenState._border),
    ),
    child: Column(
      children: [
        Icon(icon, color: _NotificationsScreenState._muted, size: 36),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _NotificationsScreenState._body),
        ),
        if (onAction != null) ...[
          const SizedBox(height: 12),
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ],
    ),
  );
}
