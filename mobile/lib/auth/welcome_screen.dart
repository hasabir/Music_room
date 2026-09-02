import 'package:flutter/material.dart';

import '../core/api/api_client.dart';
import '../home/home_screen.dart';
import 'auth_api.dart';
import 'google_auth_service.dart';
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
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _authApi = AuthApi();

  bool _isSubmitting = false;
  String? _errorMessage;

  void _onCreateAccount() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const RegisterScreen()));
  }

  void _onLogIn() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  Future<void> _onContinueWithGoogle() async {
    if (_isSubmitting) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final idToken = await GoogleAuthService.signInAndGetIdToken();
      await _authApi.loginWithGoogle(idToken: idToken);

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    } on GoogleAuthCancelled {
      // User dismissed the account picker — not an error.
    } on GoogleAuthFailed catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

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
              if (_errorMessage != null) ...[
                _ErrorMessage(message: _errorMessage!),
                const SizedBox(height: 12),
              ],
              _CreateAccountButton(
                onPressed: _isSubmitting ? null : _onCreateAccount,
              ),
              const SizedBox(height: 12),
              _LogInButton(onPressed: _isSubmitting ? null : _onLogIn),
              const SizedBox(height: 20),
              const _OrDivider(),
              const SizedBox(height: 20),
              _GoogleButton(
                onPressed: _isSubmitting ? null : () => _onContinueWithGoogle(),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: const TextStyle(fontSize: 14, color: Colors.redAccent),
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

  final VoidCallback? onPressed;

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

  final VoidCallback? onPressed;

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

  final VoidCallback? onPressed;

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
