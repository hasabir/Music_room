import 'dart:ui';

import 'package:flutter/material.dart';

import '../../auth/welcome_screen.dart';
import '../../auth/auth_state.dart';
import '../../home/home_screen.dart';

/// Design tokens pulled from the Music Room dark theme.
class _SplashColors {
  static const surfaceContainerLowest = Color(0xFF0E0E15);
  static const onSurface = Color(0xFFE4E1EB);
  static const primary = Color(0xFFC0C1FF);
  static const tertiary = Color(0xFF2FD9F4);
}

/// Music Room splash screen.
///
/// Shows the wordmark with a gradient, a pulsing loading indicator and
/// two ambient background glows. Fades its content in, holds for a few
/// seconds, then fades/scales it out before navigating onward.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.authState = const TemporaryAuthState()});

  /// Determines which screen to navigate to once the splash animation
  /// finishes. Defaults to a temporary, unauthenticated implementation
  /// until a real auth service is wired in.
  final AuthState authState;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  static const _fadeInDelay = Duration(milliseconds: 200);
  static const _fadeInDuration = Duration(milliseconds: 1000);
  static const _holdDuration = Duration(milliseconds: 3000);
  static const _exitDuration = Duration(milliseconds: 800);

  late final AnimationController _fadeInController;
  late final AnimationController _exitController;

  late final Animation<double> _fadeInAnimation;
  late final Animation<double> _exitFadeAnimation;
  late final Animation<double> _exitScaleAnimation;

  @override
  void initState() {
    super.initState();

    _fadeInController = AnimationController(
      vsync: this,
      duration: _fadeInDuration,
    );
    _fadeInAnimation = CurvedAnimation(
      parent: _fadeInController,
      curve: Curves.easeIn,
    );

    _exitController = AnimationController(vsync: this, duration: _exitDuration);
    _exitFadeAnimation = Tween<double>(
      begin: 1,
      end: 0,
    ).animate(CurvedAnimation(parent: _exitController, curve: Curves.easeOut));
    _exitScaleAnimation = Tween<double>(
      begin: 1,
      end: 1.05,
    ).animate(CurvedAnimation(parent: _exitController, curve: Curves.easeOut));

    _runSequence();
  }

  Future<void> _runSequence() async {
    await Future<void>.delayed(_fadeInDelay);
    if (!mounted) return;
    await _fadeInController.forward();

    await Future<void>.delayed(_holdDuration);
    if (!mounted) return;
    await _exitController.forward();

    if (!mounted) return;
    final destination = widget.authState.isAuthenticated
        ? const HomeScreen()
        : const WelcomeScreen();
    Navigator.of(context)
        .pushReplacement(MaterialPageRoute(builder: (_) => destination));
  }

  @override
  void dispose() {
    _fadeInController.dispose();
    _exitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _SplashColors.surfaceContainerLowest,
      body: Stack(
        children: [
          const Positioned.fill(child: _AmbientGlows()),
          Positioned.fill(
            child: AnimatedBuilder(
              animation: Listenable.merge([_fadeInAnimation, _exitController]),
              builder: (context, child) {
                final opacity =
                    _fadeInAnimation.value * _exitFadeAnimation.value;
                return Opacity(
                  opacity: opacity.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: _exitScaleAnimation.value,
                    child: child,
                  ),
                );
              },
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _WordmarkText(),
                    const SizedBox(height: 16),
                    const SizedBox(
                      height: 32,
                      child: Center(child: _PulseIndicator()),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WordmarkText extends StatelessWidget {
  const _WordmarkText();

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) {
        return const LinearGradient(
          colors: [_SplashColors.onSurface, _SplashColors.primary],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ).createShader(bounds);
      },
      child: const Text(
        'Music Room',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Sora',
          fontWeight: FontWeight.w800,
          fontSize: 48,
          height: 1.1,
          letterSpacing: -0.02 * 48,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Recreates the CSS `pulse-teal` keyframes: the dot scales 0.95 -> 1 -> 0.95
/// while a soft ring expands outward and fades, on a continuous 2s loop.
class _PulseIndicator extends StatefulWidget {
  const _PulseIndicator();

  @override
  State<_PulseIndicator> createState() => _PulseIndicatorState();
}

class _PulseIndicatorState extends State<_PulseIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;

        // 0%: scale 0.95, ring at 0 spread, opacity 0.7
        // 70%: scale 1.0, ring at 10px spread, opacity 0
        // 100%: scale 0.95, ring at 0 spread, opacity 0
        double scale;
        double ringSpread;
        double ringOpacity;
        if (t <= 0.7) {
          final localT = t / 0.7;
          scale = lerpDouble(0.95, 1.0, localT)!;
          ringSpread = lerpDouble(0, 10, localT)!;
          ringOpacity = lerpDouble(0.7, 0, localT)!;
        } else {
          final localT = (t - 0.7) / 0.3;
          scale = lerpDouble(1.0, 0.95, localT)!;
          ringSpread = 0;
          ringOpacity = 0;
        }

        return Transform.scale(
          scale: scale,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _SplashColors.tertiary,
              boxShadow: ringOpacity > 0
                  ? [
                      BoxShadow(
                        color: _SplashColors.tertiary.withValues(
                          alpha: ringOpacity,
                        ),
                        spreadRadius: ringSpread,
                        blurRadius: 0,
                      ),
                    ]
                  : null,
            ),
          ),
        );
      },
    );
  }
}

/// Two subtle blurred glows, positioned and sized relative to the screen.
class _AmbientGlows extends StatelessWidget {
  const _AmbientGlows();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final purpleSize = width * 0.4;
        final cyanSize = width * 0.3;

        return Stack(
          children: [
            Positioned(
              left: width * 0.25,
              top: height * 0.25,
              child: _Glow(
                size: purpleSize,
                color: _SplashColors.primary,
                blurSigma: 50,
              ),
            ),
            Positioned(
              right: width * 0.25,
              bottom: height * 0.25,
              child: _Glow(
                size: cyanSize,
                color: _SplashColors.tertiary,
                blurSigma: 40,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({
    required this.size,
    required this.color,
    required this.blurSigma,
  });

  final double size;
  final Color color;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.5,
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.05),
          ),
        ),
      ),
    );
  }
}
