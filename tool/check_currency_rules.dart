/// Validates every `assets/rules/*.yaml` file two independent ways — #40's
/// "JSON Schema published and validated in CI against every rule file":
/// against `assets/rules/schema/currency-rule.schema.json`, and against the
/// Dart parser (`lib/domain/currency/currency_rule_yaml.dart`), which is the
/// real enforcement at load time (#41). A file that fails either is a build
/// failure, not a runtime surprise.
///
/// Run: `dart run tool/check_currency_rules.dart`
library;

import 'dart:convert';
import 'dart:io';

import 'package:easa_digital_log/domain/currency/currency_rule_yaml.dart';
import 'package:json_schema/json_schema.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

const String rulesDirectory = 'assets/rules';
const String schemaPath = 'assets/rules/schema/currency-rule.schema.json';

void main() {
  final directory = Directory(rulesDirectory);
  if (!directory.existsSync()) {
    stdout.writeln(
      'check_currency_rules: $rulesDirectory does not exist yet — '
      'nothing to check.',
    );
    exit(0);
  }

  final schema = JsonSchema.create(File(schemaPath).readAsStringSync());

  final ruleFiles =
      directory
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.yaml'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  final failures = <String>[];
  for (final file in ruleFiles) {
    final relativePath = p.relative(file.path);
    final content = file.readAsStringSync();

    try {
      parseCurrencyRuleYaml(content);
    } on FormatException catch (e) {
      failures.add('$relativePath: Dart parser rejected it — $e');
      continue;
    }

    final plain = jsonDecode(jsonEncode(loadYaml(content)));
    final result = schema.validate(plain);
    if (!result.isValid) {
      for (final error in result.errors) {
        failures.add('$relativePath: schema violation — $error');
      }
    }
  }

  if (failures.isEmpty) {
    stdout.writeln(
      'check_currency_rules: ${ruleFiles.length} rule file(s) clean.',
    );
    exit(0);
  }

  stderr.writeln('check_currency_rules: ${failures.length} violation(s):');
  for (final failure in failures) {
    stderr.writeln('  $failure');
  }
  exit(1);
}
