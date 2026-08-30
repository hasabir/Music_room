import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'core/splash/splash_screen.dart';
import 'core/playback/mini_player.dart';
import 'core/navigation/app_navigator.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
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
      theme: ThemeData.dark(useMaterial3: true),
      home: SplashScreen(),
      builder: (context, child) => Overlay(
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
    );
  }
}
