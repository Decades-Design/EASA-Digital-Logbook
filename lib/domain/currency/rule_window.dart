import '../model/calendar_date.dart';
import 'held_record.dart';

/// The two window shapes #40 requires as distinct concepts: "3 in the
/// preceding 90 days" is a sliding rolling-day window; "24 calendar months"
/// is not "730 days" — it runs to the end of a specific month regardless of
/// which day of the month the anchor fell on.
enum WindowKind { rollingDays, calendarMonths }

/// What a [RuleWindow] is measured relative to.
enum WindowAnchor {
  /// The date the rule is being evaluated as of — the ordinary case, and
  /// the only anchor a *rolling* recency rule (EASA/FAA passenger currency)
  /// ever uses.
  evaluationDate,

  /// A held record's expiry date, e.g. FCL.740.A's SEP revalidation window,
  /// which runs against the *rating's* expiry, not against today (#47). The
  /// window does not slide as the evaluation date changes; it is fixed once
  /// the anchoring record's expiry is known.
  heldRecordExpiry,
}

/// The `[start, end]` range a window resolves to for one evaluation —
/// occurrences dated within this range, inclusive at both ends, count
/// toward the requirement.
class DateRange {
  const DateRange(this.start, this.end);

  final CalendarDate start;
  final CalendarDate end;
}

/// A recency window, as #40 requires it expressible: a rolling number of
/// days, or a number of calendar months, optionally anchored to a held
/// record's expiry rather than to the evaluation date.
///
/// Two independent questions a window answers, kept as two methods rather
/// than folded into one, because they answer genuinely different things:
/// [rangeEndingAt] sums *multiple* occurrences backward from a reference
/// point (how the evaluator filters a flight set); [expiryFrom] projects
/// forward from a *single* occurrence (how a satisfied [RuleResult]'s
/// expiry date, and #44's forward projection, are computed).
class RuleWindow {
  const RuleWindow._({
    required this.kind,
    this.days,
    this.months,
    this.anchor = WindowAnchor.evaluationDate,
    this.anchorHeldRecordKind,
  });

  factory RuleWindow.rollingDays(int days) =>
      RuleWindow._(kind: WindowKind.rollingDays, days: days);

  factory RuleWindow.calendarMonths(
    int months, {
    WindowAnchor anchor = WindowAnchor.evaluationDate,
    String? anchorHeldRecordKind,
  }) {
    if (anchor == WindowAnchor.heldRecordExpiry &&
        anchorHeldRecordKind == null) {
      throw ArgumentError(
        'anchorHeldRecordKind is required when anchor is heldRecordExpiry',
      );
    }
    return RuleWindow._(
      kind: WindowKind.calendarMonths,
      months: months,
      anchor: anchor,
      anchorHeldRecordKind: anchorHeldRecordKind,
    );
  }

  final WindowKind kind;

  /// Set when [kind] is [WindowKind.rollingDays].
  final int? days;

  /// Set when [kind] is [WindowKind.calendarMonths].
  final int? months;
  final WindowAnchor anchor;

  /// The [HeldRecord.kind] to anchor to, when [anchor] is
  /// [WindowAnchor.heldRecordExpiry]. Non-null exactly when [anchor] is.
  final String? anchorHeldRecordKind;

  /// The window's reference point: [evaluationDate] itself, or — for
  /// [WindowAnchor.heldRecordExpiry] — the matching [HeldRecord]'s expiry.
  ///
  /// Throws [StateError] naming the missing kind if no matching held record
  /// with an expiry is present: an expiry-anchored rule with nothing to
  /// anchor to is a configuration or data problem, not a state to silently
  /// treat as "not applicable".
  CalendarDate _referenceDate(
    CalendarDate evaluationDate,
    List<HeldRecord> heldRecords,
  ) {
    if (anchor == WindowAnchor.evaluationDate) {
      return evaluationDate;
    }
    final recordKind = anchorHeldRecordKind!;
    for (final record in heldRecords) {
      if (record.kind == recordKind && record.validUntil != null) {
        return record.validUntil!;
      }
    }
    throw StateError(
      'Window anchors to held record kind "$recordKind" with an expiry, '
      'but no such record was supplied',
    );
  }

  /// The range to sum qualifying occurrences across, ending at this
  /// window's reference point (see [_referenceDate]).
  DateRange rangeEndingAt(
    CalendarDate evaluationDate, {
    required List<HeldRecord> heldRecords,
  }) {
    final end = _referenceDate(evaluationDate, heldRecords);
    final start = switch (kind) {
      WindowKind.rollingDays => end.addDays(-days!),
      WindowKind.calendarMonths => _shiftCalendarMonths(end, -months!),
    };
    return DateRange(start, end);
  }

  /// The last date a single occurrence dated [occurrenceDate] still counts
  /// toward this window — the day recency lapses is the day after.
  ///
  /// For [WindowKind.calendarMonths] this is always the last day of the
  /// target month, never a day-of-month-preserving shift — "24 calendar
  /// months" is valid *through the end of* the 24th month regardless of
  /// which day of the month the occurrence fell on (#49).
  CalendarDate expiryFrom(CalendarDate occurrenceDate) {
    return switch (kind) {
      WindowKind.rollingDays => occurrenceDate.addDays(days!),
      WindowKind.calendarMonths => _lastDayOfMonth(
        _shiftMonthOnly(occurrenceDate.year, occurrenceDate.month, months!),
      ),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is RuleWindow &&
      other.kind == kind &&
      other.days == days &&
      other.months == months &&
      other.anchor == anchor &&
      other.anchorHeldRecordKind == anchorHeldRecordKind;

  @override
  int get hashCode =>
      Object.hash(kind, days, months, anchor, anchorHeldRecordKind);

  @override
  String toString() =>
      'RuleWindow(kind: $kind, days: $days, months: $months, '
      'anchor: $anchor, anchorHeldRecordKind: $anchorHeldRecordKind)';
}

bool _isLeapYear(int year) =>
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;

int _daysInMonth(int year, int month) {
  const lengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (month == 2 && _isLeapYear(year)) {
    return 29;
  }
  return lengths[month - 1];
}

/// (year, month) shifted by [deltaMonths], normalising overflow/underflow
/// into year carries. Floor division, not truncating `~/`, so this is also
/// correct for a negative [deltaMonths] that crosses a year boundary — Dart's
/// `%` already returns a non-negative remainder against a positive divisor,
/// so `total - (total % 12)` is always the exact multiple of 12 at or below
/// `total`.
(int, int) _shiftMonthOnly(int year, int month, int deltaMonths) {
  final total = year * 12 + (month - 1) + deltaMonths;
  final remainder = total % 12;
  final newYear = (total - remainder) ~/ 12;
  return (newYear, remainder + 1);
}

/// [date] shifted by [deltaMonths] calendar months, clamping the day to the
/// target month's last real day (e.g. 31 Jan − 1 month → 31 Dec is fine, but
/// 31 Jan + 1 month clamps to 28/29 Feb — there is no 31 February).
CalendarDate _shiftCalendarMonths(CalendarDate date, int deltaMonths) {
  final (year, month) = _shiftMonthOnly(date.year, date.month, deltaMonths);
  final day = date.day > _daysInMonth(year, month)
      ? _daysInMonth(year, month)
      : date.day;
  return CalendarDate(year, month, day);
}

CalendarDate _lastDayOfMonth((int, int) yearMonth) {
  final (year, month) = yearMonth;
  return CalendarDate(year, month, _daysInMonth(year, month));
}
