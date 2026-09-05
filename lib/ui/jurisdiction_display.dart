/// Display metadata for a jurisdiction id — shared by every screen that
/// shows a jurisdiction-dependent figure (CLAUDE.md rule 5), so the label
/// and row lists stay in exactly one place rather than drifting between
/// Totals/Currency/a flight's detail view.
const jurisdictionLabels = {
  'eu.easa.part-fcl': 'EASA Part-FCL',
  'us.faa.part61': 'FAA Part 61',
};

/// Function-tab rows, per jurisdiction — EASA and FAA pilot function time
/// are genuinely different regulatory concepts (`pic`/`picus`/`spic`/
/// `copilot`/`dual`/`instructor` vs `actingPic`/`loggedPic`/`dualReceived`/
/// `sic`), not aliases of each other. `easaPilotFunctionTime`/
/// `faaPilotFunctionTime` (`lib/domain/primitives/`) are each other's only
/// source of truth for their own key names.
///
/// FAA's own `solo` quantity is deliberately excluded — it's the same raw
/// fact (`PilotCapacity.soleOccupant`) `totals_summary.soloTime()` already
/// renders under "Other arrangements" for every jurisdiction; repeating it
/// here would double it up, not add information.
const functionRowsByJurisdiction = {
  'eu.easa.part-fcl': [
    ('pic', 'PIC'),
    ('picus', 'PICUS'),
    ('spic', 'SPIC'),
    ('copilot', 'Co-pilot'),
    ('dual', 'Dual'),
    ('instructor', 'Instructor'),
  ],
  'us.faa.part61': [
    ('actingPic', 'Acting PIC'),
    ('loggedPic', 'Logged PIC'),
    ('dualReceived', 'Dual received'),
    ('sic', 'SIC'),
  ],
};

/// Conditions-tab rows, per jurisdiction — EASA logs IFR as one column
/// (`easa_instrument_time.dart`'s `ifr`); FAA has no such concept at all and
/// splits actual/simulated instrument time instead
/// (`faa_instrument_time.dart`). `crossCountry` and night both exist under
/// both jurisdictions, but night's own key name still differs
/// (`night` vs `nightFlightTime`).
const conditionRowsByJurisdiction = {
  'eu.easa.part-fcl': [
    ('night', 'Night'),
    ('ifr', 'IFR'),
    ('crossCountry', 'Cross-country'),
  ],
  'us.faa.part61': [
    ('nightFlightTime', 'Night'),
    ('actualInstrument', 'Actual instrument'),
    ('simulatedInstrument', 'Simulated instrument'),
    ('crossCountry', 'Cross-country'),
  ],
};
