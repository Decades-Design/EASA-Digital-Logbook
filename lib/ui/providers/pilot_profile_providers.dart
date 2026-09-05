import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/pilot_record/held_aircraft_qualification.dart';
import '../../domain/pilot_record/held_rating.dart';
import '../../domain/pilot_record/pilot_profile.dart';
import 'repository_providers.dart';

/// The single pilot profile this installation holds — `null` until one has
/// ever been saved (a fresh install, before any onboarding/Settings flow
/// writes one). CLAUDE.md scopes this app to one pilot; see
/// `PilotProfileRepository`'s own dartdoc for the singleton-row rationale.
final pilotProfileProvider = FutureProvider<PilotProfile?>((ref) {
  return ref.watch(pilotProfileRepositoryProvider).find();
});

/// Every rating/certificate the pilot currently holds, across every
/// jurisdiction — the real counterpart to `sample_currency_data.dart`'s
/// `sampleCurrencyLicences`. Distinct [HeldRating.jurisdictionId] values
/// across this list are "which jurisdictions this pilot holds a licence
/// under," used wherever a screen needs that set (e.g. a flight's
/// cross-jurisdiction divergence check) rather than a separate stored list.
final heldRatingsProvider = FutureProvider<List<HeldRating>>((ref) {
  return ref.watch(heldRatingRepositoryProvider).findAll();
});

/// Every aircraft-feature qualification (type rating aside — see
/// [heldRatingsProvider]) the pilot currently holds, across every
/// jurisdiction — the entry form's #105 qualification-gap check reads this
/// alongside [heldRatingsProvider] rather than each screen querying the
/// repository directly.
final heldAircraftQualificationsProvider =
    FutureProvider<List<HeldAircraftQualification>>((ref) {
      return ref.watch(heldAircraftQualificationRepositoryProvider).findAll();
    });
