import 'package:easa_digital_log/domain/currency/currency_dashboard.dart';
import 'package:easa_digital_log/domain/currency/currency_rule_loader.dart';
import 'package:easa_digital_log/domain/currency/evaluation_subject.dart';
import 'package:easa_digital_log/domain/currency/held_record.dart';
import 'package:easa_digital_log/domain/model/calendar_date.dart';
import 'package:flutter_test/flutter_test.dart';

const _asOf = CalendarDate(2024, 6, 1);

String _ruleYaml({
  required String id,
  required String jurisdiction,
  required String heldRecordKind,
}) =>
    '''
id: $id
jurisdiction: $jurisdiction
citation: "test citation"
title: "Test rule $id"
effective_from: 2011-01-01
requirement:
  kind: held_record_currently_valid
  held_record_kind: $heldRecordKind
''';

void main() {
  late CurrencyRuleLoader loader;

  setUp(() {
    loader = CurrencyRuleLoader.fromYaml([
      _ruleYaml(
        id: 'test.satisfied.far',
        jurisdiction: 'eu.easa.part-fcl',
        heldRecordKind: 'far',
      ),
      _ruleYaml(
        id: 'test.satisfied.soon',
        jurisdiction: 'eu.easa.part-fcl',
        heldRecordKind: 'soon',
      ),
      _ruleYaml(
        id: 'test.unsatisfied',
        jurisdiction: 'us.faa.part61',
        heldRecordKind: 'never-held',
      ),
    ]);
  });

  EvaluationSubject subjectWith(List<HeldRecord> records) =>
      EvaluationSubject(flights: const [], heldRecords: records);

  test(
    'a satisfied rule expiring well outside the hero window is not at risk',
    () {
      final dashboard = buildCurrencyDashboard(
        licences: [
          const CurrencyLicenceSpec(
            jurisdictionId: 'eu.easa.part-fcl',
            label: 'EASA',
            isPrimary: true,
            privilegeSummary: 'PPL(A)',
            ruleIds: ['test.satisfied.far'],
          ),
        ],
        loader: loader,
        subject: subjectWith([
          HeldRecord(
            kind: 'far',
            validFrom: CalendarDate(2023, 1, 1),
            validUntil: CalendarDate(2025, 1, 1),
          ),
        ]),
        asOf: _asOf,
      );

      expect(dashboard.groups.single.rows.single.isAtRisk, isFalse);
      expect(dashboard.atRiskRows, isEmpty);
    },
  );

  test('a satisfied rule expiring inside the hero window is at risk', () {
    final dashboard = buildCurrencyDashboard(
      licences: [
        const CurrencyLicenceSpec(
          jurisdictionId: 'eu.easa.part-fcl',
          label: 'EASA',
          isPrimary: true,
          privilegeSummary: 'PPL(A)',
          ruleIds: ['test.satisfied.soon'],
        ),
      ],
      loader: loader,
      subject: subjectWith([
        HeldRecord(
          kind: 'soon',
          validFrom: CalendarDate(2023, 1, 1),
          validUntil: CalendarDate(2024, 6, 20), // 19 days from asOf.
        ),
      ]),
      asOf: _asOf,
      heroLeadDays: 30,
    );

    expect(dashboard.groups.single.rows.single.isAtRisk, isTrue);
    expect(dashboard.atRiskRows, hasLength(1));
  });

  test('an unsatisfied rule is always at risk, even with no expiry date', () {
    final dashboard = buildCurrencyDashboard(
      licences: [
        const CurrencyLicenceSpec(
          jurisdictionId: 'us.faa.part61',
          label: 'FAA',
          isPrimary: false,
          privilegeSummary: 'PPL ASEL',
          ruleIds: ['test.unsatisfied'],
        ),
      ],
      loader: loader,
      subject: subjectWith(const []),
      asOf: _asOf,
    );

    final row = dashboard.groups.single.rows.single;
    expect(row.evaluation.result.satisfied, isFalse);
    expect(row.evaluation.result.expiresOn, isNull);
    expect(row.isAtRisk, isTrue);
  });

  test('grouping preserves licence order and the primary flag', () {
    final dashboard = buildCurrencyDashboard(
      licences: [
        const CurrencyLicenceSpec(
          jurisdictionId: 'eu.easa.part-fcl',
          label: 'EASA',
          isPrimary: true,
          privilegeSummary: 'PPL(A)',
          ruleIds: ['test.satisfied.far'],
        ),
        const CurrencyLicenceSpec(
          jurisdictionId: 'us.faa.part61',
          label: 'FAA',
          isPrimary: false,
          privilegeSummary: 'PPL ASEL',
          ruleIds: ['test.unsatisfied'],
        ),
      ],
      loader: loader,
      subject: subjectWith([
        HeldRecord(
          kind: 'far',
          validFrom: CalendarDate(2023, 1, 1),
          validUntil: CalendarDate(2025, 1, 1),
        ),
      ]),
      asOf: _asOf,
    );

    expect(dashboard.groups, hasLength(2));
    expect(dashboard.groups[0].label, 'EASA');
    expect(dashboard.groups[0].isPrimary, isTrue);
    expect(dashboard.groups[1].label, 'FAA');
    expect(dashboard.groups[1].isPrimary, isFalse);
    // The at-risk row (test.unsatisfied, under FAA) still surfaces after
    // the satisfied EASA one in atRiskRows -- group order, not risk order.
    expect(dashboard.atRiskRows.single.title, 'Test rule test.unsatisfied');
  });
}
