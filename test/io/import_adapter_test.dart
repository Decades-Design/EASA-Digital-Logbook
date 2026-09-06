import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:easa_digital_log/io/canonical_import_row.dart';
import 'package:easa_digital_log/io/import_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

const _capacity = PilotCapacity(
  commandAuthority: true,
  soleManipulator: true,
  soleOccupant: true,
  multiPilotOperation: false,
  additionalCrewRequiredByRule: false,
  actingAsInstructor: false,
  actingAsExaminer: false,
  picusClaimed: false,
  picInterventionNotRequired: false,
);

/// A minimal, in-memory adapter over a trivial `registration,route,remarks`
/// CSV — not a real vendor format (that's #69/#71/#72's job), just enough
/// to prove [ImportAdapter] is actually usable end to end: parse to
/// canonical rows, report a per-row error without touching the rows
/// already parsed, and never reach for a database.
class _TestFixtureAdapter implements ImportAdapter {
  static const sourceKey = 'source';

  @override
  String get displayName => 'Test fixture';

  @override
  ImportParseResult parse(Map<String, String> sources) {
    final source = sources[sourceKey]!;
    final rows = <CanonicalImportRow>[];
    final errors = <ImportRowError>[];
    final lines = source.split('\n').where((l) => l.trim().isNotEmpty).toList();

    for (var i = 0; i < lines.length; i++) {
      final rowNumber = i + 1;
      final fields = lines[i].split(',');
      if (fields.length < 2) {
        errors.add(
          ImportRowError(
            rowNumber: rowNumber,
            message: 'expected at least 2 columns, found ${fields.length}',
          ),
        );
        continue;
      }

      final registration = fields[0];
      final route = fields[1].split('-');
      final off = UtcInstant.utc(2026, 1, 1, 9);

      rows.add(
        CanonicalImportRow(
          sourceRowNumber: rowNumber,
          aircraft: Aircraft(
            registration: registration,
            manufacturer: 'Unknown',
            model: 'Unknown',
            category: AircraftCategory.aeroplane,
            engineType: EngineType.piston,
            engineCount: 1,
            operatingSurface: OperatingSurface.land,
            requiresMultiCrew: false,
          ),
          flight: Flight(
            aircraftRegistration: registration,
            route: route,
            prePlannedNavigation: false,
            offBlocks: off,
            onBlocks: off.add(const Duration(hours: 1)),
            capacity: _capacity,
            carryingPassengers: false,
            takeoffs: const CircuitCounts(dayFullStop: 1),
            landings: const CircuitCounts(dayFullStop: 1),
            ifrFlightPlanFiled: false,
            actualInstrumentTime: FlightDuration.zero,
            simulatedInstrumentTime: FlightDuration.zero,
            approaches: const [],
            holdingProceduresCount: 0,
            trackingPerformed: false,
            remarks: '',
          ),
          unmappedFields: fields.length > 2 ? {'extra': fields[2]} : const {},
        ),
      );
    }

    return ImportParseResult(rows: rows, errors: errors);
  }
}

void main() {
  test('a working adapter maps every clean row to a canonical row', () {
    final result = _TestFixtureAdapter().parse({
      _TestFixtureAdapter.sourceKey: 'N12345,KABC-KDEF\nN67890,KGHI-KGHI',
    });

    expect(result.rows, hasLength(2));
    expect(result.errors, isEmpty);
    expect(result.hasErrors, isFalse);
    expect(result.rows[0].flight.route, ['KABC', 'KDEF']);
    expect(result.rows[0].aircraft.registration, 'N12345');
  });

  test(
    'a malformed row becomes an error, and does not block the rows around it',
    () {
      final result = _TestFixtureAdapter().parse({
        _TestFixtureAdapter.sourceKey:
            'N12345,KABC-KDEF\nmalformed\nN67890,KGHI-KGHI',
      });

      expect(result.rows, hasLength(2));
      expect(result.hasErrors, isTrue);
      expect(result.errors.single.rowNumber, 2);
      expect(result.errors.single.message, contains('2 columns'));
      // Row numbers stay 1-based against the source file, not against the
      // successfully-parsed subset — row 3 in the file, not row 2 of rows.
      expect(result.rows[1].sourceRowNumber, 3);
    },
  );

  test('unmapped vendor fields survive onto the canonical row, not lost', () {
    final result = _TestFixtureAdapter().parse({
      _TestFixtureAdapter.sourceKey: 'N12345,KABC-KDEF,some vendor note',
    });

    expect(result.rows.single.unmappedFields, {'extra': 'some vendor note'});
    expect(
      mergeUnmappedFieldsIntoRemarks(
        result.rows.single.flight.remarks,
        result.rows.single.unmappedFields,
      ),
      'extra: some vendor note',
    );
  });
}
