import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/aircraft_repository.dart';
import '../../data/repositories/custom_aerodrome_repository.dart';
import '../../data/repositories/flight_read_repository_drift.dart';
import '../../data/repositories/flight_repository_drift.dart';
import '../../data/repositories/held_aircraft_qualification_repository.dart';
import '../../data/repositories/held_rating_repository.dart';
import '../../data/repositories/medical_certificate_repository.dart';
import '../../data/repositories/pilot_profile_repository.dart';
import '../../domain/repository/flight_read_repository.dart';
import '../../domain/repository/flight_repository.dart';
import 'database_provider.dart';

/// Repository providers (#56) — each just closes over [databaseProvider];
/// see `database_provider.dart`'s dartdoc for the conventions these follow.

final flightRepositoryProvider = Provider<FlightRepository>(
  (ref) => DriftFlightRepository(ref.watch(databaseProvider)),
);

final flightReadRepositoryProvider = Provider<FlightReadRepository>(
  (ref) => DriftFlightReadRepository(ref.watch(databaseProvider)),
);

final aircraftRepositoryProvider = Provider<AircraftRepository>(
  (ref) => AircraftRepository(ref.watch(databaseProvider)),
);

final pilotProfileRepositoryProvider = Provider<PilotProfileRepository>(
  (ref) => PilotProfileRepository(ref.watch(databaseProvider)),
);

final heldRatingRepositoryProvider = Provider<HeldRatingRepository>(
  (ref) => HeldRatingRepository(ref.watch(databaseProvider)),
);

final heldAircraftQualificationRepositoryProvider =
    Provider<HeldAircraftQualificationRepository>(
      (ref) => HeldAircraftQualificationRepository(ref.watch(databaseProvider)),
    );

final medicalCertificateRepositoryProvider =
    Provider<MedicalCertificateRepository>(
      (ref) => MedicalCertificateRepository(ref.watch(databaseProvider)),
    );

final customAerodromeRepositoryProvider = Provider<CustomAerodromeRepository>(
  (ref) => CustomAerodromeRepository(ref.watch(databaseProvider)),
);
