import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/jurisdiction/jurisdiction_profile.dart';
import '../../domain/jurisdiction/jurisdiction_registry.dart';
import 'pilot_profile_providers.dart';

/// Every jurisdiction profile this app ships, loaded once. `cache: false` —
/// `rootBundle`'s process-wide cache otherwise returns a permanently-pending
/// `Future` to a later widget-test run that reopens a screen depending on
/// this provider (the same note `NewFlightScreen._loadJurisdictions` and
/// every screen's own former `_load()` carried before this provider existed).
final jurisdictionRegistryProvider = FutureProvider<JurisdictionRegistry>((
  ref,
) async {
  final results = await Future.wait([
    rootBundle.loadString(
      'assets/jurisdictions/eu.easa.part-fcl.yaml',
      cache: false,
    ),
    rootBundle.loadString(
      'assets/jurisdictions/us.faa.part61.yaml',
      cache: false,
    ),
  ]);
  return JurisdictionRegistry([
    for (final yaml in results) parseJurisdictionProfileYaml(yaml),
  ]);
});

/// The jurisdiction Totals/Currency/Logbook default to — the pilot's
/// [PilotProfile.primaryJurisdictionId] once one exists, else `null` (no
/// profile saved yet; a screen falls back to its own sensible default
/// rather than this provider guessing one, per CLAUDE.md's "never guess a
/// missing discriminator" rule applied one level up).
final primaryJurisdictionIdProvider = FutureProvider<String?>((ref) async {
  final profile = await ref.watch(pilotProfileProvider.future);
  return profile?.primaryJurisdictionId;
});
