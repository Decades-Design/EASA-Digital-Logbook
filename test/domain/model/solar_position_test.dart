// flutter_test re-exports test/group/expect from package:test_api, so plain
// Dart tests need no separate package:test dependency.
import 'package:easa_digital_log/domain/model/geo_coordinate.dart';
import 'package:easa_digital_log/domain/model/solar_position.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reference values are from the US Naval Observatory's Rise/Set/Transit/
/// Twilight API (aa.usno.navy.mil/data/api#rstt), the authoritative source
/// for these figures — printed to the minute, hence the one-minute
/// tolerance below rather than anything tighter. A commercial calculator
/// (sunrise-sunset.org) was checked first and agreed with USNO on civil
/// twilight but was consistently about two minutes off USNO on sunrise/
/// sunset specifically; USNO was used throughout once that discrepancy
/// surfaced, rather than mixing sources.
void _expectWithinAMinute(UtcInstant? actual, String referenceIso) {
  expect(actual, isNotNull, reason: 'expected a crossing, got none');
  final reference = UtcInstant.parse(referenceIso);
  final delta = actual!.difference(reference).abs();
  expect(
    delta <= const Duration(minutes: 1),
    isTrue,
    reason: 'expected $actual within a minute of $reference, off by $delta',
  );
}

void main() {
  group('solarElevationDegrees', () {
    test('the sun is high at local solar noon and low at local midnight', () {
      final equator = GeoCoordinate(latitude: 0, longitude: 0);
      final noon = UtcInstant.utc(2024, 3, 20, 12);
      final midnight = UtcInstant.utc(2024, 3, 20, 0);

      expect(solarElevationDegrees(noon, equator), greaterThan(80));
      expect(solarElevationDegrees(midnight, equator), lessThan(-80));
    });
  });

  group('isNight', () {
    test('is false in the middle of the day', () {
      final london = GeoCoordinate(latitude: 51.5074, longitude: -0.1278);
      expect(isNight(UtcInstant.utc(2024, 6, 21, 12), london), isFalse);
    });

    test('is true well before morning civil twilight', () {
      final london = GeoCoordinate(latitude: 51.5074, longitude: -0.1278);
      // Civil twilight begins ~02:55Z on this date; well before that.
      expect(isNight(UtcInstant.utc(2024, 6, 21, 0), london), isTrue);
    });
  });

  group('solarThresholdCrossings — sunrise/sunset threshold', () {
    test('London on the June 2024 solstice', () {
      final london = GeoCoordinate(latitude: 51.5074, longitude: -0.1278);
      final result = solarThresholdCrossings(
        onDate: UtcInstant.utc(2024, 6, 21),
        position: london,
        thresholdDegrees: sunriseSunsetThresholdDegrees,
      );

      expect(result.state, SolarThresholdState.crosses);
      _expectWithinAMinute(result.ascending, '2024-06-21T03:43:00Z');
      _expectWithinAMinute(result.descending, '2024-06-21T20:22:00Z');
    });

    test('London on the December 2024 solstice', () {
      final london = GeoCoordinate(latitude: 51.5074, longitude: -0.1278);
      final result = solarThresholdCrossings(
        onDate: UtcInstant.utc(2024, 12, 21),
        position: london,
        thresholdDegrees: sunriseSunsetThresholdDegrees,
      );

      expect(result.state, SolarThresholdState.crosses);
      _expectWithinAMinute(result.ascending, '2024-12-21T08:04:00Z');
      _expectWithinAMinute(result.descending, '2024-12-21T15:54:00Z');
    });

    test('the equator on the March 2024 equinox', () {
      final equator = GeoCoordinate(latitude: 0, longitude: 0);
      final result = solarThresholdCrossings(
        onDate: UtcInstant.utc(2024, 3, 20),
        position: equator,
        thresholdDegrees: sunriseSunsetThresholdDegrees,
      );

      expect(result.state, SolarThresholdState.crosses);
      _expectWithinAMinute(result.ascending, '2024-03-20T06:04:00Z');
      _expectWithinAMinute(result.descending, '2024-03-20T18:11:00Z');
    });

    test('midnight sun above the Arctic Circle: never sets, never throws', () {
      final tromso = GeoCoordinate(latitude: 69.6492, longitude: 18.9553);
      final result = solarThresholdCrossings(
        onDate: UtcInstant.utc(2024, 6, 21),
        position: tromso,
        thresholdDegrees: sunriseSunsetThresholdDegrees,
      );

      expect(result.state, SolarThresholdState.aboveAllDay);
      expect(result.ascending, isNull);
      expect(result.descending, isNull);
    });

    test('polar night above the Arctic Circle: never rises, never throws', () {
      final tromso = GeoCoordinate(latitude: 69.6492, longitude: 18.9553);
      final result = solarThresholdCrossings(
        onDate: UtcInstant.utc(2024, 12, 21),
        position: tromso,
        thresholdDegrees: sunriseSunsetThresholdDegrees,
      );

      expect(result.state, SolarThresholdState.belowAllDay);
      expect(result.ascending, isNull);
      expect(result.descending, isNull);
    });

    test('the geographic North Pole never throws, in any season', () {
      final pole = GeoCoordinate(latitude: 90, longitude: 0);

      final juneResult = solarThresholdCrossings(
        onDate: UtcInstant.utc(2024, 6, 21),
        position: pole,
        thresholdDegrees: sunriseSunsetThresholdDegrees,
      );
      final decemberResult = solarThresholdCrossings(
        onDate: UtcInstant.utc(2024, 12, 21),
        position: pole,
        thresholdDegrees: sunriseSunsetThresholdDegrees,
      );

      expect(juneResult.state, SolarThresholdState.aboveAllDay);
      expect(decemberResult.state, SolarThresholdState.belowAllDay);
      expect(
        solarElevationDegrees(UtcInstant.utc(2024, 6, 21), pole).isNaN,
        isFalse,
      );
    });
  });

  group('solarThresholdCrossings — civil twilight threshold', () {
    test('London on the June 2024 solstice', () {
      final london = GeoCoordinate(latitude: 51.5074, longitude: -0.1278);
      final result = solarThresholdCrossings(
        onDate: UtcInstant.utc(2024, 6, 21),
        position: london,
        thresholdDegrees: civilTwilightThresholdDegrees,
      );

      expect(result.state, SolarThresholdState.crosses);
      _expectWithinAMinute(result.ascending, '2024-06-21T02:55:00Z');
      _expectWithinAMinute(result.descending, '2024-06-21T21:09:00Z');
    });

    test('London on the December 2024 solstice', () {
      final london = GeoCoordinate(latitude: 51.5074, longitude: -0.1278);
      final result = solarThresholdCrossings(
        onDate: UtcInstant.utc(2024, 12, 21),
        position: london,
        thresholdDegrees: civilTwilightThresholdDegrees,
      );

      expect(result.state, SolarThresholdState.crosses);
      _expectWithinAMinute(result.ascending, '2024-12-21T07:24:00Z');
      _expectWithinAMinute(result.descending, '2024-12-21T16:34:00Z');
    });

    test('the equator on the March 2024 equinox', () {
      final equator = GeoCoordinate(latitude: 0, longitude: 0);
      final result = solarThresholdCrossings(
        onDate: UtcInstant.utc(2024, 3, 20),
        position: equator,
        thresholdDegrees: civilTwilightThresholdDegrees,
      );

      expect(result.state, SolarThresholdState.crosses);
      _expectWithinAMinute(result.ascending, '2024-03-20T05:43:00Z');
      _expectWithinAMinute(result.descending, '2024-03-20T18:31:00Z');
    });

    test('above the Arctic Circle in midsummer, civil twilight never ends '
        'either — the sun sets but it never gets properly dark', () {
      final tromso = GeoCoordinate(latitude: 69.6492, longitude: 18.9553);
      final result = solarThresholdCrossings(
        onDate: UtcInstant.utc(2024, 6, 21),
        position: tromso,
        thresholdDegrees: civilTwilightThresholdDegrees,
      );

      expect(result.state, SolarThresholdState.aboveAllDay);
    });

    test('above the Arctic Circle in midwinter, civil twilight still happens '
        'for a few hours around midday even though the sun never rises — this '
        'is exactly why sunrise/sunset and civil twilight are independent '
        'thresholds, not one shared window', () {
      final tromso = GeoCoordinate(latitude: 69.6492, longitude: 18.9553);
      final sunriseSunset = solarThresholdCrossings(
        onDate: UtcInstant.utc(2024, 12, 21),
        position: tromso,
        thresholdDegrees: sunriseSunsetThresholdDegrees,
      );
      final civilTwilight = solarThresholdCrossings(
        onDate: UtcInstant.utc(2024, 12, 21),
        position: tromso,
        thresholdDegrees: civilTwilightThresholdDegrees,
      );

      expect(sunriseSunset.state, SolarThresholdState.belowAllDay);
      expect(civilTwilight.state, SolarThresholdState.crosses);
      _expectWithinAMinute(civilTwilight.ascending, '2024-12-21T08:32:00Z');
      _expectWithinAMinute(civilTwilight.descending, '2024-12-21T12:53:00Z');
    });
  });
}
