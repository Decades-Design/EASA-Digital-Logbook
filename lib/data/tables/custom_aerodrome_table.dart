import 'package:drift/drift.dart';

/// Pilot-defined aerodromes (private strips, unlicensed fields) — the
/// bundled ~85,000-row OurAirports dataset stays a runtime-loaded asset and
/// is never written here. Plain reference data, no lifecycle.
@DataClassName('CustomAerodromeRow')
class CustomAerodromesTable extends Table {
  @override
  String get tableName => 'custom_aerodromes';

  TextColumn get id => text()();
  TextColumn get icaoCode => text().nullable()();
  TextColumn get iataCode => text().nullable()();
  TextColumn get name => text()();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  IntColumn get elevationFt => integer().nullable()();
  TextColumn get isoCountry => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
