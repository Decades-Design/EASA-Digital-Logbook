import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/primitives/default_primitives.dart';
import '../../domain/projection/jurisdiction_projection.dart';
import 'aerodrome_providers.dart';
import 'jurisdiction_providers.dart';

/// The EASA projection, unconditionally — mirrors
/// `foreflight_export_providers.dart`'s `faaProjectionProvider` exactly,
/// same reasoning: the AMC1 FCL.050 export is EASA-shaped regardless of
/// which licence the pilot actually holds primarily, and
/// `jurisdictionProjectionsProvider` only builds projections for
/// jurisdictions backed by a held rating, which would leave a pilot with
/// no EASA rating unable to export at all.
final easaProjectionProvider = FutureProvider<JurisdictionProjection>((
  ref,
) async {
  final registry = await ref.watch(jurisdictionRegistryProvider.future);
  final aerodromes = await ref.watch(aerodromeDirectoryProvider.future);
  return JurisdictionProjection(
    registry: registry,
    primitives: defaultPrimitives,
    aerodromes: aerodromes,
    jurisdictionId: 'eu.easa.part-fcl',
  );
});
