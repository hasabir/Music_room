import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/api/api_client.dart';
import 'auth_api.dart';
import 'login_screen.dart';
import 'password_reset_code_screen.dart';

class _ResetColors {
  static const background = Color(0xFF0E0E15);
  static const title = Color(0xFFEDEDF5);
  static const description = Color(0xFFC7C4D7);
  static const label = Color(0xFF2FD9F4);
  static const fieldBackground = Color(0xFF1B1B26);
  static const fieldBorder = Color(0xFF34333F);
  static const hintText = Color(0xFF7A7889);
  static const inputText = Color(0xFFE4E1EB);
  static const gradientStart = Color(0xFF8083FF);
  static const gradientEnd = Color(0xFF494BD6);
  static const tertiary = Color(0xFF2FD9F4);
}

/// First screen of the password-reset flow, reached from the Login
/// screen's "Forgot password?" link.
///
/// Collects the account's email and requests a reset code from the
/// backend via [AuthApi.requestPasswordReset]. On success, moves to
/// [PasswordResetCodeScreen] to collect the 6-digit code the backend
/// emailed.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, this.initialEmail});

  /// Prefills the email field, e.g. when reached from Settings for an
  /// already-known account rather than the "Forgot password?" link.
  final String? initialEmail;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _emailController = TextEditingController(text: widget.initialEmail);
  final _authApi = AuthApi();

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _onSendResetLink() async {
    if (_isSubmitting) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final email = _emailController.text.trim();
    try {
      final devReset = await _authApi.requestPasswordReset(email: email);

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              PasswordResetCodeScreen(email: email, initialDevCode: devReset),
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
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
      backgroundColor: _ResetColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                const SizedBox(height: 8),
                _BackButton(onPressed: () => Navigator.of(context).pop()),
                const SizedBox(height: 24),
                const _Title(),
                const SizedBox(height: 12),
                const _Description(),
                const SizedBox(height: 32),
                _LabeledField(
                  label: 'EMAIL ADDRESS',
                  hint: 'name@example.com',
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Email is required';
                    }
                    if (!value.contains('@') || !value.contains('.')) {
                      return 'Enter a valid email';
                    }
                    return null;
                  },
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 20),
                  _ErrorMessage(message: _errorMessage!),
                ],
                const SizedBox(height: 28),
                _SendResetLinkButton(
                  onPressed: _isSubmitting ? null : _onSendResetLink,
                  isLoading: _isSubmitting,
                ),
                const SizedBox(height: 16),
                _BackToSignInButton(onPressed: _onBackToSignIn),
                const SizedBox(height: 32),
                _LogInPrompt(onPressed: _onBackToSignIn),
                const SizedBox(height: 24),
              ],
            ),
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
          color: _ResetColors.inputText,
          size: 28,
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Reset Password',
      style: TextStyle(
        fontFamily: 'Sora',
        fontWeight: FontWeight.w800,
        fontSize: 36,
        height: 1.1,
        letterSpacing: -0.02 * 36,
        color: _ResetColors.title,
      ),
    );
  }
}

class _Description extends StatelessWidget {
  const _Description();

  @override
  Widget build(BuildContext context) {
    return const Text(
      "Enter your email and we'll send you a link to get back into your "
      'account.',
      style: TextStyle(
        fontSize: 16,
        height: 1.5,
        color: _ResetColors.description,
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.hint,
    required this.controller,
    this.keyboardType,
    this.validator,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.05 * 12,
            color: _ResetColors.label,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          style: const TextStyle(fontSize: 16, color: _ResetColors.inputText),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              fontSize: 16,
              color: _ResetColors.hintText,
            ),
            filled: true,
            fillColor: _ResetColors.fieldBackground,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 18,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: _ResetColors.fieldBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: _ResetColors.fieldBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: _ResetColors.tertiary),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.redAccent),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.redAccent),
            ),
          ),
        ),
      ],
    );
  }
}

class _SendResetLinkButton extends StatelessWidget {
  const _SendResetLinkButton({required this.onPressed, this.isLoading = false});

  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_ResetColors.gradientStart, _ResetColors.gradientEnd],
        ),
        boxShadow: [
          BoxShadow(
            color: _ResetColors.gradientEnd.withValues(alpha: 0.4),
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
                    'Send Reset Link',
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

class _BackToSignInButton extends StatelessWidget {
  const _BackToSignInButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.transparent,
          side: const BorderSide(color: _ResetColors.tertiary, width: 1.5),
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
            color: _ResetColors.tertiary,
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

class _LogInPrompt extends StatelessWidget {
  const _LogInPrompt({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 14, color: _ResetColors.description),
          children: [
            const TextSpan(text: 'Remember your password?  '),
            TextSpan(
              text: 'Log in here',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: _ResetColors.gradientStart,
              ),
              recognizer: (TapGestureRecognizer()..onTap = onPressed),
            ),
          ],
        ),
      ),
    );
  }
}
