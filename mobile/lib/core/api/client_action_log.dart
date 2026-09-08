import 'dart:async';

import 'package:flutter/material.dart';

import 'api_client.dart';
import 'api_config.dart';

/// Best-effort telemetry for actions that do not otherwise contact the API.
/// No entered text, coordinates, route arguments, or media URLs are collected.
class ClientActionLog {
  static Future<String?> Function()? readAccessToken;
  static final _api = ApiClient();
  static int _pending = 0;

  static void record(String action) {
    if (readAccessToken == null || _pending >= 20) return;
    _pending++;
    unawaited(_send(action));
  }

  static Future<void> _send(String action) async {
    try {
      final token = await readAccessToken!().timeout(
        const Duration(seconds: 3),
      );
      await _api.post(
        Uri.parse('${ApiConfig.baseUrl}/api/v1/user/actions/'),
        body: {'action': action},
        accessToken: token,
      );
    } catch (_) {
      // Offline/expired sessions or logging failures must not block the UI.
      // Do not retry: events must not be attributed to a later user's session.
    } finally {
      _pending--;
    }
  }
}

class ActionLogNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    ClientActionLog.record('navigation');
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    ClientActionLog.record('navigation');
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    ClientActionLog.record('navigation');
  }
}
