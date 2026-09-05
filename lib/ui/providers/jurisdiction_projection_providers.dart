import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/primitives/default_primitives.dart';
import '../../domain/projection/jurisdiction_projection.dart';
import 'aerodrome_providers.dart';
import 'jurisdiction_providers.dart';
import 'pilot_profile_providers.dart';

/// One [JurisdictionProjection] per jurisdiction the pilot holds a licence
/// under (distinct `HeldRating.jurisdictionId` values — see
/// `pilot_profile_providers.dart`'s note on why that's the source of truth
/// rather than a separate stored list), keyed by jurisdiction id so a
/// screen's jurisdiction dropdown is a cheap lookup rather than a reload —
/// the same shape every screen's own former `_load()` built by hand.
final jurisdictionProjectionsProvider =
    FutureProvider<Map<String, JurisdictionProjection>>((ref) async {
      final registry = await ref.watch(jurisdictionRegistryProvider.future);
      final aerodromes = await ref.watch(aerodromeDirectoryProvider.future);
      final heldRatings = await ref.watch(heldRatingsProvider.future);
      final jurisdictionIds = {
        for (final rating in heldRatings) rating.jurisdictionId,
      };
      return {
        for (final jurisdictionId in jurisdictionIds)
          jurisdictionId: JurisdictionProjection(
            registry: registry,
            primitives: defaultPrimitives,
            aerodromes: aerodromes,
            jurisdictionId: jurisdictionId,
          ),
      };
    });
