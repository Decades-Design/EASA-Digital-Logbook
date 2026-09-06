import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/primitives/default_primitives.dart';
import '../../domain/projection/jurisdiction_projection.dart';
import 'aerodrome_providers.dart';
import 'jurisdiction_providers.dart';

/// The FAA projection, unconditionally — #70's own instruction ("Derived
/// values computed via the FAA projection, since ForeFlight is FAA-shaped")
/// applies regardless of which licence the pilot actually holds.
/// `jurisdictionProjectionsProvider` only ever builds a projection for a
/// jurisdiction backed by a held rating, which would leave a pilot with no
/// FAA licence unable to export at all — this bypasses that filter and
/// resolves `us.faa.part61` directly from the registry, since a
/// `JurisdictionProjection`'s computation needs nothing more than a
/// resolvable profile id.
final faaProjectionProvider = FutureProvider<JurisdictionProjection>((
  ref,
) async {
  final registry = await ref.watch(jurisdictionRegistryProvider.future);
  final aerodromes = await ref.watch(aerodromeDirectoryProvider.future);
  return JurisdictionProjection(
    registry: registry,
    primitives: defaultPrimitives,
    aerodromes: aerodromes,
    jurisdictionId: 'us.faa.part61',
  );
});
