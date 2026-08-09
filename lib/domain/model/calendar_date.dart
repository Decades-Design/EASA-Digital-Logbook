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

  /// Parses a zero-padded `YYYY-MM-DD` string — the exact form [toString]
  /// produces. Throws [FormatException] naming [source] if malformed.
  factory CalendarDate.parse(String source) {
    final match = _pattern.firstMatch(source);
    if (match == null) {
      throw FormatException('Not a valid YYYY-MM-DD calendar date', source);
    }
    return CalendarDate(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  static final RegExp _pattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  /// This date shifted by [days] days; negative moves backward.
  ///
  /// Pure integer calendar arithmetic (Fliegel & van Flandern's Julian day
  /// number algorithm) rather than `DateTime`, which `lib/domain/` may not
  /// name at all — rule 3, `tool/check_domain_types.dart`.
  CalendarDate addDays(int days) {
    final jdn = _toJulianDayNumber(year, month, day) + days;
    return _fromJulianDayNumber(jdn);
  }

  static int _toJulianDayNumber(int y, int m, int d) {
    final a = (14 - m) ~/ 12;
    final y2 = y + 4800 - a;
    final m2 = m + 12 * a - 3;
    return d +
        (153 * m2 + 2) ~/ 5 +
        365 * y2 +
        y2 ~/ 4 -
        y2 ~/ 100 +
        y2 ~/ 400 -
        32045;
  }

  static CalendarDate _fromJulianDayNumber(int jdn) {
    final a = jdn + 32044;
    final b = (4 * a + 3) ~/ 146097;
    final c = a - (146097 * b) ~/ 4;
    final d = (4 * c + 3) ~/ 1461;
    final e = c - (1461 * d) ~/ 4;
    final m = (5 * e + 2) ~/ 153;
    final day = e - (153 * m + 2) ~/ 5 + 1;
    final month = m + 3 - 12 * (m ~/ 10);
    final year = 100 * b + d - 4800 + (m ~/ 10);
    return CalendarDate(year, month, day);
  }

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
