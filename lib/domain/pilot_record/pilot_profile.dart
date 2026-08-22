import 'package:freezed_annotation/freezed_annotation.dart';

import '../model/calendar_date.dart';

part 'pilot_profile.freezed.dart';

/// The logbook holder's own facts, needed by currency rules that turn on
/// age — EASA medical certificate validity banding (`MED.A.045`) chief
/// among them.
///
/// Singleton, not a list: CLAUDE.md scopes this app to one pilot's own
/// legal record, never multiple pilots, so there is exactly one
/// [PilotProfile] per installation. `PilotProfileRepository` enforces that
/// at the persistence layer rather than this model carrying an id nothing
/// would ever vary.
@freezed
abstract class PilotProfile with _$PilotProfile {
  const factory PilotProfile({
    required CalendarDate dateOfBirth,

    /// The `JurisdictionProfile.id` whose figures the logbook, currency and
    /// totals screens render — "let the user choose their primary
    /// jurisdiction" must be this explicit settings value, never inferred
    /// from which licence happens to come first (CLAUDE.md).
    required String primaryJurisdictionId,

    /// ICAO code of the aerodrome this pilot flies from most, used only for
    /// the Aerodromes screen's "furthest" figure. Nullable and unlike
    /// [primaryJurisdictionId] never defaulted on migration — a pilot who
    /// hasn't set one yet should see that figure omitted, not a guessed
    /// answer (CLAUDE.md: "never guess a missing discriminator").
    String? homeBaseIcao,
  }) = _PilotProfile;
}
