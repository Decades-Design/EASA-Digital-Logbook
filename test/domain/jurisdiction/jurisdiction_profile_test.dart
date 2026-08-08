// flutter_test re-exports test/group/expect from package:test_api, so plain
// Dart tests need no separate package:test dependency.
import 'package:easa_digital_log/domain/jurisdiction/jurisdiction_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseJurisdictionProfileYaml', () {
    test('parses a root profile\'s top-level keys as rules', () {
      final profile = parseJurisdictionProfileYaml('''
id: eu.easa.part-fcl
pic_rule: easa.pilot_function_time
''');

      expect(profile.id, 'eu.easa.part-fcl');
      expect(profile.extendsId, isNull);
      expect(profile.rules, {'pic_rule': 'easa.pilot_function_time'});
    });

    test(
      'parses an extending profile\'s overrides, ignoring top-level noise',
      () {
        final profile = parseJurisdictionProfileYaml('''
id: uk.caa.part-fcl
extends: eu.easa.part-fcl
overrides:
  pic_rule: uk.pilot_function_time
''');

        expect(profile.id, 'uk.caa.part-fcl');
        expect(profile.extendsId, 'eu.easa.part-fcl');
        expect(profile.rules, {'pic_rule': 'uk.pilot_function_time'});
      },
    );

    test('an extending profile with no overrides has empty rules', () {
      final profile = parseJurisdictionProfileYaml('''
id: uk.caa.part-fcl
extends: eu.easa.part-fcl
''');

      expect(profile.rules, isEmpty);
    });

    test('rejects a document with no id', () {
      expect(
        () =>
            parseJurisdictionProfileYaml('pic_rule: easa.pilot_function_time'),
        throwsFormatException,
      );
    });

    test('rejects a rule value that is not a string', () {
      expect(
        () => parseJurisdictionProfileYaml('''
id: eu.easa.part-fcl
pic_rule:
  nested: true
'''),
        throwsFormatException,
      );
    });
  });
}
