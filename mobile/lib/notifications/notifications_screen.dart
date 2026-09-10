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
import 'notification_service.dart';
import '../track_vote/event_api.dart';
import '../track_vote/event_models.dart';

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
  final _tokenStorage = TokenStorage();
  final _notificationService = RealtimeNotificationService.instance;

  late List<Event> _eventInvites;
  List<FriendRequest> _friendRequests = const [];
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
      ]);
      final requests = results[0] as List<FriendRequest>;
      final currentUser = results[1] as AuthUser;
      final events = results[2] as List<Event>;
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

  @override
  Widget build(BuildContext context) {
    final isEmpty =
        !_loadingFriends && _friendRequests.isEmpty && _eventInvites.isEmpty;
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
              if (isEmpty)
                const _MessageCard(
                  icon: Icons.notifications_none_rounded,
                  message: "You're all caught up.",
                ),
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
