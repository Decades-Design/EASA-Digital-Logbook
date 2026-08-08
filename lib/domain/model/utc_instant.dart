import 'wall_clock.dart';

/// An instant guaranteed to be UTC, enforced by the type system rather than
/// by convention.
///
/// `AMC1 FCL.050` requires flight times to be recorded in UTC, and CLAUDE.md
/// rule 3 restates it as a hard project rule: all stored times are UTC,
/// never a naive local `DateTime`. ADR-0002 records the decision and the gap
/// this type closes — `DateTime.isUtc` is trivially lost (a local `DateTime`
/// or a UTC value that has been `.toLocal()`ed both still type-check as
/// plain `DateTime`), and the failure that produces is silent: night time
/// and currency windows are computed against the wrong instant with no
/// exception and no test failure. `UtcInstant` makes the wrong thing
/// impossible to express instead of merely discouraged: there is no
/// constructor that accepts a local value, and `tool/check_domain_types.dart`
/// (issue #15) fails the build if any other file in `lib/domain/` even names
/// `DateTime`.
///
/// **The `DateTime.parse` trap.** `DateTime.parse('2026-03-14T09:05:00')` —
/// a string with no zone designator — silently returns a *local* `DateTime`
/// with no error and no warning; [UtcInstant.parse] rejects exactly that
/// input instead.
///
/// **`asUtcDateTime` is an escape hatch for interop only** — with `drift`,
/// `pdf`, and vendor CSV libraries that want a plain `DateTime` — and its
/// result must never be `.toLocal()`ed anywhere inside `lib/domain/`; doing
/// so recreates the exact silent-local-time bug this type exists to
/// prevent. Local rendering belongs to the UI layer.
///
/// **The M4 boundary.** [toWallClock] takes an [offset] the *caller*
/// supplies — it does not know or guess which offset applies to a named
/// time zone. Resolving "Europe/London" or "America/New_York" to a
/// UTC offset at a given instant, including historical DST rules, requires
/// the IANA time zone database, and that lookup belongs to the UI layer in
/// M4, not to `lib/domain/`. No `package:timezone` dependency is added by
/// this task — that was a deliberate decision by the project owner, not an
/// oversight, and M4 is where the deferred lookup lands.
class UtcInstant implements Comparable<UtcInstant> {
  const UtcInstant._(this._value);

  /// Wraps [value], which must already be UTC.
  ///
  /// Throws [ArgumentError] if `value.isUtc` is false — a local `DateTime`
  /// is never silently accepted or converted, because either direction
  /// (assuming it's already UTC, or converting it) can mask a real
  /// programming error at the call site.
  factory UtcInstant.fromDateTime(DateTime value) {
    if (!value.isUtc) {
      throw ArgumentError.value(
        value,
        'value',
        'must be a UTC DateTime (isUtc == true); a local DateTime is never '
            'silently accepted — see CLAUDE.md rule 3 and ADR-0002',
      );
    }
    return UtcInstant._(value);
  }

  /// Constructs a UTC instant directly from calendar fields, exactly like
  /// `DateTime.utc`.
  factory UtcInstant.utc(
    int year, [
    int month = 1,
    int day = 1,
    int hour = 0,
    int minute = 0,
    int second = 0,
    int millisecond = 0,
  ]) => UtcInstant._(
    DateTime.utc(year, month, day, hour, minute, second, millisecond),
  );

  /// Parses an ISO-8601 [source] string that must carry an explicit UTC zone
  /// designator — either `Z` or a numeric offset such as `+01:00`.
  ///
  /// An explicit numeric offset is accepted, not just `Z`, because
  /// `DateTime.parse` converts it to UTC losslessly and vendor CSV import
  /// (ForeFlight, Garmin) will encounter offset-qualified timestamps; the
  /// resulting [UtcInstant] always serialises back out with `Z`
  /// ([toIso8601String]), never with a bare offset.
  ///
  /// Throws [FormatException] naming [source] if the string is malformed, or
  /// if it parses but carries no zone designator at all — the exact input
  /// `DateTime.parse` would otherwise silently resolve to a local time.
  factory UtcInstant.parse(String source) {
    final parsed = DateTime.parse(source);
    if (!parsed.isUtc) {
      throw FormatException(
        'No UTC zone designator (Z or a numeric offset) in source; '
        'DateTime.parse would silently return a local DateTime for this '
        'string',
        source,
      );
    }
    return UtcInstant._(parsed);
  }

  /// As [UtcInstant.parse], but returns `null` instead of throwing on a
  /// malformed or zone-less [source].
  ///
  /// Only [FormatException] is caught — a programming error thrown from
  /// somewhere else in the call is never swallowed.
  static UtcInstant? tryParse(String source) {
    try {
      return UtcInstant.parse(source);
    } on FormatException {
      return null;
    }
  }

  /// The wrapped instant. Always `isUtc == true` — see [asUtcDateTime].
  final DateTime _value;

  /// Escape hatch for interop with code outside `lib/domain/` that needs a
  /// plain `DateTime` (persistence, PDF export, vendor adapters). Always
  /// `isUtc == true`. Never call `.toLocal()` on the result inside
  /// `lib/domain/` — see the class dartdoc.
  DateTime get asUtcDateTime => _value;

  /// Milliseconds since the Unix epoch, UTC.
  int get millisecondsSinceEpoch => _value.millisecondsSinceEpoch;

  /// Formats as ISO-8601 with an explicit trailing `Z`, e.g.
  /// `'2026-03-14T09:05:00.000Z'`. Never a bare offset-less string — ADR-0002
  /// requires the zone designator always be explicit, precisely so this
  /// output can never be misread as local by a later `DateTime.parse`.
  String toIso8601String() => _value.toIso8601String();

  /// Renders this instant as a calendar reading at [offset] from UTC.
  ///
  /// [offset] is supplied by the caller — see the M4 boundary note on the
  /// class dartdoc. The computation is exact instant arithmetic (shift by
  /// [offset], then read the calendar fields), so it correctly produces the
  /// spring-forward gap and the autumn ambiguous hour as two different
  /// [WallClock] readings for two different instants, never one.
  WallClock toWallClock(Duration offset) {
    final shifted = _value.add(offset);
    return WallClock(
      year: shifted.year,
      month: shifted.month,
      day: shifted.day,
      hour: shifted.hour,
      minute: shifted.minute,
      second: shifted.second,
      offset: offset,
    );
  }

  UtcInstant add(Duration duration) => UtcInstant._(_value.add(duration));

  UtcInstant subtract(Duration duration) =>
      UtcInstant._(_value.subtract(duration));

  Duration difference(UtcInstant other) => _value.difference(other._value);

  bool operator <(UtcInstant other) => _value.isBefore(other._value);

  bool operator <=(UtcInstant other) => !_value.isAfter(other._value);

  bool operator >(UtcInstant other) => _value.isAfter(other._value);

  bool operator >=(UtcInstant other) => !_value.isBefore(other._value);

  @override
  int compareTo(UtcInstant other) => _value.compareTo(other._value);

  @override
  bool operator ==(Object other) =>
      other is UtcInstant && other._value.isAtSameMomentAs(_value);

  @override
  int get hashCode => _value.hashCode;

  @override
  String toString() => 'UtcInstant(${toIso8601String()})';
}
