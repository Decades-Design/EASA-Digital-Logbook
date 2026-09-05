import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/aerodromes/aerodrome_summary.dart';
import '../../domain/model/aerodrome.dart';
import 'aerodrome_providers.dart';
import 'flight_records_providers.dart';
import 'repository_providers.dart';

/// Every pilot-defined aerodrome (#63) — folded into
/// `AerodromeDirectory.search`'s `extra` parameter alongside the bundled
/// OurAirports dataset.
final customAerodromesProvider = StreamProvider<List<Aerodrome>>((ref) {
  return ref.watch(customAerodromeRepositoryProvider).watchAll();
});

/// ICAO codes touched by the pilot's own flights, most-recently-flown-to
/// first (#63's "recent" ranking).
final recentAerodromeCodesProvider = FutureProvider<List<String>>((
  ref,
) async {
  final flights = await ref.watch(allFlightRecordsProvider.future);
  return rankAerodromesByRecency(flights);
});

/// ICAO codes touched by the pilot's own flights, most-visited first (#63's
/// "frequent" ranking).
final frequentAerodromeCodesProvider = FutureProvider<List<String>>((
  ref,
) async {
  final flights = await ref.watch(allFlightRecordsProvider.future);
  final directory = await ref.watch(aerodromeDirectoryProvider.future);
  final visits = rankAerodromesByVisits(flights, directory);
  return [for (final visit in visits) visit.icao];
});
