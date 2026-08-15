/// Placeholder data for the Logbook screen's visual pass (#57). Real data
/// comes from [FlightReadRepository] once that wiring lands (#56) — this
/// file exists so the screen's layout can be built and judged on
/// real-looking numbers before that plumbing exists. Values match the "1b —
/// Ledger" mock in the Flight Logbook - App Design doc (Claude Design
/// project 513e7fc3-e41a-40ea-b3a5-f16f086d15f8) so the built screen can be
/// compared pixel-for-pixel against it. Delete this file when the screen
/// reads from the repository instead.
library;

const sampleFlightCount = 412;
const sampleTotalTime = Duration(hours: 386, minutes: 20);

/// Tallies behind the "N flights need attention" banner. Not derived from
/// [sampleLogbookMonths] — the visible seven flights are a small window,
/// the banner counts the whole logbook.
const sampleDraftCount = 2;
const sampleAwaitingSignatureCount = 1;
const sampleNeedsInformationCount = 1;

/// A small flag/tag drawn on a flight row — never a bare colour, always a
/// labelled chip, per CLAUDE.md rule 5 (never render a jurisdiction-
/// dependent fact without saying what it is).
enum FlightRowBadge {
  /// Not yet exported/certified — freely editable (CLAUDE.md rule 4).
  draft,

  /// Committed (exported) but missing the signatory's countersignature.
  unsigned,

  /// This flight's derived values differ across the pilot's held licences
  /// — opens the side-by-side comparison (CLAUDE.md's multi-jurisdiction
  /// UX rule).
  mismatch,

  /// Any portion of the flight was flown at night under the primary
  /// jurisdiction's definition.
  night,

  /// An IFR flight plan was filed for this flight (distinct from actual or
  /// simulated instrument conditions — CLAUDE.md rule 2).
  ifr,
}

/// What the trailing time column shows in place of a plain "BLOCK" label.
enum FlightTimeState {
  /// The ordinary case: total time as flown, labelled BLOCK.
  block,

  /// A rule primitive's output was manually overridden for this flight —
  /// flagged rather than silently substituted.
  overridden,

  /// A PICUS sector awaiting the countersignature that makes it creditable
  /// — the figure is shown, but visually muted, since it doesn't count yet.
  notYetCreditable,
}

class SampleFlightRow {
  const SampleFlightRow({
    required this.day,
    required this.monthAbbrev,
    required this.route,
    required this.registration,
    required this.crewRole,
    this.crewNote,
    required this.totalTime,
    this.badges = const {},
    this.timeState = FlightTimeState.block,
  });

  final int day;
  final String monthAbbrev;
  final List<String> route;
  final String registration;

  /// Command-authority role for this flight under the primary jurisdiction
  /// — PIC, Dual, PICUS, etc. Distinct from sole-manipulator status
  /// (CLAUDE.md rule 2: command authority is a separate raw fact).
  final String crewRole;

  /// Free-text context after the crew role — pax count, instructor name,
  /// the reason a mismatch badge is showing, or why the flight needs
  /// attention.
  final String? crewNote;

  /// Off blocks to on blocks — the one figure that means the same thing
  /// under every jurisdiction (docs/entry-form.md §2).
  final Duration totalTime;

  final Set<FlightRowBadge> badges;
  final FlightTimeState timeState;
}

class SampleLogbookMonth {
  const SampleLogbookMonth({
    required this.label,
    required this.flights,
    required this.runningCount,
    required this.runningTotal,
  });

  final String label;
  final List<SampleFlightRow> flights;

  /// Flights so far this month, and running total-to-date through the end
  /// of it — the "brought forward / this page / total to date" figures the
  /// printable export must reconcile (CLAUDE.md), shown live here too.
  /// Sample-only: not derivable from [flights], since that's a handful of
  /// rows out of 412.
  final int runningCount;
  final Duration runningTotal;
}

/// Seven flights across two months — the exact set from the 1b mock, so the
/// built screen can be checked against it directly. The 02 Aug and 28 Jul
/// rows are the two the mock singles out in its caption: a PICUS sector
/// awaiting signature (not yet creditable) and a night/IFR flight with an
/// overridden derived value.
final sampleLogbookMonths = [
  SampleLogbookMonth(
    label: 'AUGUST 2026',
    runningCount: 5,
    runningTotal: const Duration(hours: 14, minutes: 5),
    flights: [
      SampleFlightRow(
        day: 8,
        monthAbbrev: 'AUG',
        route: ['EGKA', 'EGBJ', 'EGKA'],
        registration: 'G-ARRW',
        crewRole: 'PIC',
        crewNote: 'no landings entered',
        totalTime: const Duration(hours: 2, minutes: 15),
        badges: const {FlightRowBadge.draft},
      ),
      SampleFlightRow(
        day: 6,
        monthAbbrev: 'AUG',
        route: ['EGKA', 'EGHH'],
        registration: 'N456BD',
        crewRole: 'PIC',
        crewNote: 'logged Dual under EASA',
        totalTime: const Duration(hours: 1, minutes: 5),
        badges: const {FlightRowBadge.mismatch},
      ),
      SampleFlightRow(
        day: 4,
        monthAbbrev: 'AUG',
        route: ['EGKA', 'EGKA'],
        registration: 'G-ABCD',
        crewRole: 'Dual',
        crewNote: 'J. Reilly',
        totalTime: const Duration(minutes: 50),
      ),
      SampleFlightRow(
        day: 2,
        monthAbbrev: 'AUG',
        route: ['EGKA', 'LFAT'],
        registration: 'G-MULTI',
        crewRole: 'PICUS',
        crewNote: 'M. Okafor',
        totalTime: const Duration(hours: 1, minutes: 40),
        badges: const {FlightRowBadge.unsigned},
        timeState: FlightTimeState.notYetCreditable,
      ),
    ],
  ),
  SampleLogbookMonth(
    label: 'JULY 2026',
    runningCount: 9,
    runningTotal: const Duration(hours: 21, minutes: 35),
    flights: [
      SampleFlightRow(
        day: 28,
        monthAbbrev: 'JUL',
        route: ['EGKA', 'EGTB'],
        registration: 'G-ARRW',
        crewRole: 'PIC',
        crewNote: 'night IR currency',
        totalTime: const Duration(hours: 1, minutes: 20),
        badges: const {FlightRowBadge.night, FlightRowBadge.ifr},
        timeState: FlightTimeState.overridden,
      ),
      SampleFlightRow(
        day: 24,
        monthAbbrev: 'JUL',
        route: ['EGKA', 'EGLF', 'EGKA'],
        registration: 'G-ABCD',
        crewRole: 'PIC',
        crewNote: 'nav exercise',
        totalTime: const Duration(hours: 1, minutes: 35),
      ),
      SampleFlightRow(
        day: 19,
        monthAbbrev: 'JUL',
        route: ['EGKA', 'EGKB'],
        registration: 'G-ARRW',
        crewRole: 'PIC',
        totalTime: const Duration(minutes: 45),
      ),
    ],
  ),
];
