import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'core/splash/splash_screen.dart';
import 'core/playback/mini_player.dart';
import 'core/navigation/app_navigator.dart';
import 'core/api/client_action_log.dart';
import 'core/auth/token_storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  ClientActionLog.readAccessToken = TokenStorage().readAccessToken;
  runApp(const MusicRoomApp());
}

class MusicRoomApp extends StatelessWidget {
  const MusicRoomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Music Room',
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      navigatorObservers: [ActionLogNavigatorObserver()],
      theme: ThemeData.dark(useMaterial3: true),
      home: SplashScreen(),
      builder: (context, child) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerUp: (_) => ClientActionLog.record('interaction'),
        child: Focus(
          canRequestFocus: false,
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.space)) {
              ClientActionLog.record('interaction');
            }
            return KeyEventResult.ignored;
          },
          child: Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (_) => Stack(
                  children: [
                    child ?? const SizedBox.shrink(),
                    const Align(
                      alignment: Alignment.bottomCenter,
                      child: MiniPlayer(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
