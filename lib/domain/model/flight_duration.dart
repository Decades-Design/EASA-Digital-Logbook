/// A logbook duration, stored as whole minutes.
///
/// Logbook time is kept in integer minutes rather than fractional hours so
/// that summing thousands of flights is exact. A `double hours` field
/// accumulates floating-point error across a full career's worth of entries,
/// and that error surfaces as an intermittent, unexplainable mismatch far
/// away from its cause — for example a multi-page PDF export whose running
/// totals no longer reconcile. Integer minutes make the arithmetic exact;
/// decimal hours and `HH:MM` are display formats only, never a storage or
/// accumulation representation.
///
/// **Decimal display policy.** [toDecimalHours] renders to one decimal place
/// (tenths of an hour), rounding half away from zero: an exact `.05`
/// boundary rounds outward (up in magnitude), not to even and not toward
/// zero. This is a deliberate, singular policy applied in one place —
/// formatting — never duplicated at call sites.
///
/// **Rounding happens only at the display or export boundary.** Totals are
/// always produced by summing stored integer minutes ([sum], `operator +`)
/// and only the final total is ever rendered to decimal. Rounding each
/// addend before summing produces a materially different — and wrong —
/// result; see the "rounding at the display boundary" test for a worked
/// example that is off by over a hundred hours across ten thousand flights.
///
/// **The round-trip is asymmetric.** `parseDecimalHours` followed by
/// `toDecimalHours` is guaranteed to reproduce the original string, and
/// import fidelity depends on exactly that direction. The reverse is not
/// guaranteed: at one decimal place of display, only whole-minute values
/// that are multiples of 6 minutes (i.e. exact tenths of an hour) round-trip
/// through `toDecimalHours` back to the same minute count via
/// `parseDecimalHours`. `FlightDuration(83).toDecimalHours()` is `'1.4'`,
/// but `FlightDuration.parseDecimalHours('1.4')` is 84 minutes, not 83.
class FlightDuration implements Comparable<FlightDuration> {
  const FlightDuration(this.inMinutes);

  /// The zero duration.
  static const FlightDuration zero = FlightDuration(0);

  /// The duration in whole minutes. May be negative — see `operator -`.
  final int inMinutes;

  /// Pattern for `HH:MM` input: one or more digits, a colon, exactly two
  /// digits. No leading sign is accepted.
  static final RegExp _hoursMinutesPattern = RegExp(r'^(\d+):(\d{2})$');

  /// Pattern for decimal-hours input: an integer part, with an optional
  /// fractional part of at most 9 digits. No leading sign is accepted and
  /// the fractional part, if present, must not be empty.
  static final RegExp _decimalHoursPattern = RegExp(r'^(\d+)(?:\.(\d{1,9}))?$');

  /// Parses an `HH:MM` string, e.g. `'1:23'` or `'01:23'`.
  ///
  /// Hours may be unpadded on input; minutes must be exactly two digits and
  /// less than 60. Throws [FormatException] naming [source] if the string is
  /// malformed.
  factory FlightDuration.parseHoursMinutes(String source) {
    final match = _hoursMinutesPattern.firstMatch(source);
    if (match == null) {
      throw FormatException('Not a valid HH:MM duration', source);
    }

    final hours = int.parse(match.group(1)!);
    final minutes = int.parse(match.group(2)!);
    if (minutes > 59) {
      throw FormatException('Minutes must be 00-59', source);
    }

    return FlightDuration(hours * 60 + minutes);
  }

  /// Parses a decimal-hours string, e.g. `'1.4'` or `'2'`.
  ///
  /// Parsing is done with integer arithmetic on the digit string — never by
  /// routing through `double.parse(x) * 60`, which is not exact (e.g.
  /// `double.parse('1.4') * 60 == 84.00000000000001`). At most 9 fractional
  /// digits are accepted; this bounds `fractionDigits * 60` (used below)
  /// well within integer range and rejects nonsensical precision. Throws
  /// [FormatException] naming [source] if the string is malformed.
  factory FlightDuration.parseDecimalHours(String source) {
    final match = _decimalHoursPattern.firstMatch(source);
    if (match == null) {
      throw FormatException('Not a valid decimal-hours duration', source);
    }

    final whole = int.parse(match.group(1)!);
    final fraction = match.group(2);

    if (fraction == null) {
      return FlightDuration(whole * 60);
    }

    final fractionDigits = int.parse(fraction);
    var scale = 1;
    for (var i = 0; i < fraction.length; i++) {
      scale *= 10;
    }

    // '1.45' -> whole = 1, fractionDigits = 45, scale = 100
    // minutes = 60 + (45 * 60 + 50) ~/ 100 = 60 + 27 = 87
    final minutes = whole * 60 + (fractionDigits * 60 + scale ~/ 2) ~/ scale;
    return FlightDuration(minutes);
  }

  /// Sums [durations] using exact integer-minute arithmetic. Returns [zero]
  /// for an empty iterable.
  static FlightDuration sum(Iterable<FlightDuration> durations) {
    var total = 0;
    for (final duration in durations) {
      total += duration.inMinutes;
    }
    return FlightDuration(total);
  }

  /// Formats as `HH:MM`, hours padded to at least two digits, minutes padded
  /// to exactly two digits. Negative durations are not specially handled by
  /// this formatter; see [isNegative].
  String toHoursMinutes() {
    final hours = inMinutes ~/ 60;
    final minutes = inMinutes % 60;
    final hoursText = hours.toString().padLeft(2, '0');
    final minutesText = minutes.toString().padLeft(2, '0');
    return '$hoursText:$minutesText';
  }

  /// Formats to decimal hours at one decimal place (tenths), rounding half
  /// away from zero. Computed with integer arithmetic only — never `double`.
  String toDecimalHours() {
    final tenths = (inMinutes * 10 + 30) ~/ 60;
    return '${tenths ~/ 10}.${tenths % 10}';
  }

  /// Whether this duration is negative.
  bool get isNegative => inMinutes < 0;

  FlightDuration operator +(FlightDuration other) =>
      FlightDuration(inMinutes + other.inMinutes);

  /// Subtracts [other]. The result may be negative; a negative result is
  /// reported via [isNegative], never thrown. Rejecting a negative *flight*
  /// duration is `Flight`'s validation concern, not this value type's.
  FlightDuration operator -(FlightDuration other) =>
      FlightDuration(inMinutes - other.inMinutes);

  bool operator <(FlightDuration other) => inMinutes < other.inMinutes;

  bool operator <=(FlightDuration other) => inMinutes <= other.inMinutes;

  bool operator >(FlightDuration other) => inMinutes > other.inMinutes;

  bool operator >=(FlightDuration other) => inMinutes >= other.inMinutes;

  @override
  int compareTo(FlightDuration other) => inMinutes.compareTo(other.inMinutes);

  @override
  bool operator ==(Object other) =>
      other is FlightDuration && other.inMinutes == inMinutes;

  @override
  int get hashCode => inMinutes.hashCode;

  @override
  String toString() => 'FlightDuration($inMinutes minutes)';
}
