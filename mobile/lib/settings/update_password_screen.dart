import 'package:flutter/material.dart';

class _UpdateColors {
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

/// Lets a signed-in user change their password using their current
/// password, as opposed to the "forgot password" email-code flow in
/// `auth/reset_password_screen.dart` + `auth/change_password_screen.dart`.
///
/// TODO: The backend has no authenticated "change password" endpoint yet
/// (only the unauthenticated email-code reset flow — see
/// `authentication/views.py`). This screen is fully built and validated
/// client-side so it's ready to wire up once that endpoint exists; for
/// now [_onUpdatePassword] stops short of calling anything and tells the
/// user the feature isn't available yet, rather than faking success.
class UpdatePasswordScreen extends StatefulWidget {
  const UpdatePasswordScreen({super.key});

  @override
  State<UpdatePasswordScreen> createState() => _UpdatePasswordScreenState();
}

class _UpdatePasswordScreenState extends State<UpdatePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isCurrentPasswordVisible = false;
  bool _isNewPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _onUpdatePassword() async {
    if (_isSubmitting) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    // No backend endpoint exists for this yet (see class doc). Simulate
    // the round-trip delay so the loading state is exercised, then tell
    // the user honestly rather than pretending it succeeded.
    await Future<void>.delayed(const Duration(milliseconds: 400));

    if (!mounted) return;
    setState(() => _isSubmitting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Changing your password isn't available yet — check back soon."),
      ),
    );
  }

  void _onBackToSignIn() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _UpdateColors.background,
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
                  label: 'CURRENT PASSWORD',
                  hint: 'Enter your current password',
                  controller: _currentPasswordController,
                  obscureText: !_isCurrentPasswordVisible,
                  prefixIcon: Icons.lock_outline,
                  suffixIcon: _VisibilityToggle(
                    isVisible: _isCurrentPasswordVisible,
                    onPressed: () => setState(
                      () => _isCurrentPasswordVisible = !_isCurrentPasswordVisible,
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Current password is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                _LabeledField(
                  label: 'NEW PASSWORD',
                  hint: 'Enter your new password',
                  controller: _newPasswordController,
                  obscureText: !_isNewPasswordVisible,
                  prefixIcon: Icons.lock_reset_rounded,
                  suffixIcon: _VisibilityToggle(
                    isVisible: _isNewPasswordVisible,
                    onPressed: () =>
                        setState(() => _isNewPasswordVisible = !_isNewPasswordVisible),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'New password is required';
                    }
                    if (value.length < 8) {
                      return 'Password must be at least 8 characters';
                    }
                    if (value == _currentPasswordController.text) {
                      return 'New password must be different from the current one';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                _LabeledField(
                  label: 'CONFIRM NEW PASSWORD',
                  hint: 'Repeat your new password',
                  controller: _confirmPasswordController,
                  obscureText: !_isConfirmPasswordVisible,
                  prefixIcon: Icons.restore,
                  suffixIcon: _VisibilityToggle(
                    isVisible: _isConfirmPasswordVisible,
                    onPressed: () => setState(
                      () => _isConfirmPasswordVisible = !_isConfirmPasswordVisible,
                    ),
                  ),
                  validator: (value) {
                    if (value != _newPasswordController.text) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 20),
                  _ErrorMessage(message: _errorMessage!),
                ],
                const SizedBox(height: 28),
                _UpdatePasswordButton(
                  onPressed: _isSubmitting ? null : _onUpdatePassword,
                  isLoading: _isSubmitting,
                ),
                const SizedBox(height: 16),
                _BackToSignInButton(onPressed: _onBackToSignIn),
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
        icon: const Icon(Icons.arrow_back, color: _UpdateColors.inputText, size: 28),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Change Password',
      style: TextStyle(
        fontFamily: 'Sora',
        fontWeight: FontWeight.w800,
        fontSize: 36,
        height: 1.1,
        letterSpacing: -0.02 * 36,
        color: _UpdateColors.title,
      ),
    );
  }
}

class _Description extends StatelessWidget {
  const _Description();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Enter your current password, then choose a new one to protect your account.',
      style: TextStyle(fontSize: 16, height: 1.5, color: _UpdateColors.description),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.obscureText,
    required this.prefixIcon,
    required this.suffixIcon,
    required this.validator,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final bool obscureText;
  final IconData prefixIcon;
  final Widget suffixIcon;
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
            color: _UpdateColors.label,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          validator: validator,
          style: const TextStyle(fontSize: 16, color: _UpdateColors.inputText),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 16, color: _UpdateColors.hintText),
            prefixIcon: Icon(prefixIcon, color: _UpdateColors.hintText, size: 20),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: _UpdateColors.fieldBackground,
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: _UpdateColors.fieldBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: _UpdateColors.fieldBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: _UpdateColors.tertiary),
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

class _VisibilityToggle extends StatelessWidget {
  const _VisibilityToggle({required this.isVisible, required this.onPressed});

  final bool isVisible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(
        isVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        color: _UpdateColors.hintText,
      ),
    );
  }
}

class _UpdatePasswordButton extends StatelessWidget {
  const _UpdatePasswordButton({required this.onPressed, this.isLoading = false});

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
          colors: [_UpdateColors.gradientStart, _UpdateColors.gradientEnd],
        ),
        boxShadow: [
          BoxShadow(
            color: _UpdateColors.gradientEnd.withValues(alpha: 0.4),
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
                    'Update Password',
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
          side: const BorderSide(color: _UpdateColors.tertiary, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: const Text(
          'Cancel',
          style: TextStyle(
            fontFamily: 'Sora',
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: _UpdateColors.tertiary,
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
    return Text(message, style: const TextStyle(fontSize: 14, color: Colors.redAccent));
  }
}
