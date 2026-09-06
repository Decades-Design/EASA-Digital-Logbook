import 'package:drift/native.dart';
import 'package:easa_digital_log/data/database.dart';
import 'package:easa_digital_log/domain/repository/flight_read_repository.dart';
import 'package:easa_digital_log/ui/io/generic_csv_mapping_screen.dart';
import 'package:easa_digital_log/ui/io/import_preview_screen.dart';
import 'package:easa_digital_log/ui/providers/database_provider.dart';
import 'package:easa_digital_log/ui/providers/flight_records_providers.dart';
import 'package:easa_digital_log/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _csv =
    'Date,Off,On,Reg,From,To,PIC\n'
    '2026-01-01,10:00,11:00,N100AB,KABC,KDEF,1:00\n';

void main() {
  Future<void> pumpScreen(WidgetTester tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          // Navigating "Preview import" pushes ImportPreviewScreen, which
          // reads allFlightRecordsProvider — its real jurisdiction-asset/
          // drift-stream chain needs real wall-clock time under a widget
          // test's fake clock (see import_preview_screen_test.dart's own
          // note), irrelevant to what this screen's own tests check.
          allFlightRecordsProvider.overrideWith(
            (ref) async => <FlightRecord>[],
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const GenericCsvMappingScreen(csv: _csv),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> selectDropdown(
    WidgetTester tester,
    String labelText,
    String optionText,
  ) async {
    final dropdown = find.ancestor(
      of: find.text(labelText),
      matching: find.byType(DropdownButtonFormField<String?>),
    );
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text(optionText).last);
    await tester.pumpAndSettle();
  }

  testWidgets('detects the CSV header row and offers it in every dropdown', (
    tester,
  ) async {
    await pumpScreen(tester);

    final dateDropdown = find.ancestor(
      of: find.text('Date *'),
      matching: find.byType(DropdownButtonFormField<String?>),
    );
    await tester.tap(dateDropdown);
    await tester.pumpAndSettle();

    expect(find.text('Date').last, findsOneWidget);
    expect(find.text('Reg'), findsOneWidget);
    expect(find.text('PIC'), findsOneWidget);
  });

  testWidgets('shows which required fields are still missing rather than a raw '
      'exception', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('Preview import'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Still needs:'), findsOneWidget);
  });

  testWidgets(
    'mapping every required field and continuing opens the preview screen',
    (tester) async {
      await pumpScreen(tester);

      await selectDropdown(tester, 'Date *', 'Date');
      await selectDropdown(tester, 'Off-blocks time *', 'Off');
      await selectDropdown(tester, 'On-blocks time *', 'On');
      await selectDropdown(tester, 'Aircraft registration *', 'Reg');
      await selectDropdown(tester, 'Departure *', 'From');
      await selectDropdown(tester, 'Destination *', 'To');

      await tester.tap(find.text('Preview import'));
      await tester.pumpAndSettle();

      expect(find.byType(ImportPreviewScreen), findsOneWidget);
    },
  );
}
