/// Enforces the layering rule from CLAUDE.md: `lib/domain/` is pure Dart and
/// must never reach for Flutter, the filesystem, or the rendering layer.
///
/// Run: `dart run tool/check_layering.dart [path]`
/// Exits 0 when clean or when the target directory does not exist yet.
library;

import 'dart:io';

/// Import/export URI prefixes that `lib/domain/` may not depend on.
///
/// Extend this list rather than adding special cases below.
const List<String> bannedPrefixes = <String>[
  'package:flutter/',
  'dart:io',
  'dart:ui',
];

const String defaultTarget = 'lib/domain';

/// A banned directive found in a domain file.
class Violation {
  const Violation({
    required this.filePath,
    required this.line,
    required this.uri,
  });

  final String filePath;
  final int line;
  final String uri;

  @override
  String toString() => '$filePath:$line  imports $uri';
}

final RegExp _blockComment = RegExp(r'/\*.*?\*/', dotAll: true);
final RegExp _directive = RegExp(
  '''^\\s*(?:import|export)\\s+['"]([^'"]+)['"]''',
);

/// Returns every banned import or export in [source].
///
/// Block and line comments are stripped first, so a commented-out import is
/// not a violation. Both `import` and `export` are checked — a re-export
/// reintroduces the dependency just as effectively.
List<Violation> findViolations(String filePath, String source) {
  final withoutBlockComments = source.replaceAll(_blockComment, '');
  final lines = withoutBlockComments.split('\n');
  final violations = <Violation>[];

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trimLeft().startsWith('//')) {
      continue;
    }

    final match = _directive.firstMatch(line);
    if (match == null) {
      continue;
    }

    final uri = match.group(1)!;
    final isBanned = bannedPrefixes.any(uri.startsWith);
    if (isBanned) {
      violations.add(Violation(filePath: filePath, line: i + 1, uri: uri));
    }
  }

  return violations;
}

void main(List<String> args) {
  final target = args.isNotEmpty ? args.first : defaultTarget;
  final directory = Directory(target);

  if (!directory.existsSync()) {
    stdout.writeln(
      'check_layering: $target does not exist yet — nothing to check.',
    );
    exit(0);
  }

  final violations = <Violation>[];
  for (final entity in directory.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      violations.addAll(findViolations(entity.path, entity.readAsStringSync()));
    }
  }

  if (violations.isEmpty) {
    stdout.writeln('check_layering: $target is clean.');
    exit(0);
  }

  stderr.writeln('check_layering: ${violations.length} layering violation(s):');
  for (final violation in violations) {
    stderr.writeln('  $violation');
  }
  stderr.writeln('');
  stderr.writeln('lib/domain/ must be pure Dart. See CLAUDE.md and ADR-0001.');
  exit(1);
}
