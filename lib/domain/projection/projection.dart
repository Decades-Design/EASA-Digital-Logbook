import '../model/aircraft.dart';
import '../model/flight.dart';
import 'projection_result.dart';

/// Applies one jurisdiction's rules to a [Flight], or to a set of them, to
/// produce derived quantities. The abstraction CLAUDE.md's architecture
/// section describes as `domain/projection/`: it keeps jurisdiction-specific
/// interpretation out of [Flight] itself (ADR-0001) and out of the UI.
///
/// **No caching or memoisation.** #17's acceptance criteria are explicit:
/// correctness first, measure before optimising. A stale cached result that
/// silently outlives an edited flight or an updated jurisdiction profile is
/// a worse failure than recomputing every time.
///
/// [Aircraft] is part of the signature even though the pilot-function-time
/// rules in this PR (#18, #19) don't read it — later primitives (night,
/// cross-country, instrument) do, and #17 fixes the interface shape once
/// rather than growing it per-primitive.
abstract class Projection {
  /// Derived quantities for one [flight], flown in [aircraft].
  ProjectionResult project(Flight flight, Aircraft aircraft);

  /// Derived quantities aggregated over [flights] — e.g. a logbook total or
  /// a currency window, not a per-flight figure.
  ///
  /// Aggregation is not simple addition: a [DerivedQuantity] with
  /// `creditable: false` (an unsigned PICUS, say) must not silently
  /// contribute to a total the pilot could rely on, and must not silently
  /// vanish from it either — see [JurisdictionProjection.projectAggregate]
  /// for how the two needs are kept apart.
  ProjectionResult projectAggregate(Iterable<(Flight, Aircraft)> flights);
}
