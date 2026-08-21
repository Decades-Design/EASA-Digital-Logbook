import 'package:easa_digital_log/ui/entry/new_flight_screen.dart';
import 'package:easa_digital_log/ui/entry/widgets/approach_row.dart';
import 'package:easa_digital_log/ui/entry/widgets/conditions_section.dart';
import 'package:easa_digital_log/ui/entry/widgets/times_section.dart';
import 'package:easa_digital_log/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Smoke coverage for the rebuilt Flight Entry Form (#58/#129,
/// `Flight Entry Form.dc.html`). Not a full interaction suite — just enough
/// to catch a render crash, a missing section, a layout overflow, or a
/// jurisdiction-loading regression before it reaches a device.
void main() {
  Future<void> pumpScreen(WidgetTester tester) async {
    // The default 800x600 test surface only builds the `ListView` children
    // inside its viewport (Sliver lazy-list semantics) — a tall surface
    // means every section builds, so `find.text` can see all of them and
    // any layout overflow anywhere on the screen surfaces here rather than
    // only on a device with a shorter, but differently-proportioned, page.
    tester.view.physicalSize = const Size(390, 9000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // `_pickTime` (new_flight_screen.dart) already forces 24-hour entry on
    // its own `showTimePicker` calls now — Zulu entry only makes sense in
    // 24-hour form — so `setTime` below can drive values like hour 21
    // without a test-side MediaQuery override to match.
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const NewFlightScreen()),
    );
    // Lets the async assets/jurisdictions/*.yaml load (see
    // `_loadJurisdictions`) settle before assertions run.
    await tester.pumpAndSettle();
  }

  testWidgets('renders every section in docs/entry-form.md §1 order', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.text('New flight'), findsOneWidget);
    expect(find.text('AIRCRAFT'), findsOneWidget);
    expect(find.text('DATE & ROUTE'), findsOneWidget);
    expect(find.text('TIMES'), findsOneWidget);
    expect(find.text('WHO ELSE WAS ON BOARD?'), findsOneWidget);
    expect(find.text('YOUR TAKE-OFFS AND LANDINGS'), findsOneWidget);
    expect(find.text('CONDITIONS'), findsOneWidget);
    expect(find.text('REMARKS AND ENDORSEMENTS'), findsOneWidget);
    expect(find.text('Save flight'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets('picking a fleet aircraft resolves its type and chips', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.enterText(find.byType(TextField).first, 'G-ARRW');
    await tester.pump();

    expect(find.textContaining('Piper PA-28-161 Warrior'), findsOneWidget);
    expect(find.text('SEP land'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'each of the four crew paths expands without throwing or overflowing, '
    'and the FAA-only IR currency group always shows (licences stubbed on)',
    (tester) async {
      await pumpScreen(tester);

      for (final label in [
        'Just me',
        'With an instructor',
        'With another pilot',
        'With passengers',
      ]) {
        await tester.tap(find.text(label));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'selecting "$label"');
      }

      expect(find.text('IR CURRENCY AND PROFICIENCY'), findsOneWidget);
    },
  );

  testWidgets(
    'picking a multi-pilot aircraft and completing the instructor path '
    '(purpose, countersignature) does not throw or overflow',
    (tester) async {
      await pumpScreen(tester);

      await tester.enterText(find.byType(TextField).first, 'G-VMPS');
      await tester.tap(find.text('Change aircraft'));
      await tester.pump();
      expect(find.text('MP'), findsOneWidget);

      await tester.tap(find.text('With an instructor'));
      await tester.pump();
      await tester.tap(
        find.widgetWithText(
          DropdownButtonFormField<String>,
          'Purpose of flight',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skill test').last);
      await tester.pumpAndSettle();
      expect(find.text('Examiner no.'), findsOneWidget);

      expect(find.text('not signed'), findsOneWidget);
      await tester.tap(find.text('Sign now'));
      await tester.pump();
      expect(find.text('not signed'), findsNothing);

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the "with another pilot" PICUS path (multi-pilot toggle, PICUS claim, '
    'split manipulation time) does not throw or overflow',
    (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('With another pilot'));
      await tester.pump();
      await tester.tap(find.text('Other pilot').first);
      await tester.pump();

      // EntryToggleRow's tap target is the Switch, not the label — tapping
      // the label text alone (as with a ChoiceChip) is a no-op here.
      await tester.tap(
        find.descendant(
          of: find.widgetWithText(Row, 'Multi-pilot operation'),
          matching: find.byType(Switch),
        ),
      );
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.widgetWithText(Row, 'Claim PICUS'),
          matching: find.byType(Switch),
        ),
      );
      await tester.pump();
      expect(
        find.textContaining('PIC intervention was not required'),
        findsOneWidget,
      );

      await tester.tap(find.text('Both — split'));
      await tester.pump();
      expect(find.text('My manipulation time'), findsOneWidget);

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('adding and removing an IR approach row does not throw', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.tap(find.text('+ Add approach'));
    await tester.pump();
    expect(find.text('Flown'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pump();
    expect(find.text('Flown'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a full ICAO code and runway designator are not clipped in an '
      'approach row (regression: the default InputDecorationTheme padding '
      'alone was wider than the box)', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.text('+ Add approach'));
    await tester.pump();

    final approachFields = find.descendant(
      of: find.byType(ApproachRow),
      matching: find.byType(TextField),
    );
    expect(approachFields, findsNWidgets(2));

    await tester.enterText(approachFields.first, 'EGKA');
    await tester.enterText(approachFields.last, '36L');
    await tester.pump();

    expect(
      tester.widget<TextField>(approachFields.first).controller!.text,
      'EGKA',
    );
    expect(
      tester.widget<TextField>(approachFields.last).controller!.text,
      '36L',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the derivation strip stays a placeholder until block times are set, '
    'even once aircraft and crew are',
    (tester) async {
      await pumpScreen(tester);

      await tester.enterText(find.byType(TextField).first, 'G-ARRW');
      await tester.pump();
      await tester.tap(find.text('Just me'));
      await tester.pump();

      // Off/on blocks default to unset ("--:--"), so `buildDraftFlight`
      // (flight_draft_mapper.dart) has nothing to project yet — the footer
      // must keep showing its placeholder, not a half-built breakdown.
      expect(
        find.textContaining('jurisdiction breakdown appears once crew is'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the scroll body starts right under the top bar, not offset by a '
      'second status-bar inset (regression: ListView auto-padding stacked '
      'on top of EntryTopBar\'s own SafeArea)', (tester) async {
    tester.view.padding = const FakeViewPadding(top: 30);
    addTearDown(tester.view.resetPadding);
    await pumpScreen(tester);

    final topBarBottom =
        tester.getBottomLeft(find.text('New flight')).dy +
        8; // EntryTopBar's own bottom padding
    final aircraftLabelTop = tester.getTopLeft(find.text('AIRCRAFT')).dy;

    // EntrySection's own top padding (22px) is the only gap that should
    // separate the two — not another ~30px status-bar inset on top of it.
    expect(aircraftLabelTop - topBarBottom, lessThan(40));
  });

  Future<void> setTime(WidgetTester tester, String hour, String minute) async {
    await tester.tap(find.text('--:--').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Switch to text input mode'));
    await tester.pumpAndSettle();
    final fields = find.descendant(
      of: find.byType(Dialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), hour);
    await tester.enterText(fields.at(1), minute);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'the derivation strip produces a real EASA/FAA breakdown from crew and '
    'block times alone (regression: previously required a resolved '
    'aircraft even for the "Just me" path, which never reads one)',
    (tester) async {
      await pumpScreen(tester);

      // No registration entered — deliberately left unresolved.
      await setTime(tester, '09', '15'); // off blocks
      await setTime(tester, '11', '30'); // on blocks
      await tester.tap(find.text('Just me'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('jurisdiction breakdown appears once crew is'),
        findsNothing,
      );
      expect(find.textContaining('EASA:'), findsOneWidget);
      expect(find.textContaining('FAA:'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('toggling "IFR flight plan filed" changes the derivation strip '
      '(regression: easa_instrument_time.dart\'s \'ifr\' quantity was '
      'computed correctly but never included in the footer\'s label maps, '
      'so the toggle appeared to do nothing)', (tester) async {
    await pumpScreen(tester);

    await setTime(tester, '09', '15'); // off blocks
    await setTime(tester, '11', '30'); // on blocks
    await tester.tap(find.text('Just me'));
    await tester.pumpAndSettle();

    // Expand the breakdown so the new "IFR" row, if any, is visible.
    await tester.tap(find.text('THIS ENTRY PRODUCES').first);
    await tester.pumpAndSettle();
    expect(find.text('IFR'), findsNothing);

    await tester.tap(
      find.descendant(
        of: find.widgetWithText(Row, 'IFR flight plan filed'),
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('IFR'), findsOneWidget);
    expect(find.text('2:15'), findsWidgets); // block time, credited in full
    expect(tester.takeException(), isNull);
  });

  testWidgets('the "BLOCK" shortcut fills a Conditions duration field with the '
      'current block time in one tap', (tester) async {
    await pumpScreen(tester);

    await setTime(tester, '09', '15'); // off blocks
    await setTime(tester, '11', '30'); // on blocks -> 2:15 block

    // "Night time" is the first duration field with the shortcut; find
    // its TextFields directly rather than by type name, since
    // ConditionsSection doesn't export one field's fields separately.
    final nightHours = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == '0',
    );
    final nightMinutes = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == '00',
    );
    expect(tester.widget<TextField>(nightHours.first).controller!.text, '');

    // Scoped to ConditionsSection — TimesSection has its own, unrelated
    // static "BLOCK" caption above the block-time field.
    final blockShortcut = find.descendant(
      of: find.byType(ConditionsSection),
      matching: find.text('BLOCK'),
    );
    await tester.tap(blockShortcut.first);
    await tester.pump();

    expect(tester.widget<TextField>(nightHours.first).controller!.text, '2');
    expect(tester.widget<TextField>(nightMinutes.first).controller!.text, '15');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the "BLOCK" shortcut is hidden until block time is known', (
    tester,
  ) async {
    await pumpScreen(tester);

    // Off/on blocks are left unset — no block time to fill from yet.
    // (TimesSection's own unrelated "BLOCK" caption is unaffected and
    // stays visible regardless.)
    expect(
      find.descendant(
        of: find.byType(ConditionsSection),
        matching: find.text('BLOCK'),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the aircraft picker search narrows the fleet list by registration or '
    'type, and picking a match still resolves it',
    (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('Change aircraft'));
      await tester.pump();
      expect(find.text('G-ARRW'), findsOneWidget);
      expect(find.text('G-HELI'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Search registration or type'),
        'cessna',
      );
      await tester.pump();
      expect(find.text('G-ABCD'), findsOneWidget);
      expect(find.text('G-ARRW'), findsNothing);
      expect(find.text('G-HELI'), findsNothing);

      await tester.tap(find.text('G-ABCD'));
      await tester.pump();
      expect(find.textContaining('Cessna 152'), findsOneWidget);

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a two-digit-hour block time is not clipped by the BLOCK field '
      '(regression: a 74px-wide box cut "15:19" down to "15:1")', (
    tester,
  ) async {
    await pumpScreen(tester);

    await setTime(tester, '21', '56'); // off blocks
    await setTime(tester, '13', '15'); // on blocks — crosses midnight

    final blockField = tester.widget<TextField>(
      find.descendant(
        of: find.byType(TimesSection),
        matching: find.byType(TextField),
      ),
    );
    expect(blockField.controller!.text, '15:19');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the aircraft picker search reports no matches rather than an empty '
    'silent list',
    (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('Change aircraft'));
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'Search registration or type'),
        'zzz-no-such-aircraft',
      );
      await tester.pump();

      expect(find.textContaining('No aircraft match'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'typing a full 4-character ICAO code in a route leg advances focus to '
    'the next leg',
    (tester) async {
      await pumpScreen(tester);

      // The route row holds exactly two ICAO fields to start with
      // (departure, destination).
      final icaoFields = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'ICAO',
      );
      expect(icaoFields, findsNWidgets(2));

      await tester.tap(icaoFields.first);
      await tester.pump();
      await tester.enterText(icaoFields.first, 'EGKA');
      await tester.pump();

      final secondField = tester.widget<TextField>(icaoFields.last);
      expect(secondField.focusNode!.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('off/on blocks are entered and displayed as Zulu, not local', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(find.text('ALL TIMES ZULU'), findsOneWidget);

    await setTime(tester, '21', '56');
    expect(find.text('21:56Z'), findsOneWidget);
    // No separate "local echo" is shown — that computation was
    // deliberately deferred rather than half-wired (see
    // times_section.dart's dartdoc).
    expect(find.text('21:56'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the expanded derivation strip groups EASA and FAA separately and '
    'drops the redundant inline summary',
    (tester) async {
      await pumpScreen(tester);

      await setTime(tester, '09', '15');
      await setTime(tester, '11', '30');
      await tester.tap(find.text('Just me'));
      await tester.pumpAndSettle();

      // Collapsed: the inline summary is present.
      expect(find.textContaining('EASA:'), findsOneWidget);

      await tester.tap(find.text('THIS ENTRY PRODUCES').first);
      await tester.pumpAndSettle();

      // Expanded: the inline "EASA: ..." summary is gone (superseded by
      // the grouped breakdown below), but the group headers are present.
      expect(find.textContaining('EASA:'), findsNothing);
      expect(find.text('EASA'), findsOneWidget);
      expect(find.text('FAA'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
