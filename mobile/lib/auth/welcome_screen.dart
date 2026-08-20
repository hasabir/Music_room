import 'package:flutter/material.dart';

import 'login_screen.dart';
import 'register_screen.dart';

class _WelcomeColors {
  static const background = Color(0xFF0E0E15);
  static const headline = Color(0xFFC0C1FF);
  static const description = Color(0xFFC7C4D7);
  static const tertiary = Color(0xFF2FD9F4);
  static const dividerLine = Color(0xFF464554);
  static const dividerText = Color(0xFF908FA0);
  static const gradientStart = Color(0xFF8083FF);
  static const gradientEnd = Color(0xFF494BD6);
}

/// First screen shown to unauthenticated users after the splash screen.
///
/// Offers account creation, log in, and a Google sign-in entry point.
/// None of those flows are implemented yet — each button exposes a clearly
/// marked placeholder callback for the real screens to be wired in later.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  void _onCreateAccount(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const RegisterScreen()));
  }

  void _onLogIn(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  // TODO: Replace with real Google Sign-In once the auth service exists.
  void _onContinueWithGoogle(BuildContext context) {}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _WelcomeColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 3),
              const _Headline(),
              const SizedBox(height: 16),
              const _Description(),
              const Spacer(flex: 4),
              _CreateAccountButton(onPressed: () => _onCreateAccount(context)),
              const SizedBox(height: 12),
              _LogInButton(onPressed: () => _onLogIn(context)),
              const SizedBox(height: 20),
              const _OrDivider(),
              const SizedBox(height: 20),
              _GoogleButton(onPressed: () => _onContinueWithGoogle(context)),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Shape the\nmusic\ntogether.',
      style: TextStyle(
        fontFamily: 'Sora',
        fontWeight: FontWeight.w800,
        fontSize: 48,
        height: 1.1,
        letterSpacing: -0.02 * 48,
        color: _WelcomeColors.headline,
      ),
    );
  }
}

class _Description extends StatelessWidget {
  const _Description();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Join events, vote on tracks, and build live playlists with friends.',
      style: TextStyle(
        fontSize: 16,
        height: 1.6,
        color: _WelcomeColors.description,
      ),
    );
  }
}

class _CreateAccountButton extends StatelessWidget {
  const _CreateAccountButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_WelcomeColors.gradientStart, _WelcomeColors.gradientEnd],
        ),
        boxShadow: [
          BoxShadow(
            color: _WelcomeColors.gradientEnd.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onPressed,
          child: const Center(
            child: Text(
              'Create account',
              style: TextStyle(
                fontFamily: 'Sora',
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LogInButton extends StatelessWidget {
  const _LogInButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.transparent,
          side: const BorderSide(color: _WelcomeColors.tertiary, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: const Text(
          'Log In',
          style: TextStyle(
            fontFamily: 'Sora',
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: _WelcomeColors.tertiary,
          ),
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: Divider(color: _WelcomeColors.dividerLine)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'OR',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.05 * 12,
              color: _WelcomeColors.dividerText,
            ),
          ),
        ),
        Expanded(child: Divider(color: _WelcomeColors.dividerLine)),
      ],
    );
  }
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.transparent,
          side: const BorderSide(color: _WelcomeColors.tertiary, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/images/google_logo.png', width: 20, height: 20),
            const SizedBox(width: 12),
            const Text(
              'Continue with Google',
              style: TextStyle(
                fontFamily: 'Sora',
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
