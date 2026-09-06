import 'package:easa_digital_log/ui/io/import_screen.dart';
import 'package:easa_digital_log/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A render-only test — actually driving `file_picker`'s native dialog
/// isn't exercised here (it's a platform channel with no fake to hand a
/// path back through in a widget test); this proves the three format
/// options are presented and the screen doesn't crash before a pilot picks
/// one.
void main() {
  testWidgets('presents the three supported import formats', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const ImportScreen()),
    );

    expect(find.text('ForeFlight'), findsOneWidget);
    expect(find.text('Garmin Pilot'), findsOneWidget);
    expect(find.text('Generic CSV'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the back button pops the screen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const ImportScreen()),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Import'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Import'), findsNothing);
    expect(find.text('Open'), findsOneWidget);
  });
}
