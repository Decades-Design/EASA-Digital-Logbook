import '../../domain/model/aircraft.dart' as domain;
import '../database.dart';

AircraftRow aircraftToRow(domain.Aircraft aircraft, {required String id}) {
  return AircraftRow(
    id: id,
    registration: aircraft.registration,
    manufacturer: aircraft.manufacturer,
    model: aircraft.model,
    icaoTypeDesignator: aircraft.icaoTypeDesignator,
    category: aircraft.category.name,
    engineType: aircraft.engineType.name,
    engineCount: aircraft.engineCount,
    operatingSurface: aircraft.operatingSurface.name,
    requiresMultiCrew: aircraft.requiresMultiCrew,
    typeRatingDesignator: aircraft.typeRatingDesignator,
  );
}

domain.Aircraft aircraftFromRow(
  AircraftRow row,
  Map<String, Set<domain.AircraftQualification>> requiredQualifications,
) {
  return domain.Aircraft(
    registration: row.registration,
    manufacturer: row.manufacturer,
    model: row.model,
    icaoTypeDesignator: row.icaoTypeDesignator,
    category: domain.AircraftCategory.values.byName(row.category),
    engineType: domain.EngineType.values.byName(row.engineType),
    engineCount: row.engineCount,
    operatingSurface: domain.OperatingSurface.values.byName(
      row.operatingSurface,
    ),
    requiresMultiCrew: row.requiresMultiCrew,
    typeRatingDesignator: row.typeRatingDesignator,
    requiredQualifications: requiredQualifications,
  );
}
