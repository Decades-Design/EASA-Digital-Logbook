import '../model/aerodrome_directory.dart';
import '../model/aircraft.dart';
import '../model/flight.dart';
import '../model/flight_duration.dart';
import '../model/flight_times.dart';
import '../projection/derived_quantity.dart';
import 'cross_country_support.dart';

/// FAA `cross_country_rule` primitive. `§61.1(b)(3)` is seven
/// sub-paragraphs, not one threshold — see
/// `docs/jurisdiction-matrix.md` §"Cross-country, expanded". (i) is the
/// general logging definition, no minimum distance; (ii)-(vii) are
/// purpose-specific *credit* tests at 50, 25 or 15 nm depending on the
/// certificate/rating being credited and, for two of them, on
/// [Aircraft.category].
///
/// Every sub-test is computed for every flight, independently — a flight
/// can pass one and fail another, and this primitive has no notion of which
/// certificate the pilot actually holds (that is a later, M2+ concern), so
/// it answers all six "would this count toward..." questions at once rather
/// than picking one.
///
/// Distance is [furthestLandingDistanceFromDepartureNm]: the greatest
/// straight-line distance from the *original* departure to any landing
/// point, not a leg-by-leg or final-destination figure — #24's explicit
/// acceptance criterion, since a flight that ranges out and returns to
/// land back at departure went that far from departure regardless of where
/// it ended up.
Map<String, DerivedQuantity> faaCrossCountryTime(
  Flight flight,
  Aircraft aircraft,
  AerodromeDirectory aerodromes,
) {
  final blockTime = flight.blockTime;
  final generalCrossCountry = landedAwayFromDeparture(flight);
  final furthestNm = furthestLandingDistanceFromDepartureNm(flight, aerodromes);
  final isRotorcraft = aircraft.category == AircraftCategory.helicopter;
  final isPoweredParachute =
      aircraft.category == AircraftCategory.poweredParachute;

  return {
    'crossCountry': _general(generalCrossCountry, blockTime),
    'crossCountryPrivateCommercialInstrument': _creditTest(
      citation:
          "§61.1(b)(3)(ii) private/commercial/instrument rating/"
          'recreational (except rotorcraft, except powered-parachute)',
      applies: !isPoweredParachute,
      exclusionReason:
          'aircraft category is powered parachute — see '
          'crossCountryPoweredParachute instead',
      generalCrossCountry: generalCrossCountry,
      furthestNm: furthestNm,
      thresholdNm: 50,
      blockTime: blockTime,
    ),
    'crossCountrySportPilot': _creditTest(
      citation: '§61.1(b)(3)(iii) sport pilot (except powered-parachute)',
      applies: !isPoweredParachute,
      exclusionReason:
          'aircraft category is powered parachute — see '
          'crossCountryPoweredParachute instead',
      generalCrossCountry: generalCrossCountry,
      furthestNm: furthestNm,
      thresholdNm: 25,
      blockTime: blockTime,
    ),
    'crossCountryPoweredParachute': _creditTest(
      citation:
          '§61.1(b)(3)(iv) sport pilot with powered-parachute '
          'privileges, or private pilot with powered-parachute category '
          'rating',
      applies: isPoweredParachute,
      exclusionReason: 'aircraft category is not powered parachute',
      generalCrossCountry: generalCrossCountry,
      furthestNm: furthestNm,
      thresholdNm: 15,
      blockTime: blockTime,
    ),
    'crossCountryRotorcraft': _creditTest(
      citation:
          '§61.1(b)(3)(v) rotorcraft category rating, instrument-'
          'helicopter rating, or recreational privileges in a rotorcraft',
      applies: isRotorcraft,
      exclusionReason: 'aircraft category is not rotorcraft',
      generalCrossCountry: generalCrossCountry,
      furthestNm: furthestNm,
      thresholdNm: 25,
      blockTime: blockTime,
    ),
    'crossCountryAirlineTransportPilot': _creditTest(
      citation:
          '§61.1(b)(3)(vi) airline transport pilot (except '
          'rotorcraft)',
      applies: !isRotorcraft,
      exclusionReason: 'aircraft category is rotorcraft',
      generalCrossCountry: generalCrossCountry,
      furthestNm: furthestNm,
      thresholdNm: 50,
      blockTime: blockTime,
    ),
    'crossCountryMilitary': _creditTest(
      citation:
          '§61.1(b)(3)(vii) military pilot qualifying for a '
          'commercial certificate under §61.73 (except rotorcraft)',
      applies: !isRotorcraft,
      exclusionReason: 'aircraft category is rotorcraft',
      generalCrossCountry: generalCrossCountry,
      furthestNm: furthestNm,
      thresholdNm: 50,
      blockTime: blockTime,
    ),
  };
}

DerivedQuantity _general(bool generalCrossCountry, FlightDuration blockTime) {
  if (!generalCrossCountry) {
    return DerivedQuantity.zero(
      "§61.1(b)(3)(i) 'cross-country time': no landing at a point other "
      'than the point of departure',
    );
  }
  return DerivedQuantity.creditable(
    blockTime,
    "§61.1(b)(3)(i) 'cross-country time': included a landing at a point "
    'other than the point of departure, navigated to by dead reckoning, '
    'pilotage, or a navigation system',
  );
}

/// One of the six purpose-specific credit tests, (ii)-(vii). Each requires,
/// in order: [applies] (the aircraft category this test is written for),
/// [generalCrossCountry] (the flight is cross-country at all, per (i) —
/// every sub-test presupposes this), and finally [furthestNm] exceeding
/// [thresholdNm].
DerivedQuantity _creditTest({
  required String citation,
  required bool applies,
  required String exclusionReason,
  required bool generalCrossCountry,
  required double? furthestNm,
  required double thresholdNm,
  required FlightDuration blockTime,
}) {
  if (!applies) {
    return DerivedQuantity.zero('$citation: does not apply — $exclusionReason');
  }
  if (!generalCrossCountry) {
    return DerivedQuantity.zero(
      '$citation: no landing away from the point of departure, so this is '
      'not cross-country time at all',
    );
  }
  if (furthestNm == null) {
    return DerivedQuantity.notCreditable(
      FlightDuration.zero,
      '$citation: distance from the point of departure could not be '
      'computed — no other waypoint resolved to a position',
    );
  }
  if (furthestNm > thresholdNm) {
    return DerivedQuantity.creditable(
      blockTime,
      '$citation: furthest landing ${furthestNm.toStringAsFixed(1)} NM '
      'from the point of departure, more than $thresholdNm NM required',
    );
  }
  return DerivedQuantity.zero(
    '$citation: furthest landing ${furthestNm.toStringAsFixed(1)} NM from '
    'the point of departure, needs more than $thresholdNm NM',
  );
}
