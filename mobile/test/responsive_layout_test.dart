import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/responsive/responsive.dart';
import 'package:mobile/core/widgets/app_bottom_nav.dart';

void main() {
  testWidgets('navigation adapts when the browser is resized', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    AppTab? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: ResponsiveScaffold(
          currentTab: AppTab.home,
          onTabSelected: (tab) => selected = tab,
          body: const SizedBox.expand(),
        ),
      ),
    );
    expect(find.byType(AppBottomNav), findsOneWidget);
    await tester.tap(find.text('Vote'));
    expect(selected, AppTab.vote);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1024, 240);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(AppBottomNav), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Profile'));
    await tester.tap(find.text('Profile'));
    expect(selected, AppTab.profile);
  });

  testWidgets(
    'card columns account for spacing and resize without undersizing',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(730, 600);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ResponsiveCardGrid(
              children: [
                for (var i = 0; i < 3; i++)
                  SizedBox(key: ValueKey(i), height: 100),
              ],
            ),
          ),
        ),
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey(1))).dy,
        greaterThan(tester.getTopLeft(find.byKey(const ValueKey(0))).dy),
      );
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(736, 600);
      await tester.pump();
      expect(tester.getSize(find.byKey(const ValueKey(0))).width, 360);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey(1))).dy,
        tester.getTopLeft(find.byKey(const ValueKey(0))).dy,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('hero actions remain reachable with keyboard and enlarged text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var pressed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            viewInsets: EdgeInsets.only(bottom: 280),
            textScaler: TextScaler.linear(1.5),
          ),
          child: Scaffold(
            body: ResponsiveContent(
              child: ResponsiveScrollColumn(
                children: [
                  const Spacer(),
                  const SizedBox(
                    height: 300,
                    child: Text('Welcome to Music Room'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => pressed = true,
                    child: const Text('Continue'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Continue'));
    await tester.tap(find.text('Continue'));
    expect(pressed, isTrue);
    expect(tester.takeException(), isNull);
  });
}
