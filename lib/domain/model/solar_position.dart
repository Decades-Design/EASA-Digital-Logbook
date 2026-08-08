import 'dart:math' as math;

import 'geo_coordinate.dart';
import 'utc_instant.dart';

/// #20: the sun's position, needed because both EASA and FAA define "night"
/// by reference to civil twilight rather than a clock time —
/// `docs/jurisdiction-matrix.md` line 87. The EASA and FAA night-time
/// primitives (#21, #22) are both built on [solarElevationDegrees] alone, so
/// a formula fix here fixes both.
///
/// Low-precision solar position algorithm: Meeus, *Astronomical Algorithms*
/// ch. 25, in the form NOAA's solar calculator uses. Good to a fraction of a
/// degree, which is what "within a minute" of a published sunrise/sunset time
/// needs — near the horizon at mid-latitudes the sun moves roughly
/// 0.25 degrees of elevation per minute.

/// Conventional sunrise/sunset threshold, in degrees of elevation: the sun's
/// centre 0.833 degrees below the geometric horizon (34' refraction + 16'
/// solar radius — Meeus, USNO), the standard used by every rigorous source
/// checked against `test/domain/model/solar_position_test.dart`. This is
/// *not* the definition either jurisdiction uses for night — see
/// [civilTwilightThresholdDegrees] — but sunrise/sunset are independently
/// useful (`docs/entry-form.md` line 289: the entry form pre-fills day/night
/// landing counts from a twilight computation, and sunrise/sunset anchor
/// that computation for the reader) and load-bearing for the FAA night
/// *currency* window (`§61.57(b)`, sunset/sunrise ± 1 hour — the FAA
/// night-time primitive, not this one).
///
/// Unlike the twilight thresholds below, sunrise/sunset is inherently a
/// refraction-dependent, not purely geometric, question — real atmospheric
/// refraction right at the horizon varies with conditions, which is why
/// different published calculators can disagree on sunrise/sunset by a
/// minute or two even when they agree on civil twilight. The US Naval
/// Observatory (the reference this codebase validates against) was checked
/// against a commercial calculator during development; the two agreed on
/// civil twilight but differed by about two minutes on sunrise/sunset. USNO
/// was treated as authoritative.
const double sunriseSunsetThresholdDegrees = -0.833;

/// Civil twilight threshold, in degrees of elevation. Both EASA (FCL.010)
/// and the FAA (`§1.1`) define night, for logging purposes, as the period
/// the sun is more than 6 degrees below the horizon —
/// `docs/jurisdiction-matrix.md` line 87.
const double civilTwilightThresholdDegrees = -6.0;

double _toRadians(double degrees) => degrees * math.pi / 180;

double _toDegrees(double radians) => radians * 180 / math.pi;

double _normalizeDegrees(double degrees) {
  final result = degrees % 360;
  return result < 0 ? result + 360 : result;
}

/// Julian Day for [instant]. `2440587.5` is the Julian Day of the Unix
/// epoch (1970-01-01T00:00:00Z).
double _julianDay(UtcInstant instant) =>
    2440587.5 + instant.millisecondsSinceEpoch / 86400000.0;

double _minutesSinceMidnightUtc(UtcInstant instant) {
  final value = instant.asUtcDateTime;
  return value.hour * 60 +
      value.minute +
      value.second / 60 +
      value.millisecond / 60000;
}

double _geometricMeanLongitudeDegrees(double t) =>
    _normalizeDegrees(280.46646 + t * (36000.76983 + t * 0.0003032));

double _geometricMeanAnomalyDegrees(double t) =>
    357.52911 + t * (35999.05029 - 0.0001537 * t);

double _eccentricityEarthOrbit(double t) =>
    0.016708634 - t * (0.000042037 + 0.0000001267 * t);

double _sunEquationOfCenterDegrees(double t) {
  final meanAnomalyRad = _toRadians(_geometricMeanAnomalyDegrees(t));
  return math.sin(meanAnomalyRad) * (1.914602 - t * (0.004817 + 0.000014 * t)) +
      math.sin(2 * meanAnomalyRad) * (0.019993 - 0.000101 * t) +
      math.sin(3 * meanAnomalyRad) * 0.000289;
}

double _sunTrueLongitudeDegrees(double t) =>
    _geometricMeanLongitudeDegrees(t) + _sunEquationOfCenterDegrees(t);

double _sunApparentLongitudeDegrees(double t) {
  final omegaDegrees = 125.04 - 1934.136 * t;
  return _sunTrueLongitudeDegrees(t) -
      0.00569 -
      0.00478 * math.sin(_toRadians(omegaDegrees));
}

double _meanObliquityOfEclipticDegrees(double t) =>
    23 +
    (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60;

double _obliquityCorrectionDegrees(double t) {
  final omegaDegrees = 125.04 - 1934.136 * t;
  return _meanObliquityOfEclipticDegrees(t) +
      0.00256 * math.cos(_toRadians(omegaDegrees));
}

double _sunDeclinationDegrees(double t) {
  final obliquityRad = _toRadians(_obliquityCorrectionDegrees(t));
  final apparentLongitudeRad = _toRadians(_sunApparentLongitudeDegrees(t));
  return _toDegrees(
    math.asin(math.sin(obliquityRad) * math.sin(apparentLongitudeRad)),
  );
}

double _equationOfTimeMinutes(double t) {
  final obliquityRad = _toRadians(_obliquityCorrectionDegrees(t));
  final y = math.tan(obliquityRad / 2) * math.tan(obliquityRad / 2);
  final l0Rad = _toRadians(_geometricMeanLongitudeDegrees(t));
  final e = _eccentricityEarthOrbit(t);
  final meanAnomalyRad = _toRadians(_geometricMeanAnomalyDegrees(t));

  final value =
      y * math.sin(2 * l0Rad) -
      2 * e * math.sin(meanAnomalyRad) +
      4 * e * y * math.sin(meanAnomalyRad) * math.cos(2 * l0Rad) -
      0.5 * y * y * math.sin(4 * l0Rad) -
      1.25 * e * e * math.sin(2 * meanAnomalyRad);
  return 4 * _toDegrees(value);
}

/// The sun's elevation above the horizon, in degrees, at [instant] and
/// [position]. Positive above the horizon, negative below. Refraction is
/// not modelled — that correction is folded into
/// [sunriseSunsetThresholdDegrees] instead of into this function, so this
/// function stays the one place both thresholds are evaluated against.
///
/// A pure function of its two arguments, no I/O and no platform dependency —
/// #20's acceptance criterion — so it can run identically in a background
/// isolate or inline.
double solarElevationDegrees(UtcInstant instant, GeoCoordinate position) {
  final t = (_julianDay(instant) - 2451545.0) / 36525.0;

  final declinationDegrees = _sunDeclinationDegrees(t);
  final equationOfTimeMinutes = _equationOfTimeMinutes(t);

  var trueSolarTime =
      (_minutesSinceMidnightUtc(instant) +
          equationOfTimeMinutes +
          4 * position.longitude) %
      1440;
  if (trueSolarTime < 0) {
    trueSolarTime += 1440;
  }
  final hourAngleDegrees = trueSolarTime / 4 - 180;

  final latitudeRad = _toRadians(position.latitude);
  final declinationRad = _toRadians(declinationDegrees);
  final hourAngleRad = _toRadians(hourAngleDegrees);

  final cosZenith =
      (math.sin(latitudeRad) * math.sin(declinationRad) +
              math.cos(latitudeRad) *
                  math.cos(declinationRad) *
                  math.cos(hourAngleRad))
          .clamp(-1.0, 1.0);
  return 90 - _toDegrees(math.acos(cosZenith));
}

/// Whether the sun is more than 6 degrees below the horizon at [instant] and
/// [position] — the EASA and FAA definition of night for logging purposes
/// (`docs/jurisdiction-matrix.md` line 87). Night *currency* windows use a
/// different threshold entirely (sunset/sunrise ± 1 hour, `§61.57(b)`) and
/// are not this function's concern — see the FAA night-time primitive.
bool isNight(UtcInstant instant, GeoCoordinate position) =>
    solarElevationDegrees(instant, position) < civilTwilightThresholdDegrees;

/// Whether, on the UTC calendar date [onDate] falls on, the sun's elevation
/// at [position] crosses a threshold at all, and if so where.
enum SolarThresholdState {
  /// The sun's elevation rises above and falls back below the threshold
  /// during the day — [SolarThresholdCrossing.ascending] and
  /// [SolarThresholdCrossing.descending] are both set.
  crosses,

  /// The sun's elevation never drops to the threshold — e.g. midnight sun
  /// for [sunriseSunsetThresholdDegrees], or the civil-twilight-all-night
  /// condition at high summer latitudes for [civilTwilightThresholdDegrees].
  aboveAllDay,

  /// The sun's elevation never rises to the threshold — polar night.
  belowAllDay,
}

/// The instants (if any) at which the sun's elevation crosses a threshold on
/// one UTC calendar date, at one position.
class SolarThresholdCrossing {
  const SolarThresholdCrossing({
    required this.ascending,
    required this.descending,
    required this.state,
  });

  /// The instant elevation rises through the threshold — morning. Non-null
  /// only when [state] is [SolarThresholdState.crosses].
  final UtcInstant? ascending;

  /// The instant elevation falls through the threshold — evening. Non-null
  /// only when [state] is [SolarThresholdState.crosses].
  final UtcInstant? descending;

  final SolarThresholdState state;
}

/// 10-minute steps across a 24-hour UTC date. Within one calendar day, the
/// sun's elevation has at most one local maximum and one local minimum — a
/// smooth, roughly sinusoidal curve with a 24-hour period — so 10-minute
/// sampling cannot straddle and miss a crossing; [_bisectCrossing] then
/// refines each bracketed crossing well past the 1-minute accuracy target.
const int _sampleCount = 144;
const int _sampleStepMinutes = 1440 ~/ _sampleCount;
const Duration _bisectionTolerance = Duration(seconds: 15);

/// Finds where the sun's elevation at [position] crosses [thresholdDegrees],
/// on the UTC calendar date [onDate] falls on (time-of-day in [onDate] is
/// ignored; only the date is used).
///
/// High-latitude condition where the sun never reaches the threshold that
/// day is reported via [SolarThresholdCrossing.state], never thrown — #20's
/// explicit acceptance criterion.
SolarThresholdCrossing solarThresholdCrossings({
  required UtcInstant onDate,
  required GeoCoordinate position,
  required double thresholdDegrees,
}) {
  final calendarDate = onDate.asUtcDateTime;
  final midnight = UtcInstant.utc(
    calendarDate.year,
    calendarDate.month,
    calendarDate.day,
  );

  double elevationAboveThreshold(UtcInstant instant) =>
      solarElevationDegrees(instant, position) - thresholdDegrees;

  UtcInstant? ascending;
  UtcInstant? descending;

  var previousInstant = midnight;
  var previousValue = elevationAboveThreshold(previousInstant);

  for (var sample = 1; sample <= _sampleCount; sample++) {
    final currentInstant = midnight.add(
      Duration(minutes: sample * _sampleStepMinutes),
    );
    final currentValue = elevationAboveThreshold(currentInstant);

    if ((previousValue < 0) != (currentValue < 0)) {
      final crossing = _bisectCrossing(
        position: position,
        thresholdDegrees: thresholdDegrees,
        lowInstant: previousInstant,
        lowValue: previousValue,
        highInstant: currentInstant,
      );
      if (previousValue < 0) {
        ascending = crossing;
      } else {
        descending = crossing;
      }
    }

    previousInstant = currentInstant;
    previousValue = currentValue;
  }

  final state = ascending != null || descending != null
      ? SolarThresholdState.crosses
      : (previousValue >= 0
            ? SolarThresholdState.aboveAllDay
            : SolarThresholdState.belowAllDay);

  return SolarThresholdCrossing(
    ascending: ascending,
    descending: descending,
    state: state,
  );
}

/// Bisects between [lowInstant] (where elevation-minus-threshold is
/// [lowValue]) and [highInstant] (the opposite sign) to find the crossing
/// instant to within [_bisectionTolerance].
UtcInstant _bisectCrossing({
  required GeoCoordinate position,
  required double thresholdDegrees,
  required UtcInstant lowInstant,
  required double lowValue,
  required UtcInstant highInstant,
}) {
  var low = lowInstant;
  var high = highInstant;
  final lowIsNegative = lowValue < 0;

  while (high.difference(low) > _bisectionTolerance) {
    final mid = low.add(high.difference(low) ~/ 2);
    final midValue = solarElevationDegrees(mid, position) - thresholdDegrees;
    if ((midValue < 0) == lowIsNegative) {
      low = mid;
    } else {
      high = mid;
    }
  }
  return low.add(high.difference(low) ~/ 2);
}
