import 'package:flutter/material.dart';

import '../core/api/api_client.dart';
import 'auth_api.dart';
import 'auth_models.dart';
import 'email_verified_screen.dart';
import 'verification_expired_screen.dart';

class _PendingColors {
  static const background = Color(0xFF0E0E15);
  static const title = Color(0xFFEDEDF5);
  static const description = Color(0xFFC7C4D7);
  static const iconBackground = Color(0xFF14171D);
  static const iconGlow = Color(0xFF2FD9F4);
  static const gradientStart = Color(0xFF8083FF);
  static const gradientEnd = Color(0xFF494BD6);
  static const tertiary = Color(0xFF2FD9F4);
  static const statusText = Color(0xFF8B899B);
  static const errorText = Color(0xFFFF8A8A);
  static const successText = Color(0xFF6EE7C8);
}

/// Shown immediately after a successful registration, while the account
/// still needs its email verified before the user can log in.
///
/// The backend is the source of truth for verification: this screen never
/// assumes success on its own. It confirms verification with
/// [AuthApi.verifyEmail] using a uid/token pair, which is only available
/// here if the backend included it as `dev_verification` (dev-email mode)
/// on registration or resend. Outside of dev mode there is no
/// verification-status-by-email endpoint to poll, so pressing "I've
/// Verified" without a known uid/token honestly reports that verification
/// can't be confirmed yet, rather than faking success.
class EmailVerificationPendingScreen extends StatefulWidget {
  const EmailVerificationPendingScreen({
    super.key,
    required this.email,
    this.initialDevVerification,
  });

  final String email;
  final DevVerificationInfo? initialDevVerification;

  @override
  State<EmailVerificationPendingScreen> createState() =>
      _EmailVerificationPendingScreenState();
}

class _EmailVerificationPendingScreenState
    extends State<EmailVerificationPendingScreen> {
  final _authApi = AuthApi();

  late DevVerificationInfo? _devVerification;
  bool _isCheckingVerification = false;
  bool _isResending = false;
  String? _statusMessage;
  bool _statusIsError = true;

  @override
  void initState() {
    super.initState();
    _devVerification = widget.initialDevVerification;
  }

  Future<void> _onIveVerified() async {
    if (_isCheckingVerification || _isResending) return;

    final devVerification = _devVerification;
    if (devVerification == null) {
      setState(() {
        _statusIsError = true;
        _statusMessage = "Your email hasn't been verified yet.";
      });
      return;
    }

    setState(() {
      _isCheckingVerification = true;
      _statusMessage = null;
    });

    try {
      await _authApi.verifyEmail(
        uid: devVerification.uid,
        token: devVerification.token,
      );

      if (!mounted) return;
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const EmailVerifiedScreen()));
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.statusCode == 400) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VerificationExpiredScreen(email: widget.email),
          ),
        );
      } else {
        setState(() {
          _statusIsError = true;
          _statusMessage = error.message;
        });
      }
    } finally {
      if (mounted) setState(() => _isCheckingVerification = false);
    }
  }

  Future<void> _onResend() async {
    if (_isResending || _isCheckingVerification) return;

    setState(() {
      _isResending = true;
      _statusMessage = null;
    });

    try {
      final devVerification = await _authApi.resendVerificationEmail(
        email: widget.email,
      );

      if (!mounted) return;
      setState(() {
        _devVerification = devVerification ?? _devVerification;
        _statusIsError = false;
        _statusMessage = 'Verification email sent.';
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _statusIsError = true;
        _statusMessage = error.message;
      });
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _PendingColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 8),
              _BackButton(onPressed: () => Navigator.of(context).pop()),
              const Spacer(flex: 3),
              const _VerificationIcon(),
              const SizedBox(height: 32),
              const Text(
                'Check your inbox',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Sora',
                  fontWeight: FontWeight.w800,
                  fontSize: 32,
                  height: 1.1,
                  color: _PendingColors.title,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'We sent a verification link to your email. Please '
                'click it to activate your account.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  color: _PendingColors.description,
                ),
              ),
              const Spacer(flex: 4),
              if (_statusMessage != null) ...[
                Text(
                  _statusMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: _statusIsError
                        ? _PendingColors.errorText
                        : _PendingColors.successText,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              _PrimaryButton(
                label: "I've Verified",
                icon: Icons.check_circle_outline,
                isLoading: _isCheckingVerification,
                onPressed: _isResending ? null : _onIveVerified,
              ),
              const SizedBox(height: 16),
              _SecondaryButton(
                label: 'Resend Email',
                icon: Icons.refresh,
                isLoading: _isResending,
                onPressed: _isCheckingVerification ? null : _onResend,
              ),
              const SizedBox(height: 32),
              const _StatusIndicator(),
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
          color: _PendingColors.title,
          size: 28,
        ),
      ),
    );
  }
}

class _VerificationIcon extends StatelessWidget {
  const _VerificationIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _PendingColors.iconBackground,
        border: Border.all(
          color: _PendingColors.iconGlow.withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: _PendingColors.iconGlow.withValues(alpha: 0.25),
            blurRadius: 40,
            spreadRadius: 4,
          ),
        ],
      ),
      child: const Center(
        child: Icon(
          Icons.mark_email_unread_outlined,
          color: _PendingColors.iconGlow,
          size: 48,
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.isLoading = false,
  });

  final String label;
  final IconData icon;
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
            colors: [_PendingColors.gradientStart, _PendingColors.gradientEnd],
          ),
          boxShadow: [
            BoxShadow(
              color: _PendingColors.gradientEnd.withValues(alpha: 0.4),
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
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            fontFamily: 'Sora',
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(icon, color: Colors.white, size: 20),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.isLoading = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.transparent,
          side: const BorderSide(color: _PendingColors.tertiary, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation(_PendingColors.tertiary),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontFamily: 'Sora',
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: _PendingColors.tertiary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.refresh,
                    color: _PendingColors.tertiary,
                    size: 20,
                  ),
                ],
              ),
      ),
    );
  }
}

/// The technical-looking "● AWAITING_SIGNAL" status readout, with a
/// gently pulsing dot.
class _StatusIndicator extends StatefulWidget {
  const _StatusIndicator();

  @override
  State<_StatusIndicator> createState() => _StatusIndicatorState();
}

class _StatusIndicatorState extends State<_StatusIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _opacity = Tween<double>(
      begin: 0.4,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FadeTransition(
          opacity: _opacity,
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: _PendingColors.tertiary,
            ),
          ),
        ),
        const SizedBox(width: 10),
        const Text(
          'AWAITING_SIGNAL',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            letterSpacing: 1.5,
            color: _PendingColors.statusText,
          ),
        ),
      ],
    );
  }
}
