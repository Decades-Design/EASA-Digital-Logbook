import 'package:freezed_annotation/freezed_annotation.dart';

import '../model/flight_duration.dart';

part 'derived_quantity.freezed.dart';

/// One computed value a [Projection] produces, plus whether it can actually
/// be relied on and why it has the value it has.
///
/// **Never silently zero, never silently valid.** `PICUS` awaiting
/// countersignature (`test/fixtures/capacities/picus_pending.yaml`) has a
/// real, non-zero [value] — the pilot flew the time — but [creditable] is
/// `false` until the signature arrives. Collapsing that to `0` would lie
/// about what happened; collapsing it to a bare creditable value would lie
/// about whether it counts. Both are wrong in a way nobody would notice
/// until an export or a currency check relied on it.
///
/// [explanation] exists because a number with no reason attached is not
/// explainable — `docs/entry-form.md` §7's derivation strip requires every
/// number to be traceable to a named rule, and a bare `Map<String, dynamic>`
/// (which #17 explicitly rules out) could never carry this.
@freezed
abstract class DerivedQuantity with _$DerivedQuantity {
  const factory DerivedQuantity({
    required FlightDuration value,
    required bool creditable,
    required String explanation,
  }) = _DerivedQuantity;

  /// A quantity that counts in full, for [explanation].
  factory DerivedQuantity.creditable(
    FlightDuration value,
    String explanation,
  ) =>
      DerivedQuantity(value: value, creditable: true, explanation: explanation);

  /// A quantity with a real, non-zero [value] that does not yet — or does
  /// not ever — count, for [explanation]. See the class dartdoc: this is
  /// the case a `Map<String, dynamic>` result would be tempted to collapse
  /// to a bare `0`.
  factory DerivedQuantity.notCreditable(
    FlightDuration value,
    String explanation,
  ) => DerivedQuantity(
    value: value,
    creditable: false,
    explanation: explanation,
  );

  /// Nothing to claim under this rule, for [explanation].
  factory DerivedQuantity.zero(String explanation) => DerivedQuantity(
    value: FlightDuration.zero,
    creditable: true,
    explanation: explanation,
  );
}
