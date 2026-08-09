import 'calendar_date.dart';
import 'flight.dart';

/// #29: which calendar date a flight belongs to in the logbook — the answer
/// to "a flight departing 23:40 UTC and arriving 01:10 UTC belongs to which
/// date?" See `docs/adr/0009-date-boundary-policy.md`: the date of
/// departure, in UTC — never the date of arrival, and never a local date,
/// since none is stored (rule 3).
///
/// The single place this truncation happens. List ordering, PDF pagination
/// and currency-window bucketing (none of which exist yet as of M1) must
/// all call this rather than reading [Flight.offBlocks] and truncating it
/// themselves, so the policy can never quietly diverge between them.
extension FlightLogbookDate on Flight {
  CalendarDate get logbookDate => CalendarDate.fromUtcInstant(offBlocks);
}
