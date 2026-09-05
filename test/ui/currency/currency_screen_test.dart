import 'package:easa_digital_log/ui/currency/currency_screen.dart';
import 'package:easa_digital_log/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression coverage for the hero-card row overflowing at larger system
/// text sizes (found on-device: a fixed-height `SizedBox` around the
/// horizontal hero list clipped its content once "Due soon"/"Expired"
/// cards grew past the pixel height the box was tuned for at default
/// text scale).
void main() {
  Future<void> pumpScreen(WidgetTester tester, {double textScale = 1.0}) async {
    tester.view.physicalSize = const Size(390, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const CurrencyScreen(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'renders the dashboard without overflowing at default text scale',
    (tester) async {
      await pumpScreen(tester);

      expect(find.text('Currency'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the hero card row holds at a large but common text scale (regression: '
    'a fixed-height SizedBox around it used to clip at anything above '
    'default)',
    (tester) async {
      await pumpScreen(tester, textScale: 1.6);

      expect(find.text('Currency'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
