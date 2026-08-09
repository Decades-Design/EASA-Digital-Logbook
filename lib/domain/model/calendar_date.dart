import 'utc_instant.dart';

/// A calendar date with no time-of-day component — year, month, day only.
///
/// Exists because `lib/domain/` bans a raw `DateTime` (rule 3,
/// `tool/check_domain_types.dart`) and several facts genuinely are dates,
/// not instants: a flight's logbook date (#29 — see
/// `flight_logbook_date.dart` and `docs/adr/0009-date-boundary-policy.md`),
/// and, eventually, a licence or countersignature's credential expiry,
/// today provisionally typed as [UtcInstant] with a "a proper calendar-date
/// type is #29's territory" note on it.
class CalendarDate implements Comparable<CalendarDate> {
  const CalendarDate(this.year, this.month, this.day);

  /// [instant]'s calendar date **in UTC** — the only timezone `lib/domain/`
  /// ever reads a date against (rule 3, ADR-0002). Never a local date:
  /// nothing in this codebase stores one to read.
  factory CalendarDate.fromUtcInstant(UtcInstant instant) {
    final utc = instant.asUtcDateTime;
    return CalendarDate(utc.year, utc.month, utc.day);
  }

  final int year;
  final int month;
  final int day;

  @override
  int compareTo(CalendarDate other) {
    if (year != other.year) {
      return year.compareTo(other.year);
    }
    if (month != other.month) {
      return month.compareTo(other.month);
    }
    return day.compareTo(other.day);
  }

  bool operator <(CalendarDate other) => compareTo(other) < 0;

  bool operator <=(CalendarDate other) => compareTo(other) <= 0;

  bool operator >(CalendarDate other) => compareTo(other) > 0;

  bool operator >=(CalendarDate other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is CalendarDate &&
      year == other.year &&
      month == other.month &&
      day == other.day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';
}
