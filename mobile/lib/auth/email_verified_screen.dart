import 'package:flutter/material.dart';

import 'login_screen.dart';

class _VerifiedColors {
  static const background = Color(0xFF0E0E15);
  static const title = Color(0xFFEDEDF5);
  static const description = Color(0xFFC7C4D7);
  static const iconGlow = Color(0xFF2FD9F4);
  static const checkCircle = Color(0xFF2FD9F4);
  static const checkMark = Color(0xFF0E0E15);
  static const gradientStart = Color(0xFF8083FF);
  static const gradientEnd = Color(0xFF494BD6);
}

/// Shown once the backend has confirmed the account's email is verified
/// (see [AuthApi.verifyEmail]) — never shown just because the user pressed
/// a button.
///
/// The backend's verify-email endpoint doesn't return auth tokens, only a
/// confirmation that `is_email_verified` is now true, so "Continue to
/// Music Room" takes the user to sign in rather than straight into the
/// authenticated app. If the backend's contract changes to return tokens
/// here, this is the one place that needs updating.
class EmailVerifiedScreen extends StatelessWidget {
  const EmailVerifiedScreen({super.key});

  void _onContinue(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _VerifiedColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 8),
              _BackButton(onPressed: () => Navigator.of(context).pop()),
              const Spacer(flex: 3),
              const _SuccessIcon(),
              const SizedBox(height: 32),
              const Text(
                'Email verified !',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Sora',
                  fontWeight: FontWeight.w800,
                  fontSize: 32,
                  height: 1.1,
                  color: _VerifiedColors.title,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Your email address has been\n'
                'successfully verified. Your Music Room\n'
                'account is ready.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  color: _VerifiedColors.description,
                ),
              ),
              const Spacer(flex: 4),
              _ContinueButton(onPressed: () => _onContinue(context)),
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
          color: _VerifiedColors.title,
          size: 28,
        ),
      ),
    );
  }
}

class _SuccessIcon extends StatelessWidget {
  const _SuccessIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _VerifiedColors.iconGlow.withValues(alpha: 0.08),
        boxShadow: [
          BoxShadow(
            color: _VerifiedColors.iconGlow.withValues(alpha: 0.3),
            blurRadius: 50,
            spreadRadius: 6,
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: 76,
          height: 76,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: _VerifiedColors.checkCircle,
          ),
          child: const Icon(
            Icons.check,
            color: _VerifiedColors.checkMark,
            size: 40,
          ),
        ),
      ),
    );
  }
}

class _ContinueButton extends StatelessWidget {
  const _ContinueButton({required this.onPressed});

  final VoidCallback onPressed;

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
            colors: [
              _VerifiedColors.gradientStart,
              _VerifiedColors.gradientEnd,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: _VerifiedColors.gradientEnd.withValues(alpha: 0.4),
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
                'Continue to Music Room',
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
