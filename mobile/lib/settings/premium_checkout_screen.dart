import 'package:mobile/core/responsive/responsive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth/auth_models.dart';
import '../core/api/api_client.dart';

/// Simulated checkout: card details never leave this screen or get stored.
class PremiumCheckoutScreen extends StatefulWidget {
  const PremiumCheckoutScreen({super.key, required this.onActivate});
  final Future<AuthUser> Function() onActivate;
  @override
  State<PremiumCheckoutScreen> createState() => _PremiumCheckoutScreenState();
}

class _PremiumCheckoutScreenState extends State<PremiumCheckoutScreen> {
  final _form = GlobalKey<FormState>();
  final _controllers = List.generate(4, (_) => TextEditingController());
  bool _busy = false;
  AuthUser? _user;
  String? _error;

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      if (!mounted) return;
      final user = await widget.onActivate();
      if (!mounted) return;
      for (final controller in _controllers) {
        controller.clear();
      }
      setState(() => _user = user);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not activate Premium. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    int index,
    String label,
    String hint,
    String? Function(String?) validator,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: TextFormField(
        controller: _controllers[index],
        enabled: !_busy,
        keyboardType: index == 0 ? TextInputType.name : TextInputType.number,
        obscureText: index == 3,
        autocorrect: false,
        enableSuggestions: false,
        inputFormatters: index == 0
            ? [LengthLimitingTextInputFormatter(100)]
            : index == 2
            ? [_ExpiryDateFormatter()]
            : [
                FilteringTextInputFormatter.allow(
                  RegExp(index == 1 ? r'[0-9 ]' : r'[0-9]'),
                ),
                LengthLimitingTextInputFormatter(index == 1 ? 23 : 4),
              ],
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: const Color(0xFF17161F),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
        validator: validator,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy && _user == null,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && _user != null) Navigator.of(context).pop(_user);
    },
    child: Scaffold(
      backgroundColor: const Color(0xFF0E0E15),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0E15),
        automaticallyImplyLeading: !_busy && _user == null,
        title: Text(_user == null ? 'Premium checkout' : 'Welcome to Premium'),
      ),
      body: ResponsiveContent(
        maxWidth: 720,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF494BD6), Color(0xFF242444)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _user == null
                            ? Icons.workspace_premium_rounded
                            : Icons.check_circle_rounded,
                        color: const Color(0xFF2FD9F4),
                        size: 40,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _user == null
                            ? 'Music Room Premium'
                            : "You're on Premium!",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Unlimited suggestions & votes\nEdit public playlists',
                        style: TextStyle(color: Colors.white70, height: 1.6),
                      ),
                      const Divider(height: 32, color: Colors.white24),
                      Text(
                        _user == null
                            ? 'Due today: 0.00 • Demo upgrade'
                            : 'Upgrade complete • No charge made',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                if (_user != null)
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(_user),
                    child: const Text('Continue to Premium'),
                  )
                else ...[
                  const Text(
                    'Card details',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Demo checkout — use test details, not a real card. Nothing is charged or saved.\nTry 4242 4242 4242 4242, a future expiry and any 3-digit CVC.',
                    style: TextStyle(color: Color(0xFF908FA0), height: 1.5),
                  ),
                  const SizedBox(height: 20),
                  Form(
                    key: _form,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    child: Column(
                      children: [
                        _field(
                          0,
                          'Cardholder name',
                          'Alex Morgan',
                          (v) => (v ?? '').trim().length < 2
                              ? 'Enter the cardholder name.'
                              : null,
                        ),
                        _field(
                          1,
                          'Card number',
                          '4242 4242 4242 4242',
                          validateDemoCard,
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _field(
                                2,
                                'Expiry date',
                                'MM/YY',
                                validateDemoExpiry,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _field(
                                3,
                                'CVC',
                                '123',
                                (v) => RegExp(r'^\d{3,4}$').hasMatch(v ?? '')
                                    ? null
                                    : 'Enter 3 or 4 digits.',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  SizedBox(
                    height: 54,
                    child: FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Text('Processing demo payment…'),
                              ],
                            )
                          : const Text('Confirm & activate Premium'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No recurring payments. Switch back to Free in Settings.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF908FA0), fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _ExpiryDateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final limited = digits.substring(0, digits.length.clamp(0, 4));
    final deleting = newValue.text.length < oldValue.text.length;
    final addSlash = limited.length > 2 || (limited.length == 2 && !deleting);
    final text = addSlash
        ? '${limited.substring(0, 2)}/${limited.substring(2)}'
        : limited;

    int mapOffset(int offset) {
      if (offset < 0) return text.length;
      final before = newValue.text.substring(
        0,
        offset.clamp(0, newValue.text.length),
      );
      final count = before.replaceAll(RegExp(r'[^0-9]'), '').length;
      return (count + (addSlash && count >= 2 ? 1 : 0)).clamp(0, text.length);
    }

    return TextEditingValue(
      text: text,
      selection: TextSelection(
        baseOffset: mapOffset(newValue.selection.baseOffset),
        extentOffset: mapOffset(newValue.selection.extentOffset),
      ),
    );
  }
}

String? validateDemoCard(String? value) {
  final digits = (value ?? '').replaceAll(' ', '');
  if (!RegExp(r'^\d{13,19}$').hasMatch(digits) ||
      RegExp(r'^(\d)\1+$').hasMatch(digits)) {
    return 'Enter a valid test card number.';
  }
  var sum = 0;
  for (var i = 0; i < digits.length; i++) {
    var digit = int.parse(digits[digits.length - 1 - i]);
    if (i.isOdd) {
      digit *= 2;
      if (digit > 9) digit -= 9;
    }
    sum += digit;
  }
  return sum % 10 == 0 ? null : 'Check the card number.';
}

String? validateDemoExpiry(String? value) {
  final match = RegExp(r'^(\d{2})/(\d{2})$').firstMatch(value ?? '');
  if (match == null) return 'Use MM/YY.';
  final month = int.parse(match.group(1)!);
  final year = 2000 + int.parse(match.group(2)!);
  final now = DateTime.now();
  if (month < 1 || month > 12) return 'Enter a valid month.';
  if (year < now.year || (year == now.year && month < now.month)) {
    return 'Card has expired.';
  }
  return null;
}
