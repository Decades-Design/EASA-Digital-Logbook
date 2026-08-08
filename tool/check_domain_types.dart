/// Enforces the storage rule from CLAUDE.md rule 3: every persisted instant
/// is UTC. `DateTime.isUtc` is trivially lost, so `lib/domain/` may not name
/// `DateTime` at all — see [findBannedTypes] for why the ban is blunt rather
/// than a narrower field-position match.
///
/// Run: `dart run tool/check_domain_types.dart [path]`
/// Exits 0 when clean or when the target directory does not exist yet.
library;

import 'dart:io';

import 'dart_source.dart';

/// Identifiers `lib/domain/` may not name. Extend this list rather than
/// adding special cases.
///
/// `DateTime` is banned outright — not merely as a field type. Rule 3 of
/// CLAUDE.md and ADR-0002 require every stored instant to be UTC, and
/// `DateTime.isUtc` is trivially lost. The blunt form also catches
/// `DateTime.now()`, which is nondeterminism the domain layer should not
/// have either. Issue #11 extends this list with derived-quantity names.
const List<String> bannedIdentifiers = <String>['DateTime'];

/// Files permitted to name a banned identifier, with the reason.
///
/// These two are the wrapper and its display companion: they exist precisely
/// to be the only place in `lib/domain/` that touches `DateTime`, so that
/// nothing else has to.
const List<String> allowlist = <String>[
  'lib/domain/model/utc_instant.dart',
  'lib/domain/model/wall_clock.dart',
];

const String defaultTarget = 'lib/domain';

/// File suffixes the walk skips. See `check_layering.dart`'s matching
/// constant and ADR-0006.
const List<String> generatedSuffixes = <String>['.freezed.dart', '.g.dart'];

/// A banned identifier found in a domain file.
class TypeViolation {
  const TypeViolation({
    required this.filePath,
    required this.line,
    required this.identifier,
  });

  final String filePath;
  final int line;
  final String identifier;

  @override
  String toString() => '$filePath:$line  names $identifier';
}

/// Normalises Windows-style separators to `/` so a path can be compared
/// against [allowlist] regardless of which platform produced it.
String _normalise(String path) => path.replaceAll(r'\', '/');

/// Whether [filePath] is exactly one of the [allowlist] entries once
/// normalised — an exact suffix match, not `contains`, so a lookalike file
/// name (`utc_instant_helper.dart`) is not allowlisted by accident.
bool _isAllowlisted(String filePath) {
  final normalised = _normalise(filePath);
  return allowlist.any((entry) => normalised.endsWith(entry));
}

/// Returns every occurrence of a [bannedIdentifiers] name in [source], one
/// [TypeViolation] per occurrence, unless [filePath] is on [allowlist].
///
/// Comments are stripped first via [stripComments], so a commented-out
/// mention is not a violation. Each identifier is matched on a word
/// boundary (`\bDateTime\b`), so `UtcDateTimeHolder` and `myDateTime` do not
/// match — only the bare identifier does, in any position: field, parameter,
/// return type, generic argument, or a static call like `DateTime.now()`.
///
/// This guard has no notion of string literals or dartdoc code fences, so
/// the word `DateTime` written inside a string or inside a documentation
/// example is reported as a violation. That is a known, accepted
/// **fail-closed** false positive: it breaks the build, a human looks, and
/// nothing slips through — which is the correct bias for a guard, and the
/// reason this blunt whole-identifier match was chosen over a narrower
/// type-position match (field types, parameter types, return types only)
/// that would need to special-case every syntactic position a type can
/// appear in and would fail open on whichever one was missed. See the
/// matching discussion on `findViolations` in `check_layering.dart` for the
/// sibling guard's version of the same trade-off.
List<TypeViolation> findBannedTypes(String filePath, String source) {
  if (_isAllowlisted(filePath)) {
    return <TypeViolation>[];
  }

  final stripped = stripComments(source);
  final violations = <TypeViolation>[];

  for (final identifier in bannedIdentifiers) {
    final pattern = RegExp('\\b$identifier\\b');
    for (final match in pattern.allMatches(stripped)) {
      final line =
          '\n'.allMatches(stripped.substring(0, match.start)).length + 1;
      violations.add(
        TypeViolation(filePath: filePath, line: line, identifier: identifier),
      );
    }
  }

  violations.sort((a, b) => a.line.compareTo(b.line));
  return violations;
}

void main(List<String> args) {
  final target = args.isNotEmpty ? args.first : defaultTarget;
  final directory = Directory(target);

  if (!directory.existsSync()) {
    stdout.writeln(
      'check_domain_types: $target does not exist yet — nothing to check.',
    );
    exit(0);
  }

  final violations = <TypeViolation>[];
  for (final entity in directory.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) {
      continue;
    }
    if (generatedSuffixes.any(entity.path.endsWith)) {
      continue;
    }
    violations.addAll(findBannedTypes(entity.path, entity.readAsStringSync()));
  }

  if (violations.isEmpty) {
    stdout.writeln('check_domain_types: $target is clean.');
    exit(0);
  }

  stderr.writeln(
    'check_domain_types: ${violations.length} banned identifier(s):',
  );
  for (final violation in violations) {
    stderr.writeln('  $violation');
  }
  stderr.writeln('');
  stderr.writeln(
    'lib/domain/ must never name a raw DateTime. See CLAUDE.md rule 3 and '
    'ADR-0002.',
  );
  exit(1);
}
