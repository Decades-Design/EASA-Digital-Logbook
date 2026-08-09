import 'dart:convert';
import 'dart:io';

import 'package:easa_digital_log/domain/currency/currency_rule_yaml.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:json_schema/json_schema.dart';
import 'package:yaml/yaml.dart';

/// The exact fields `parseCurrencyRuleYaml` treats as mandatory --
/// duplicated here deliberately, not imported, so this test fails the
/// moment the parser and the published schema drift apart, whichever one
/// changed.
const _parserRequiredFields = [
  'id',
  'jurisdiction',
  'citation',
  'effective_from',
  'requirement',
];

const _validRuleYaml = '''
id: easa.fcl060.passenger_recency
jurisdiction: eu.easa.part-fcl
citation: "FCL.060(b)(1)"
effective_from: 2011-11-08
requirement:
  kind: any_of
  of:
    - kind: flight_event_count
      event: landings
      count: 3
      window: { kind: rolling_days, days: 90 }
      conditions:
        - { kind: aircraft_match, level: same_type_or_class }
    - kind: held_record_currently_valid
      held_record_kind: proficiency_check
''';

/// Converts a `package:yaml` document (whose maps/lists are `YamlMap`/
/// `YamlList`, not plain `Map`/`List`) into plain JSON-compatible values --
/// `json_schema` validates structurally, but its error paths and `oneOf`
/// disambiguation are only exercised against ordinary Dart collections in
/// its own test suite, so round-tripping through `jsonDecode(jsonEncode(_))`
/// (which already knows how to serialise `YamlMap`/`YamlList` as maps and
/// lists) is the safe, known-supported input shape rather than a shortcut.
Object? _toPlain(String yamlContent) =>
    jsonDecode(jsonEncode(loadYaml(yamlContent)));

void main() {
  late JsonSchema schema;

  setUpAll(() {
    final schemaFile = File('assets/rules/schema/currency-rule.schema.json');
    schema = JsonSchema.create(schemaFile.readAsStringSync());
  });

  test('the published schema requires exactly what the parser requires', () {
    expect(schema.requiredProperties, unorderedEquals(_parserRequiredFields));
  });

  test('validates a rule the Dart parser also accepts', () {
    final result = schema.validate(_toPlain(_validRuleYaml));

    expect(result.errors, isEmpty);
    // The schema and the parser are two independent checks of the same
    // input; both must accept it.
    expect(() => parseCurrencyRuleYaml(_validRuleYaml), returnsNormally);
  });

  test('rejects a rule missing a mandatory field', () {
    const missingCitation = '''
id: x
jurisdiction: eu.easa.part-fcl
effective_from: 2011-11-08
requirement:
  kind: held_record_currently_valid
  held_record_kind: x
''';

    final result = schema.validate(_toPlain(missingCitation));

    expect(result.isValid, isFalse);
  });

  test('rejects an unknown top-level field', () {
    const withTypo = '''
id: x
jurisdiction: eu.easa.part-fcl
citation: x
effective_from: 2011-11-08
effectiv_form: 2011-11-08
requirement:
  kind: held_record_currently_valid
  held_record_kind: x
''';

    final result = schema.validate(_toPlain(withTypo));

    expect(result.isValid, isFalse);
  });

  test('rejects a requirement mixing fields from two different kinds', () {
    const mixedKind = '''
id: x
jurisdiction: eu.easa.part-fcl
citation: x
effective_from: 2011-11-08
requirement:
  kind: held_record_currently_valid
  held_record_kind: x
  count: 3
''';

    final result = schema.validate(_toPlain(mixedKind));

    expect(result.isValid, isFalse);
  });
}
