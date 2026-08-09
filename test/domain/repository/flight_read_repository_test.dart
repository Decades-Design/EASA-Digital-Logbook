import 'package:easa_digital_log/domain/model/calendar_date.dart';
import 'package:easa_digital_log/domain/repository/flight_read_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FlightQuery', () {
    test('defaults to no filters', () {
      const query = FlightQuery();
      expect(query.from, isNull);
      expect(query.to, isNull);
      expect(query.aircraftId, isNull);
      expect(query.aerodromeIdentifier, isNull);
      expect(query.capacity, isNull);
    });

    test('equal by value', () {
      const a = FlightQuery(aircraftId: 'a1', from: CalendarDate(2026, 1, 1));
      const b = FlightQuery(aircraftId: 'a1', from: CalendarDate(2026, 1, 1));
      expect(a, b);
    });
  });

  group('CapacityFilter', () {
    test('equal by value', () {
      const a = CapacityFilter(commandAuthority: true);
      const b = CapacityFilter(commandAuthority: true);
      expect(a, b);
    });

    test('defaults to no filters', () {
      const filter = CapacityFilter();
      expect(filter.commandAuthority, isNull);
      expect(filter.actingAsInstructor, isNull);
    });
  });
}
