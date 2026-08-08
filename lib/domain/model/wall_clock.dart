/// A rendered calendar reading at a stated offset from UTC.
///
/// **What this is not: an instant.** [WallClock] is the result of asking
/// "what would a clock on the wall read, at this offset, for this instant" —
/// it is a display value, not a point in time. It cannot be persisted (see
/// CLAUDE.md rule 3 and ADR-0002 — every stored instant is UTC), it cannot
/// be meaningfully compared to a [WallClock] carrying a different [offset]
/// (`14:35` at `+05:30` and `09:05` at `+00:00` may be the same instant or
/// may not be — the fields alone don't say), and it has no meaning without
/// the [offset] it carries, which is why it always carries one. This is
/// exactly why [UtcInstant.toWallClock] returns a [WallClock] rather than a
/// bare `DateTime`: a `DateTime` with an offset baked into its fields but no
/// record of what that offset was is precisely the silent-local-time trap
/// this package exists to avoid.
class WallClock {
  const WallClock({
    required this.year,
    required this.month,
    required this.day,
    required this.hour,
    required this.minute,
    required this.second,
    required this.offset,
  });

  final int year;
  final int month;
  final int day;
  final int hour;
  final int minute;
  final int second;

  /// The offset from UTC this reading was rendered at, e.g.
  /// `Duration(hours: 1)` for BST. Carried alongside the calendar fields
  /// because they are meaningless without it.
  final Duration offset;

  /// Formats as `'2026-03-29 02:30 +01:00'`: date, space, zero-padded
  /// `HH:MM`, space, signed zero-padded `±HH:MM` offset. A zero offset
  /// renders `+00:00`, never `-00:00` or a bare `Z`.
  @override
  String toString() {
    final y = year.toString().padLeft(4, '0');
    final mo = month.toString().padLeft(2, '0');
    final d = day.toString().padLeft(2, '0');
    final h = hour.toString().padLeft(2, '0');
    final mi = minute.toString().padLeft(2, '0');

    final totalOffsetMinutes = offset.inMinutes;
    final offsetSign = totalOffsetMinutes < 0 ? '-' : '+';
    final offsetMagnitude = totalOffsetMinutes.abs();
    final offsetHours = (offsetMagnitude ~/ 60).toString().padLeft(2, '0');
    final offsetMinutes = (offsetMagnitude % 60).toString().padLeft(2, '0');

    return '$y-$mo-$d $h:$mi $offsetSign$offsetHours:$offsetMinutes';
  }

  @override
  bool operator ==(Object other) =>
      other is WallClock &&
      other.year == year &&
      other.month == month &&
      other.day == day &&
      other.hour == hour &&
      other.minute == minute &&
      other.second == second &&
      other.offset == offset;

  @override
  int get hashCode =>
      Object.hash(year, month, day, hour, minute, second, offset);
}
