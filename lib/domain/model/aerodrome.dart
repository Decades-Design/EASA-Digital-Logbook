import 'package:freezed_annotation/freezed_annotation.dart';

import 'geo_coordinate.dart';

part 'aerodrome.freezed.dart';

/// An aerodrome a flight can depart from or arrive at.
///
/// [icaoCode] and [iataCode] are both nullable — not every place a pilot
/// flies from has either. #14's acceptance criteria are explicit that this
/// is not an edge case: plenty of GA flying happens from private strips and
/// unlicensed grass fields no dataset knows about, and the app must be able
/// to record a flight there with only a name and a position.
@freezed
abstract class Aerodrome with _$Aerodrome {
  const factory Aerodrome({
    String? icaoCode,
    String? iataCode,
    required String name,
    required GeoCoordinate position,

    /// Feet AMSL. Null where the source dataset doesn't record it — mainly
    /// very small or closed sites.
    int? elevationFt,

    /// ISO 3166-1 alpha-2, e.g. `US`, `GB`. Free text rather than an enum:
    /// the dataset carries ~250 of these and the app has no rule that
    /// branches on a closed set of them today.
    String? isoCountry,
  }) = _Aerodrome;
}
