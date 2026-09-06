import 'package:drift/native.dart';
import 'package:easa_digital_log/data/database.dart';
import 'package:easa_digital_log/data/repositories/export_record_repository_drift.dart';
import 'package:easa_digital_log/domain/model/calendar_date.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late DriftExportRecordRepository exports;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    exports = DriftExportRecordRepository(db);
  });

  tearDown(() => db.close());

  test('findOverlapping is empty before anything has been recorded', () async {
    final overlapping = await exports.findOverlapping(
      format: 'ForeFlight',
      from: const CalendarDate(2026, 1, 1),
      to: const CalendarDate(2026, 6, 30),
    );

    expect(overlapping, isEmpty);
  });

  test('a range fully inside a previously recorded one overlaps', () async {
    await exports.recordExport(
      format: 'ForeFlight',
      from: const CalendarDate(2026, 1, 1),
      to: const CalendarDate(2026, 12, 31),
    );

    final overlapping = await exports.findOverlapping(
      format: 'ForeFlight',
      from: const CalendarDate(2026, 6, 1),
      to: const CalendarDate(2026, 6, 30),
    );

    expect(overlapping, hasLength(1));
    expect(overlapping.single.from, const CalendarDate(2026, 1, 1));
    expect(overlapping.single.to, const CalendarDate(2026, 12, 31));
  });

  test('ranges that merely touch at a shared boundary day overlap', () async {
    await exports.recordExport(
      format: 'ForeFlight',
      from: const CalendarDate(2026, 1, 1),
      to: const CalendarDate(2026, 6, 30),
    );

    final overlapping = await exports.findOverlapping(
      format: 'ForeFlight',
      from: const CalendarDate(2026, 6, 30),
      to: const CalendarDate(2026, 12, 31),
    );

    expect(overlapping, hasLength(1));
  });

  test('a range entirely before a recorded one does not overlap', () async {
    await exports.recordExport(
      format: 'ForeFlight',
      from: const CalendarDate(2026, 6, 1),
      to: const CalendarDate(2026, 12, 31),
    );

    final overlapping = await exports.findOverlapping(
      format: 'ForeFlight',
      from: const CalendarDate(2026, 1, 1),
      to: const CalendarDate(2026, 5, 31),
    );

    expect(overlapping, isEmpty);
  });

  test('a different format never overlaps, even for the same dates', () async {
    await exports.recordExport(
      format: 'ForeFlight',
      from: const CalendarDate(2026, 1, 1),
      to: const CalendarDate(2026, 12, 31),
    );

    final overlapping = await exports.findOverlapping(
      format: 'Garmin',
      from: const CalendarDate(2026, 6, 1),
      to: const CalendarDate(2026, 6, 30),
    );

    expect(overlapping, isEmpty);
  });

  test(
    'every matching overlap is returned, not just the closest one',
    () async {
      await exports.recordExport(
        format: 'ForeFlight',
        from: const CalendarDate(2026, 1, 1),
        to: const CalendarDate(2026, 3, 31),
      );
      await exports.recordExport(
        format: 'ForeFlight',
        from: const CalendarDate(2026, 4, 1),
        to: const CalendarDate(2026, 6, 30),
      );

      final overlapping = await exports.findOverlapping(
        format: 'ForeFlight',
        from: const CalendarDate(2026, 1, 1),
        to: const CalendarDate(2026, 12, 31),
      );

      expect(
        overlapping.map((r) => r.from),
        containsAll(<CalendarDate>[
          const CalendarDate(2026, 1, 1),
          const CalendarDate(2026, 4, 1),
        ]),
      );
    },
  );
}
