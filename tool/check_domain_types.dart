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

/// Whether [filePath], once normalised, is *exactly* one of the [allowlist]
/// entries — full-path equality, not a suffix match of any kind.
///
/// A character-level suffix match (`String.endsWith`) is bypassable two
/// ways, neither of which requires touching the wrapper file's own name:
///
/// - a directory prefix that happens to end in the right characters, e.g.
///   `xlib/domain/model/utc_instant.dart` ends with
///   `lib/domain/model/utc_instant.dart` as raw characters;
/// - a nested path that repeats the allowlisted path as a trailing
///   *segment* sequence, e.g.
///   `lib/domain/foo/lib/domain/model/utc_instant.dart`.
///
/// The second case is also why splitting on `/` and comparing only the
/// *trailing* segments is not a sufficient fix on its own: in that example
/// the trailing four segments are still exactly `lib`, `domain`, `model`,
/// `utc_instant.dart`, immediately preceded by a `/`, so a rule that merely
/// requires a path separator (or the start of the string) before the match
/// cannot tell it apart from the real file. Only requiring the *entire*
/// normalised path to equal the entry admits neither bypass.
///
/// [allowlist] entries are each file's canonical path from the repository
/// root, which is exactly the (relative) path this guard's own [main] walk
/// produces when invoked with the default, relative [defaultTarget]. An
/// absolute path therefore does not match and is — conservatively,
/// fail-closed — treated as not allowlisted rather than silently accepted.
/// That is a robustness margin, not a live gap: nothing in this file invokes
/// the walk with an absolute path today.
bool _isAllowlisted(String filePath) =>
    allowlist.contains(_normalise(filePath));

/// Returns every occurrence of a [bannedIdentifiers] name in [source], one
/// [TypeViolation] per occurrence, unless [filePath] is on [allowlist].
///
/// Comments are stripped first via [stripComments], so a commented-out
/// mention is not a violation. Each identifier is matched on a word
/// boundary (`\bDateTime\b`), so `UtcDateTimeHolder` and `myDateTime` do not
/// match — only the bare identifier does, in any position: field, parameter,
/// return type, generic argument, or a static call like `DateTime.now()`.
///
/// Both limitations below are accepted trade-offs of matching syntactically
/// instead of depending on `package:analyzer` (see ADR-0001) — the same
/// trade-off `findViolations` in `check_layering.dart` makes, for the same
/// reason. They are not the same kind of trade-off, though — one is safe and
/// one is not:
///
/// - **Fails closed (safe).** This guard has no notion of string literals or
///   dartdoc code fences, so the word `DateTime` written inside a string or
///   inside a documentation example is reported as a violation. This is a
///   known false positive, not desired behaviour, but it over-reports: it
///   breaks the build, a human looks, and no real violation slips through.
///   This is also why the blunt whole-identifier match was chosen over a
///   narrower type-position match (field types, parameter types, return
///   types only): the narrower match would need to special-case every
///   syntactic position a type can appear in and would fail *open* on
///   whichever one was missed, which is the unsafe direction.
/// - **Fails open (unsafe, accepted gap).** [stripComments] has no notion of
///   string literals either, so a `/*` sequence sitting inside a string
///   literal opens a *real* block comment that swallows everything up to the
///   next `*/` — including a genuine, undeclared `DateTime`:
///   ```dart
///   const String trap = '/*';
///   final DateTime when = DateTime.now(); // never reported — "inside a comment"
///   /* a totally unrelated, later, legitimate block comment */
///   ```
///   `when` is a real raw `DateTime` reaching `lib/domain/`, but this guard
///   reports the file as clean. It is a known, accepted gap, not an
///   oversight — closing it needs `package:analyzer`, which is excluded (see
///   ADR-0001) — and a `lib/domain/` file must never be assumed free of a
///   raw `DateTime` merely because this guard passed. See the identical gap,
///   with its own worked example, on `findViolations` in
///   `check_layering.dart`, and the fail-open pin in
///   `test/tool/check_layering_test.dart` — `check_domain_types_test.dart`
///   pins this guard's own instance of the same gap alongside it.
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
