// flutter_test re-exports test/group/expect from package:test_api, so plain
// Dart tests need no separate package:test dependency.
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/projection/derived_quantity.dart';
import 'package:easa_digital_log/domain/projection/projection_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProjectionResult', () {
    test('looks up a named quantity by []', () {
      final pic = DerivedQuantity.creditable(const FlightDuration(90), 'PIC');
      final result = ProjectionResult(
        jurisdictionId: 'eu.easa.part-fcl',
        quantities: {'pic': pic},
      );

      expect(result['pic'], pic);
    });

    test('an unpopulated name is null, not a missing-key throw', () {
      final result = ProjectionResult(
        jurisdictionId: 'eu.easa.part-fcl',
        quantities: const {},
      );

      expect(result['pic'], isNull);
    });

    test('carries the jurisdiction id the result was computed under', () {
      final result = ProjectionResult(
        jurisdictionId: 'us.faa.part61',
        quantities: const {},
      );

      expect(result.jurisdictionId, 'us.faa.part61');
    });
  });
}
