import 'package:flutter/material.dart';
import 'core/splash/splash_screen.dart';

void main() {
  runApp(const MusicRoomApp());
}

class MusicRoomApp extends StatelessWidget {
  const MusicRoomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Music Room',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const SplashScreen(),
    );
  }
}
