/// One entry in the signed-in user's notification history, as returned by
/// `GET /api/v1/user/notifications/` (`NotificationSerializer`). Every
/// `notify_user()` call on the backend persists one of these, in addition
/// to the transient websocket message used for the realtime toast.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.data,
    required this.isRead,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as int,
        kind: json['kind'] as String? ?? '',
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        data: (json['data'] as Map?)?.cast<String, dynamic>() ?? const {},
        isRead: json['is_read'] as bool? ?? false,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final int id;

  /// See the backend's per-kind `notify_user(kind=...)` call sites (e.g.
  /// `friend_request`, `event_invite`, `playlist_invite`) — used here only
  /// to pick an icon and, where `data` has a `playlist_id`/`event_id`, a
  /// tap destination.
  final String kind;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final bool isRead;
  final DateTime createdAt;

  int? get playlistId => data['playlist_id'] as int?;
  int? get eventId => data['event_id'] as int?;

  AppNotification copyWith({bool? isRead}) => AppNotification(
    id: id,
    kind: kind,
    title: title,
    body: body,
    data: data,
    isRead: isRead ?? this.isRead,
    createdAt: createdAt,
  );
}
