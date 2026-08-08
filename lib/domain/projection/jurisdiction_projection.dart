import '../jurisdiction/jurisdiction_registry.dart';
import '../model/aircraft.dart';
import '../model/flight.dart';
import '../model/flight_duration.dart';
import '../primitives/pilot_function_time.dart';
import 'derived_quantity.dart';
import 'projection.dart';
import 'projection_result.dart';

/// The one, jurisdiction-agnostic [Projection] implementation. An instance
/// is bound to one jurisdiction at construction — `JurisdictionProjection
/// (jurisdictionId: 'eu.easa.part-fcl', ...)` is "the EASA projection" (#18),
/// a second instance bound to `us.faa.part61` is "the FAA projection" (#19)
/// — but this class itself never names either one. It only resolves a
/// profile and dispatches to whatever primitive the profile names.
///
/// This is the acceptance test CLAUDE.md sets for the whole abstraction:
/// adding Transport Canada is a new YAML profile and at most one new
/// primitive, never a change in this file.
class JurisdictionProjection implements Projection {
  JurisdictionProjection({
    required this.registry,
    required this.primitives,
    required this.jurisdictionId,
  });

  final JurisdictionRegistry registry;
  final PrimitiveRegistry primitives;
  final String jurisdictionId;

  @override
  ProjectionResult project(Flight flight, Aircraft aircraft) {
    final profile = registry.resolve(jurisdictionId);
    final ruleId = profile['pic_rule'];
    if (ruleId == null) {
      // No pilot-function-time rule configured for this jurisdiction yet —
      // an empty result, not an error. #20-26 will add night/cross-country/
      // instrument rule keys the same way; a profile with none of them set
      // yet is incomplete, not broken.
      return ProjectionResult(
        jurisdictionId: jurisdictionId,
        quantities: const {},
      );
    }

    final rule = primitives.pilotFunctionTime(ruleId);
    final blockTime = FlightDuration(
      flight.onBlocks.difference(flight.offBlocks).inMinutes,
    );
    return ProjectionResult(
      jurisdictionId: jurisdictionId,
      quantities: rule(flight, blockTime),
    );
  }

  @override
  ProjectionResult projectAggregate(Iterable<(Flight, Aircraft)> flights) {
    final perFlight = [
      for (final (flight, aircraft) in flights) project(flight, aircraft),
    ];

    final names = <String>{
      for (final result in perFlight) ...result.quantities.keys,
    };

    final aggregated = <String, DerivedQuantity>{};
    for (final name in names) {
      aggregated[name] = _aggregateQuantity(name, perFlight);
    }

    return ProjectionResult(
      jurisdictionId: jurisdictionId,
      quantities: aggregated,
    );
  }

  /// Sums the creditable contributions to [name] across [perFlight] into one
  /// reliable total. Non-creditable contributions (an unsigned PICUS, say)
  /// are named and counted in the explanation rather than folded into
  /// [DerivedQuantity.value] — see [Projection.projectAggregate].
  DerivedQuantity _aggregateQuantity(
    String name,
    List<ProjectionResult> perFlight,
  ) {
    var creditableTotal = FlightDuration.zero;
    var excludedTotal = FlightDuration.zero;
    var flightCount = 0;
    var excludedCount = 0;

    for (final result in perFlight) {
      final quantity = result[name];
      if (quantity == null) {
        continue;
      }
      flightCount++;
      if (quantity.creditable) {
        creditableTotal = creditableTotal + quantity.value;
      } else {
        excludedTotal = excludedTotal + quantity.value;
        excludedCount++;
      }
    }

    final explanation = excludedCount == 0
        ? '${creditableTotal.toHoursMinutes()} across $flightCount flight(s)'
        : '${creditableTotal.toHoursMinutes()} across $flightCount flight(s); '
              '${excludedTotal.toHoursMinutes()} from $excludedCount flight(s) '
              'excluded — not creditable';

    return DerivedQuantity.creditable(creditableTotal, explanation);
  }
}
