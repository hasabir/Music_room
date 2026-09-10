import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/api/api_config.dart';
import '../core/auth/token_storage.dart';

class RealtimeNotificationService {
  factory RealtimeNotificationService() => instance;

  static final RealtimeNotificationService instance =
      RealtimeNotificationService._internal();

  RealtimeNotificationService._internal() : _tokenStorage = TokenStorage();

  final TokenStorage _tokenStorage;
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  final Set<VoidCallback> _listeners = {};
  var _stopped = true;
  var _initialized = false;
  var _started = false;
  var _nextId = 1;

  Future<void> start({required VoidCallback onNotification}) async {
    addListener(onNotification);
    if (_started) return;
    _started = true;
    _stopped = false;
    await _initializeNotifications();
    await _connect();
  }

  void addListener(VoidCallback listener) => _listeners.add(listener);

  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  Future<void> requestPermission() async {
    await _initializeNotifications();
    if (kIsWeb) {
      await _notifications
          .resolvePlatformSpecificImplementation<
            WebFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      return;
    }
    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    await _notifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  Future<void> _initializeNotifications() async {
    if (_initialized) return;
    try {
      await _notifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
          web: WebInitializationSettings(),
        ),
      );
      _initialized = true;
    } catch (_) {
      // A missing desktop implementation must not stop in-app updates.
    }
  }

  Future<void> _connect() async {
    if (_stopped) return;
    final token = await _tokenStorage.readAccessToken();
    if (_stopped || token == null) return;
    try {
      final channel = WebSocketChannel.connect(
        ApiConfig.notificationSocketUri(token),
      );
      _channel = channel;
      await channel.ready;
      _subscription = channel.stream.listen(
        _handleMessage,
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _handleMessage(dynamic raw) {
    try {
      final json = jsonDecode(raw as String) as Map<String, dynamic>;
      final title = json['title'] as String? ?? 'Music Room';
      final body = json['body'] as String? ?? 'You have a new notification.';
      unawaited(_show(title, body, jsonEncode(json['data'] ?? const {})));
      for (final listener in List<VoidCallback>.of(_listeners)) {
        listener();
      }
    } catch (_) {
      // Ignore malformed socket messages instead of dropping the connection.
    }
  }

  Future<void> _show(String title, String body, String payload) async {
    try {
      await _notifications.show(
        id: _nextId++,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'music_room_realtime',
            'Music Room updates',
            channelDescription:
                'Invitations, friend requests, and collaboration updates',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
          web: WebNotificationDetails(),
        ),
        payload: payload,
      );
    } catch (_) {
      // Permission denial is expected and should never break the app.
    }
  }

  void _scheduleReconnect() {
    if (_stopped || _reconnectTimer?.isActive == true) return;
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    _reconnectTimer = Timer(const Duration(seconds: 3), _connect);
  }

  void stop() {
    _started = false;
    _stopped = true;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _subscription = null;
    unawaited(_channel?.sink.close());
    _channel = null;
  }
}
