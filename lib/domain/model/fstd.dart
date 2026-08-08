import 'package:freezed_annotation/freezed_annotation.dart';

import 'aircraft.dart';

part 'fstd.freezed.dart';

/// A flight simulation training device.
///
/// **Deliberately not an [Aircraft].** `AMC1 FCL.050` column 11 gives an FSTD
/// session its own date column, separate from column 1, and keeps its total
/// outside total time of flight in column 6 — the printed sheet itself treats
/// a session as a different kind of entry rather than a flight in a different
/// machine. See `docs/amc1-fcl050-layout.md` and `docs/entry-form.md` §9.
///
/// Modelling it as an aircraft with an `isFstd` flag would make "never add
/// simulator time to flight totals" a rule every total, currency check and
/// export has to remember. Two types make it structural: nothing links an
/// [Fstd] to a flight, so the time cannot arrive there by accident. Issue #28
/// covers the session entry that refers to this.
@freezed
abstract class Fstd with _$Fstd {
  const factory Fstd({
    /// The device's approval or qualification reference from its certificate.
    ///
    /// Unbackfillable in the rule 2 sense: nobody reconstructs which specific
    /// box they sat in years afterwards, and creditability can turn on it.
    required String identifier,

    required FstdQualificationLevel qualificationLevel,

    /// Which aircraft type the device represents.
    ///
    /// Credit follows the represented type, not the device — an FFS
    /// representing an A320 gives A320 credit. Held as a designator rather
    /// than an [Aircraft] reference because the represented type need not be
    /// an aircraft the holder has ever flown.
    required String representedTypeDesignator,

    /// Who operates the device, and where. `§61.51(b)(1)(ii)` records the
    /// location of the lesson where a flight would carry departure and
    /// arrival.
    String? operator,
    String? location,
  }) = _Fstd;
}

/// FSTD qualification levels across both authorities.
///
/// CLAUDE.md rule 2 is explicit that the level is required, not just
/// "sim: yes" — creditability depends on it and it cannot be backfilled. EASA
/// and the FAA use different ladders, so both appear here rather than being
/// forced into a common denominator that would lose the distinctions each
/// authority's rules actually read.
enum FstdQualificationLevel {
  /// Full flight simulator, EASA and FAA levels A through D. Level D is the
  /// highest fidelity and carries the widest credit.
  fullFlightSimulatorLevelA,
  fullFlightSimulatorLevelB,
  fullFlightSimulatorLevelC,
  fullFlightSimulatorLevelD,

  /// Flight training device. EASA levels 1 to 3; FAA levels 4 to 7.
  flightTrainingDeviceLevel1,
  flightTrainingDeviceLevel2,
  flightTrainingDeviceLevel3,
  flightTrainingDeviceLevel4,
  flightTrainingDeviceLevel5,
  flightTrainingDeviceLevel6,
  flightTrainingDeviceLevel7,

  /// EASA flight and navigation procedures trainer.
  flightNavigationProceduresTrainerLevel1,
  flightNavigationProceduresTrainerLevel2,

  /// EASA basic instrument training device.
  basicInstrumentTrainingDevice,

  /// FAA aviation training devices. `§61.51(g)(4)` and `§61.57(c)` treat basic
  /// and advanced differently, so the two are not one value.
  basicAviationTrainingDevice,
  advancedAviationTrainingDevice,
}
