import 'package:freezed_annotation/freezed_annotation.dart';

import 'derived_quantity.dart';

part 'projection_result.freezed.dart';

/// The named [DerivedQuantity] set a [Projection] produced for one
/// jurisdiction, for one flight or one aggregate over a flight set.
///
/// A `Map<String, DerivedQuantity>` rather than fixed fields, because the
/// vocabulary genuinely differs by jurisdiction — EASA's `pic`/`dual`/
/// `spic`/`picus`/`copilot`/`instructor` is not FAA's `logged_pic`/
/// `acting_pic`/`dual_received`/`sic`/`solo`, and #17's acceptance test
/// (CLAUDE.md: "adding Transport Canada should require a YAML profile and
/// at most one new primitive") fails if the result type has to grow a field
/// every time a jurisdiction adds a quantity. This still satisfies #17's
/// "not a `Map<String, dynamic>`" requirement: every value is a real
/// [DerivedQuantity], never a raw number or a bag of untyped data.
@freezed
abstract class ProjectionResult with _$ProjectionResult {
  const ProjectionResult._();

  const factory ProjectionResult({
    /// The jurisdiction profile id this result was computed under, e.g.
    /// `eu.easa.part-fcl`. Rule 5: an unlabelled derived number is a bug,
    /// and carrying the jurisdiction on the result itself — not just on
    /// whoever called [Projection.project] — means it survives being passed
    /// around or displayed away from the call site.
    required String jurisdictionId,
    required Map<String, DerivedQuantity> quantities,
  }) = _ProjectionResult;

  /// Looks up a named quantity, e.g. `result['pic']`. `null` if this
  /// jurisdiction's rules never populated that name — never a missing-key
  /// exception, since which names exist is itself jurisdiction-specific.
  DerivedQuantity? operator [](String name) => quantities[name];
}
