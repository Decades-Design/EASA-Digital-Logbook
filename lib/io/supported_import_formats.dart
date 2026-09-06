/// A short, human-readable summary of which vendor formats import supports
/// — the one place outside an adapter's own file that names a vendor by
/// name is allowed to live, so a screen that just wants to *say* what's
/// supported (Settings' Import row) doesn't have to spell out "ForeFlight
/// or Garmin" itself (#68: "never let a vendor's field naming past `io/`").
///
/// Update this alongside `ImportAdapter.displayName` as adapters are added
/// — there is no registry yet listing them for this to read live.
const String supportedImportFormatsLabel =
    'ForeFlight, Garmin Pilot, or a generic CSV';
