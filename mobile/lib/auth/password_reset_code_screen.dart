import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api/api_client.dart';
import 'auth_api.dart';
import 'auth_models.dart';
import 'change_password_screen.dart';

class _CodeColors {
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
  static const fieldBackground = Color(0xFF1B1B26);
  static const fieldBorder = Color(0xFF34333F);
}

/// Second step of the password-reset flow: collects the 6-digit code the
/// backend emailed, reusing the same code-entry pattern as
/// [EmailVerificationPendingScreen].
///
/// Confirms the code via [AuthApi.verifyPasswordResetCode] before moving
/// on — that call checks the code without consuming it or requiring a
/// password yet (`PasswordResetVerifyCodeSerializer`), since the code
/// still has to be resubmitted to `/password-reset/confirm/` on
/// [ChangePasswordScreen] to actually be consumed and set the new
/// password.
class PasswordResetCodeScreen extends StatefulWidget {
  const PasswordResetCodeScreen({
    super.key,
    required this.email,
    this.initialDevCode,
  });

  final String email;
  final VerificationCodeInfo? initialDevCode;

  @override
  State<PasswordResetCodeScreen> createState() =>
      _PasswordResetCodeScreenState();
}

class _PasswordResetCodeScreenState extends State<PasswordResetCodeScreen> {
  final _authApi = AuthApi();
  final _codeController = TextEditingController();

  bool _isVerifying = false;
  bool _isResending = false;
  String? _statusMessage;
  bool _statusIsError = true;

  @override
  void initState() {
    super.initState();
    if (widget.initialDevCode != null) {
      _codeController.text = widget.initialDevCode!.code;
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _onContinue() async {
    if (_isVerifying || _isResending) return;

    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() {
        _statusIsError = true;
        _statusMessage = 'Enter the 6-digit code from your email.';
      });
      return;
    }

    setState(() {
      _isVerifying = true;
      _statusMessage = null;
    });

    try {
      await _authApi.verifyPasswordResetCode(email: widget.email, code: code);

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChangePasswordScreen(email: widget.email, code: code),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _statusIsError = true;
        _statusMessage = error.message;
      });
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _onResend() async {
    if (_isResending || _isVerifying) return;

    setState(() {
      _isResending = true;
      _statusMessage = null;
    });

    try {
      final devCode = await _authApi.requestPasswordReset(email: widget.email);

      if (!mounted) return;
      setState(() {
        if (devCode != null) _codeController.text = devCode.code;
        _statusIsError = false;
        _statusMessage = 'Reset code sent.';
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
      backgroundColor: _CodeColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ListView(
            children: [
              const SizedBox(height: 8),
              _BackButton(onPressed: () => Navigator.of(context).pop()),
              const SizedBox(height: 32),
              const Center(child: _CodeIcon()),
              const SizedBox(height: 32),
              const Text(
                'Check your inbox',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Sora',
                  fontWeight: FontWeight.w800,
                  fontSize: 32,
                  height: 1.1,
                  color: _CodeColors.title,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'We sent a 6-digit reset code to your email. Enter it '
                'below to continue.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  color: _CodeColors.description,
                ),
              ),
              const SizedBox(height: 32),
              _CodeField(controller: _codeController),
              const SizedBox(height: 24),
              if (_statusMessage != null) ...[
                Text(
                  _statusMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: _statusIsError
                        ? _CodeColors.errorText
                        : _CodeColors.successText,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              _PrimaryButton(
                label: 'Continue',
                isLoading: _isVerifying,
                onPressed: _isResending ? null : _onContinue,
              ),
              const SizedBox(height: 16),
              _SecondaryButton(
                label: 'Resend Email',
                icon: Icons.refresh,
                isLoading: _isResending,
                onPressed: _isVerifying ? null : _onResend,
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
        icon: const Icon(Icons.arrow_back, color: _CodeColors.title, size: 28),
      ),
    );
  }
}

class _CodeIcon extends StatelessWidget {
  const _CodeIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _CodeColors.iconBackground,
        border: Border.all(
          color: _CodeColors.iconGlow.withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: _CodeColors.iconGlow.withValues(alpha: 0.25),
            blurRadius: 40,
            spreadRadius: 4,
          ),
        ],
      ),
      child: const Center(
        child: Icon(
          Icons.mark_email_unread_outlined,
          color: _CodeColors.iconGlow,
          size: 48,
        ),
      ),
    );
  }
}

class _CodeField extends StatelessWidget {
  const _CodeField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'VERIFICATION CODE',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.05 * 12,
            color: _CodeColors.tertiary,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: 6,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: 12,
            color: _CodeColors.title,
          ),
          decoration: InputDecoration(
            counterText: '',
            hintText: '000000',
            hintStyle: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: 12,
              color: _CodeColors.statusText,
            ),
            filled: true,
            fillColor: _CodeColors.fieldBackground,
            contentPadding: const EdgeInsets.symmetric(vertical: 18),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: _CodeColors.fieldBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: _CodeColors.fieldBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: _CodeColors.tertiary),
            ),
          ),
        ),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  final String label;
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
            colors: [_CodeColors.gradientStart, _CodeColors.gradientEnd],
          ),
          boxShadow: [
            BoxShadow(
              color: _CodeColors.gradientEnd.withValues(alpha: 0.4),
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
                  : Text(
                      label,
                      style: const TextStyle(
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
          side: const BorderSide(color: _CodeColors.tertiary, width: 1.5),
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
                  valueColor: AlwaysStoppedAnimation(_CodeColors.tertiary),
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
                      color: _CodeColors.tertiary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(icon, color: _CodeColors.tertiary, size: 20),
                ],
              ),
      ),
    );
  }
}

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
              color: _CodeColors.tertiary,
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
            color: _CodeColors.statusText,
          ),
        ),
      ],
    );
  }
}
