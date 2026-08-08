import 'package:yaml/yaml.dart';

/// One authority's declarative profile, as written in
/// `assets/jurisdictions/*.yaml` — CLAUDE.md: "Authorities are declarative
/// profiles... resolved through a registry," never a Dart class or an enum
/// value per authority.
///
/// This is the profile *as authored in one file*: its own rules, plus a
/// pointer to what it [extends], if anything. It is not yet resolved — a
/// profile that extends another does not carry the parent's rules until
/// [JurisdictionRegistry.resolve] walks the chain. See
/// [ResolvedJurisdictionProfile] for the flattened result.
class JurisdictionProfile {
  const JurisdictionProfile({
    required this.id,
    this.extendsId,
    required this.rules,
  });

  /// e.g. `eu.easa.part-fcl`, `us.faa.part61`, `uk.caa.part-fcl`.
  final String id;

  /// The parent profile's [id], or `null` for a root profile. UK Part-FCL
  /// extending EASA is CLAUDE.md's own example of why this exists — a fix
  /// to the shared EASA lineage lands in one place rather than two.
  final String? extendsId;

  /// Rule-name to primitive-id mappings this profile declares or overrides,
  /// e.g. `{'pic_rule': 'easa.pilot_function_time'}`. For a profile with no
  /// [extendsId], these are its complete rules; for one that extends another,
  /// these are only the deltas — see [JurisdictionRegistry.resolve] for how
  /// the two are merged.
  final Map<String, String> rules;
}

/// A [JurisdictionProfile] with its whole `extends` chain flattened into one
/// rule set — what [PrimitiveRegistry] lookups actually read. Never
/// constructed directly; see [JurisdictionRegistry.resolve].
class ResolvedJurisdictionProfile {
  const ResolvedJurisdictionProfile({required this.id, required this.rules});

  final String id;
  final Map<String, String> rules;

  /// The primitive id registered under [ruleName], or `null` if this
  /// profile's chain never set it — e.g. `night_rule` before #21/#22 give
  /// EASA and FAA anything to reference there.
  String? operator [](String ruleName) => rules[ruleName];
}

/// Parses one `assets/jurisdictions/*.yaml` document into a
/// [JurisdictionProfile].
///
/// A root profile's rules are its top-level keys, besides `id`. A profile
/// that `extends` another puts its deltas under `overrides:` instead —
/// CLAUDE.md's own worked example:
/// ```yaml
/// id: uk.caa.part-fcl
/// extends: eu.easa.part-fcl
/// overrides:
///   currency_rules: [uk.fcl060.passenger_recency]
/// ```
/// so a reader can tell "this profile's own rules" apart from "everything it
/// inherits" without cross-referencing the parent file.
JurisdictionProfile parseJurisdictionProfileYaml(String yamlContent) {
  final yaml = loadYaml(yamlContent);
  if (yaml is! YamlMap) {
    throw FormatException(
      'Jurisdiction profile YAML must be a map',
      yamlContent,
    );
  }

  final id = yaml['id'];
  if (id is! String || id.isEmpty) {
    throw FormatException(
      'Jurisdiction profile is missing a non-empty "id"',
      yamlContent,
    );
  }

  final extendsId = yaml['extends'];
  if (extendsId != null && extendsId is! String) {
    throw FormatException(
      'Jurisdiction profile "$id": "extends" must be a string if present',
      yamlContent,
    );
  }

  final Object? rulesSource = extendsId == null ? yaml : yaml['overrides'];
  final rules = <String, String>{};
  if (rulesSource is YamlMap) {
    for (final entry in rulesSource.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key == 'id' || key == 'extends' || key == 'overrides') {
        continue;
      }
      if (key is! String || value is! String) {
        throw FormatException(
          'Jurisdiction profile "$id": rule "$key" must map a string name '
          'to a string primitive id',
          yamlContent,
        );
      }
      rules[key] = value;
    }
  } else if (extendsId != null && rulesSource != null) {
    throw FormatException(
      'Jurisdiction profile "$id": "overrides" must be a map if present',
      yamlContent,
    );
  }

  return JurisdictionProfile(
    id: id,
    extendsId: extendsId as String?,
    rules: rules,
  );
}
