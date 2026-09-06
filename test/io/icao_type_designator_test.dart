import 'package:easa_digital_log/io/icao_type_designator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a real two-to-four character alphanumeric code passes', () {
    expect(looksLikeIcaoTypeDesignator('C152'), isTrue);
    expect(looksLikeIcaoTypeDesignator('C172'), isTrue);
    expect(looksLikeIcaoTypeDesignator('A320'), isTrue);
    expect(looksLikeIcaoTypeDesignator('P28A'), isTrue);
    expect(looksLikeIcaoTypeDesignator('B2'), isTrue);
  });

  test('a hyphenated variant suffix, embedded spaces, or lowercase fails', () {
    expect(looksLikeIcaoTypeDesignator('M20J-201'), isFalse);
    expect(looksLikeIcaoTypeDesignator('BEECH V35B TN'), isFalse);
    expect(looksLikeIcaoTypeDesignator('c152'), isFalse);
    expect(looksLikeIcaoTypeDesignator(''), isFalse);
    expect(looksLikeIcaoTypeDesignator('TOOLONG5'), isFalse);
  });
}
