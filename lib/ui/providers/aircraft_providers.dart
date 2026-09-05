import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/aircraft_repository.dart';
import 'repository_providers.dart';

/// Every stored aircraft, active and archived alike (#61) — the management
/// screen partitions the list itself; see `AircraftRepository.watchAll`'s
/// own dartdoc for why filtering doesn't belong here.
final aircraftRecordsProvider = StreamProvider<List<AircraftRecord>>((ref) {
  return ref.watch(aircraftRepositoryProvider).watchAll();
});
