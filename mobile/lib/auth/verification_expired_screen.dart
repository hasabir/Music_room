import 'package:flutter/material.dart';

import '../core/api/api_client.dart';
import 'auth_api.dart';
import 'email_verification_pending_screen.dart';
import 'login_screen.dart';

class _ExpiredColors {
  static const background = Color(0xFF0E0E15);
  static const title = Color(0xFFEDEDF5);
  static const description = Color(0xFFC7C4D7);
  static const errorGlow = Color(0xFFE5484D);
  static const errorBackground = Color(0xFF2B1216);
  static const errorIcon = Color(0xFFFFB4B4);
  static const gradientStart = Color(0xFF8083FF);
  static const gradientEnd = Color(0xFF494BD6);
  static const tertiary = Color(0xFF2FD9F4);
  static const errorText = Color(0xFFFF8A8A);
}

/// Shown when the backend reports that a verification uid/token pair is
/// invalid, already used, or expired (see [AuthApi.verifyEmail]).
class VerificationExpiredScreen extends StatefulWidget {
  const VerificationExpiredScreen({super.key, required this.email});

  final String email;

  @override
  State<VerificationExpiredScreen> createState() =>
      _VerificationExpiredScreenState();
}

class _VerificationExpiredScreenState extends State<VerificationExpiredScreen> {
  final _authApi = AuthApi();

  bool _isResending = false;
  String? _errorMessage;

  Future<void> _onSendNewEmail() async {
    if (_isResending) return;

    setState(() {
      _isResending = true;
      _errorMessage = null;
    });

    try {
      final devVerification = await _authApi.resendVerificationEmail(
        email: widget.email,
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => EmailVerificationPendingScreen(
            email: widget.email,
            initialDevVerification: devVerification,
          ),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  void _onBackToSignIn() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _ExpiredColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 8),
              _BackButton(onPressed: () => Navigator.of(context).pop()),
              const Spacer(flex: 3),
              const _ErrorIcon(),
              const SizedBox(height: 32),
              const Text(
                'Verification link\nexpired',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Sora',
                  fontWeight: FontWeight.w800,
                  fontSize: 32,
                  height: 1.15,
                  color: _ExpiredColors.title,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'This verification link is no longer valid.\n'
                'Request a new verification email to\n'
                'continue.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  color: _ExpiredColors.description,
                ),
              ),
              const Spacer(flex: 4),
              if (_errorMessage != null) ...[
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: _ExpiredColors.errorText,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              _SendNewEmailButton(
                onPressed: _isResending ? null : _onSendNewEmail,
                isLoading: _isResending,
              ),
              const SizedBox(height: 16),
              _BackToSignInButton(onPressed: _onBackToSignIn),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: IconButton(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        icon: const Icon(
          Icons.arrow_back,
          color: _ExpiredColors.title,
          size: 28,
        ),
      ),
    );
  }
}

class _ErrorIcon extends StatelessWidget {
  const _ErrorIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _ExpiredColors.errorBackground,
        boxShadow: [
          BoxShadow(
            color: _ExpiredColors.errorGlow.withValues(alpha: 0.25),
            blurRadius: 40,
            spreadRadius: 4,
          ),
        ],
      ),
      child: const Center(
        child: Icon(
          Icons.warning_amber_rounded,
          color: _ExpiredColors.errorIcon,
          size: 48,
        ),
      ),
    );
  }
}

class _SendNewEmailButton extends StatelessWidget {
  const _SendNewEmailButton({required this.onPressed, this.isLoading = false});

  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_ExpiredColors.gradientStart, _ExpiredColors.gradientEnd],
          ),
          boxShadow: [
            BoxShadow(
              color: _ExpiredColors.gradientEnd.withValues(alpha: 0.4),
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
            child: Center(
              child: isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : const Text(
                      'Send New Verification Email',
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
      ),
    );
  }
}

class _BackToSignInButton extends StatelessWidget {
  const _BackToSignInButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.transparent,
          side: const BorderSide(color: _ExpiredColors.tertiary, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: const Text(
          'Back to Sign In',
          style: TextStyle(
            fontFamily: 'Sora',
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: _ExpiredColors.tertiary,
          ),
        ),
      ),
    );
  }
}
