import 'package:drift/native.dart';
import 'package:easa_digital_log/data/database.dart';
import 'package:easa_digital_log/domain/jurisdiction/jurisdiction_registry.dart';
import 'package:easa_digital_log/domain/model/aerodrome_directory.dart';
import 'package:easa_digital_log/domain/primitives/default_primitives.dart';
import 'package:easa_digital_log/domain/projection/jurisdiction_projection.dart';
import 'package:easa_digital_log/domain/projection/projection.dart';
import 'package:easa_digital_log/domain/repository/flight_read_repository.dart';
import 'package:easa_digital_log/ui/io/amc1_fcl050_export_screen.dart';
import 'package:easa_digital_log/ui/providers/database_provider.dart';
import 'package:easa_digital_log/ui/providers/easa_export_providers.dart';
import 'package:easa_digital_log/ui/providers/repository_providers.dart';
import 'package:easa_digital_log/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A minimal fake, same convention as `export_screen_test.dart`'s own
/// `_FakeFlightReadRepository` — this screen only ever calls `watchFlights`
/// and `watchDrafts` (via `buildAmc1Fcl050ExportPlan`), so everything else
/// is unreachable and just throws if that ever changes without this fake
/// being noticed.
class _FakeFlightReadRepository implements FlightReadRepository {
  @override
  Stream<List<ProjectedFlight>> watchFlights({
    required Projection projection,
    FlightQuery query = const FlightQuery(),
  }) => Stream.value(const []);

  @override
  Stream<List<FlightRecord>> watchDrafts() => Stream.value(const []);

  @override
  Future<ProjectedFlight?> find(
    String flightId, {
    required Projection projection,
  }) => throw UnimplementedError();

  @override
  Future<FlightRecord?> findDraft(String flightId) =>
      throw UnimplementedError();

  @override
  Future<FlightHistory?> revisionHistory(String flightId) =>
      throw UnimplementedError();
}

void main() {
  final fakeEasaProjection = JurisdictionProjection(
    registry: JurisdictionRegistry(const []),
    primitives: defaultPrimitives,
    aerodromes: AerodromeDirectory(const []),
    jurisdictionId: 'eu.easa.part-fcl',
  );

  testWidgets('renders the date pickers and both export buttons', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        easaProjectionProvider.overrideWith((ref) async => fakeEasaProjection),
        flightReadRepositoryProvider.overrideWithValue(
          _FakeFlightReadRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Amc1Fcl050ExportScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('From'), findsOneWidget);
    expect(find.text('To'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
    expect(find.text('Export & Seal'), findsOneWidget);
  });
}
