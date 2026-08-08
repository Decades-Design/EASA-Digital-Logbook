import 'jurisdiction_profile.dart';

/// Resolves a [JurisdictionProfile] id to its fully-merged rule set, walking
/// the `extends` chain.
class JurisdictionRegistry {
  JurisdictionRegistry(Iterable<JurisdictionProfile> profiles)
    : _byId = {for (final profile in profiles) profile.id: profile};

  final Map<String, JurisdictionProfile> _byId;

  /// Flattens [id]'s `extends` chain into one [ResolvedJurisdictionProfile],
  /// root first so a child's own rules always win over anything it
  /// inherits — the same precedence CLAUDE.md's `overrides:` example
  /// implies.
  ///
  /// Throws [ArgumentError] naming the missing id if [id] or anything in its
  /// chain is not registered, and [StateError] naming the repeated id if the
  /// chain cycles — either is a configuration bug in the profile data, not a
  /// state this should silently resolve around.
  ResolvedJurisdictionProfile resolve(String id) {
    final chain = <JurisdictionProfile>[];
    final seen = <String>{};
    String? current = id;
    while (current != null) {
      if (!seen.add(current)) {
        throw StateError(
          'Jurisdiction profile inheritance cycle involving "$current"',
        );
      }
      final profile = _byId[current];
      if (profile == null) {
        throw ArgumentError.value(
          id,
          'id',
          'no registered jurisdiction profile "$current"',
        );
      }
      chain.add(profile);
      current = profile.extendsId;
    }

    final rules = <String, String>{};
    for (final profile in chain.reversed) {
      rules.addAll(profile.rules);
    }
    return ResolvedJurisdictionProfile(id: id, rules: rules);
  }
}
