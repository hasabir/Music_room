import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/settings/premium_checkout_screen.dart';

void main() {
  test('test card validation rejects malformed numbers', () {
    expect(validateDemoCard('4242 4242 4242 4242'), isNull);
    expect(validateDemoCard('4242424242424241'), isNotNull);
    expect(validateDemoCard('0000000000000000'), isNotNull);
    expect(validateDemoCard('123'), isNotNull);
  });
  test('expiry accepts current month and rejects expired or invalid dates', () {
    final now = DateTime.now();
    expect(
      validateDemoExpiry(
        '${now.month.toString().padLeft(2, '0')}/${(now.year % 100).toString().padLeft(2, '0')}',
      ),
      isNull,
    );
    expect(validateDemoExpiry('01/20'), isNotNull);
    expect(validateDemoExpiry('13/99'), isNotNull);
    expect(validateDemoExpiry('1234'), isNotNull);
  });
  testWidgets('invalid form cannot activate Premium', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PremiumCheckoutScreen(
          onActivate: () async {
            calls++;
            throw StateError('Unexpected activation');
          },
        ),
      ),
    );
    await tester.ensureVisible(find.text('Confirm & activate Premium'));
    await tester.tap(find.text('Confirm & activate Premium'));
    await tester.pump();
    expect(calls, 0);
    expect(find.text('Enter the cardholder name.'), findsOneWidget);
  });
}
