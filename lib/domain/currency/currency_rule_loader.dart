import '../model/calendar_date.dart';
import 'currency_rule.dart';
import 'currency_rule_yaml.dart';

/// Resolves a [CurrencyRule.id] plus an evaluation date to the exact
/// version of that rule in force on that date — #41: "a flight in 2019
/// must be evaluated against the rule in force in 2019", regardless of how
/// many times the regulation has changed since.
///
/// Parsing (`parseCurrencyRuleYaml`) and version resolution are kept
/// separate, the same split `JurisdictionRegistry` makes from
/// `parseJurisdictionProfileYaml`: this class works on already-parsed
/// [CurrencyRule]s, so it stays pure Dart with no file or asset I/O of its
/// own — reading `assets/rules/*.yaml` is the caller's concern (`lib/data/`
/// or app start-up), not the domain layer's.
class CurrencyRuleLoader {
  /// Groups [rules] by [CurrencyRule.id], sorted oldest-first within each
  /// group, validating for the errors #41 requires caught at load time
  /// rather than at evaluation:
  ///
  /// Throws [StateError] naming the id and date if two versions of the same
  /// rule share an [CurrencyRule.effectiveFrom] — an unresolvable ambiguity,
  /// since nothing then says which one governs that date.
  CurrencyRuleLoader(Iterable<CurrencyRule> rules) : _byId = {} {
    for (final rule in rules) {
      (_byId[rule.id] ??= []).add(rule);
    }
    for (final entry in _byId.entries) {
      entry.value.sort((a, b) => a.effectiveFrom.compareTo(b.effectiveFrom));
      for (var i = 1; i < entry.value.length; i++) {
        if (entry.value[i].effectiveFrom == entry.value[i - 1].effectiveFrom) {
          throw StateError(
            'Currency rule "${entry.key}" has two versions both effective '
            'from ${entry.value[i].effectiveFrom}',
          );
        }
      }
    }
  }

  /// Parses [yamlContents] — one YAML document per rule file — via
  /// [parseCurrencyRuleYaml], propagating the first [FormatException]
  /// immediately rather than loading the rest first: #41's "malformed rule
  /// files fail loudly at startup, not silently at evaluation" means the
  /// whole app should refuse to start, not limp along with a partial rule
  /// set.
  factory CurrencyRuleLoader.fromYaml(Iterable<String> yamlContents) {
    return CurrencyRuleLoader([
      for (final content in yamlContents) parseCurrencyRuleYaml(content),
    ]);
  }

  final Map<String, List<CurrencyRule>> _byId;

  /// Every loaded version of rule [id], oldest first. Empty if [id] is
  /// unknown — superseded versions are never dropped from this list, per
  /// #41's "superseded rules retained, never deleted".
  List<CurrencyRule> versionsOf(String id) =>
      List.unmodifiable(_byId[id] ?? const []);

  /// The version of rule [id] in force on [evaluationDate] — the latest
  /// version with [CurrencyRule.effectiveFrom] `<=` [evaluationDate].
  ///
  /// Throws [ArgumentError] naming [id] if no version of it was ever
  /// loaded, and [StateError] if every known version's
  /// [CurrencyRule.effectiveFrom] is after [evaluationDate] — the rule did
  /// not exist yet on that date, which is a data or caller error, not a
  /// state to silently fall back from.
  CurrencyRule resolve(String id, CalendarDate evaluationDate) {
    final versions = _byId[id];
    if (versions == null) {
      throw ArgumentError('No currency rule loaded under id "$id"');
    }

    CurrencyRule? inForce;
    for (final version in versions) {
      if (version.effectiveFrom <= evaluationDate) {
        inForce = version;
      } else {
        break; // sorted oldest-first — nothing later can match either.
      }
    }
    if (inForce == null) {
      throw StateError(
        'Currency rule "$id" had no version in force on $evaluationDate — '
        'the earliest known version takes effect '
        '${versions.first.effectiveFrom}',
      );
    }
    return inForce;
  }

  /// Every loaded rule id's in-force version as of [evaluationDate] — one
  /// resolved [CurrencyRule] per id, for a caller building a dashboard
  /// across every rule rather than asking about one specific id.
  List<CurrencyRule> allInForce(CalendarDate evaluationDate) => [
    for (final id in _byId.keys) resolve(id, evaluationDate),
  ];
}
