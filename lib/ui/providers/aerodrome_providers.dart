import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/model/aerodrome_directory.dart';

/// The bundled OurAirports dataset, loaded once. `cache: false` — see
/// `jurisdiction_registry_provider.dart`'s note on why.
final aerodromeDirectoryProvider = FutureProvider<AerodromeDirectory>((
  ref,
) async {
  final csv = await rootBundle.loadString(
    'assets/aerodromes/airports.csv',
    cache: false,
  );
  return AerodromeDirectory.fromOurAirportsCsv(csv);
});
