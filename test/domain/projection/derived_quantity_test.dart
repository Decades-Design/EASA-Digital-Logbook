// flutter_test re-exports test/group/expect from package:test_api, so plain
// Dart tests need no separate package:test dependency.
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/projection/derived_quantity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DerivedQuantity factories', () {
    test('creditable carries the value and marks it reliable', () {
      final quantity = DerivedQuantity.creditable(
        const FlightDuration(90),
        'command authority held',
      );
      expect(quantity.value, const FlightDuration(90));
      expect(quantity.creditable, isTrue);
      expect(quantity.explanation, 'command authority held');
    });

    test(
      'notCreditable keeps a real, non-zero value while marking it unreliable',
      () {
        // The whole reason this type exists: PICUS pending countersignature
        // is neither silently 0 nor silently valid.
        final quantity = DerivedQuantity.notCreditable(
          const FlightDuration(90),
          'PICUS awaiting countersignature',
        );
        expect(quantity.value, const FlightDuration(90));
        expect(quantity.creditable, isFalse);
      },
    );

    test('zero is creditable and carries FlightDuration.zero', () {
      final quantity = DerivedQuantity.zero('not the sole manipulator');
      expect(quantity.value, FlightDuration.zero);
      expect(quantity.creditable, isTrue);
    });
  });
}
