/// Enforces the layering rule from CLAUDE.md: `lib/domain/` is pure Dart and
/// must never reach for Flutter, the filesystem, the rendering layer, or an
/// outer layer of this package.
///
/// Run: `dart run tool/check_layering.dart [path]`
/// Exits 0 when clean or when the target directory does not exist yet.
library;

import 'dart:io';

/// Import/export URI prefixes that `lib/domain/` may not depend on.
///
/// Extend this list rather than adding special cases below.
const List<String> bannedPrefixes = <String>[
  // Flutter itself, and the test harness that drags it in.
  'package:flutter/',
  'package:flutter_test/',
  // Platform, host and concurrency machinery. `dart:isolate` is on this list
  // deliberately: a domain computation that wants an isolate wants a caller
  // that owns one, not an isolate of its own.
  'dart:io',
  'dart:ui',
  'dart:ffi',
  'dart:isolate',
  'dart:developer',
  'dart:mirrors',
  'dart:cli',
  'dart:html',
  'dart:js',
  // Cross-layer: domain/ is the innermost layer and depends on nothing
  // outward. See the architecture diagram in CLAUDE.md.
  'package:easa_digital_log/data/',
  'package:easa_digital_log/io/',
  'package:easa_digital_log/export/',
  'package:easa_digital_log/ui/',
];

const String defaultTarget = 'lib/domain';

/// Path segment that marks the root of the domain tree, used to decide whether
/// a relative import climbs out of it.
const String _domainSegment = 'domain';

/// File suffixes the walk skips.
///
/// `analysis_options.yaml` excludes generated code from analysis for the same
/// reason: it is not ours to lint, it is gitignored, and CI regenerates it
/// before this guard runs. See ADR-0006.
const List<String> generatedSuffixes = <String>['.freezed.dart', '.g.dart'];

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

/// Matches a line comment or a block comment — whichever opens first.
///
/// The single alternation is load-bearing. The engine tries the alternatives
/// left to right at each position, so `// toggle: /*` is consumed as a line
/// comment (its `/*` never opens a block) and `/* a // b */` is consumed as a
/// block comment. Stripping one kind before the other — in *either* order —
/// lets the loser swallow real code: block-first turns a `/*` inside a `//`
/// comment into an opener that deletes every directive up to the next `*/`.
final RegExp _comment = RegExp(r'//[^\n]*|/\*[\s\S]*?\*/');

/// Matches a whole `import`/`export` directive, from the keyword at the start
/// of a line through to its terminating `;`.
///
/// `[^;]*` spans newlines, so a directive `dart format` has wrapped over
/// several physical lines is still matched as one unit, and every URI it names
/// is visible to [_urisIn].
final RegExp _directive = RegExp(
  r'^[ \t]*(?:import|export)\b[^;]*;',
  multiLine: true,
);

/// Matches one string literal, raw or plain, single- or double-quoted.
final RegExp _quoted = RegExp(r'''r?'([^']*)'|r?"([^"]*)"''');

/// Replaces comments with blanks, preserving line breaks so violation line
/// numbers still point at the real line.
String _stripComments(String source) => source.replaceAllMapped(
  _comment,
  (match) => '\n' * '\n'.allMatches(match.group(0)!).length,
);

/// Returns every URI a directive [span] names.
///
/// A directive can name more than one URI — `import 'stub.dart' if
/// (dart.library.io) 'dart:io';` names two, and only the second is banned. A
/// single URI can also be written as several adjacent string literals, which
/// Dart concatenates: `'dart:' 'io'` *is* `dart:io`. Literals separated by
/// nothing but whitespace are therefore joined; anything between them starts a
/// new URI.
List<String> _urisIn(String span) {
  final uris = <String>[];
  final current = StringBuffer();
  var previousEnd = -1;

  for (final match in _quoted.allMatches(span)) {
    final isAdjacent =
        previousEnd >= 0 &&
        span.substring(previousEnd, match.start).trim().isEmpty;
    if (!isAdjacent && current.isNotEmpty) {
      uris.add(current.toString());
      current.clear();
    }
    current.write(match.group(1) ?? match.group(2)!);
    previousEnd = match.end;
  }
  if (current.isNotEmpty) {
    uris.add(current.toString());
  }

  return uris;
}

/// Whether a relative [uri] climbs out of the domain tree containing
/// [filePath]. A package-qualified or `dart:` URI is not relative and is
/// handled by [bannedPrefixes] instead.
///
/// When [filePath] has no `domain` segment the file's own directory is treated
/// as the root, so any climb counts as an escape. That is the conservative
/// reading, which is the right one for a guard.
bool _escapesDomain(String uri, String filePath) {
  if (uri.contains(':')) {
    return false;
  }

  final directories = filePath.replaceAll(r'\', '/').split('/')..removeLast();
  final domainIndex = directories.lastIndexOf(_domainSegment);
  var depth = domainIndex < 0 ? 0 : directories.length - domainIndex - 1;

  for (final segment in uri.split('/')) {
    if (segment == '..') {
      depth--;
      if (depth < 0) {
        return true;
      }
    } else if (segment.isNotEmpty && segment != '.') {
      depth++;
    }
  }

  return false;
}

/// Returns every banned import or export in [source].
///
/// Comments are stripped first, so a commented-out import is not a violation.
/// Both `import` and `export` are checked — a re-export reintroduces the
/// dependency just as effectively.
///
/// Known limitations, both accepted trade-offs of matching syntactically
/// instead of depending on `package:analyzer`:
/// - A banned import or export written inside a multi-line string literal
///   (e.g. a triple-quoted Dart string whose own line reads like an import
///   directive) is reported as a violation. This is a known false positive,
///   not desired behaviour — the guard fails closed, so a false positive
///   breaks the build and a human looks, which is the safe direction.
/// - For the same reason, a comment delimiter inside a string literal
///   (`const s = '/*';`) is read as a real delimiter.
List<Violation> findViolations(String filePath, String source) {
  final stripped = _stripComments(source);
  final violations = <Violation>[];

  for (final directive in _directive.allMatches(stripped)) {
    final line =
        '\n'.allMatches(stripped.substring(0, directive.start)).length + 1;

    for (final uri in _urisIn(directive.group(0)!)) {
      final isBanned =
          bannedPrefixes.any(uri.startsWith) || _escapesDomain(uri, filePath);
      if (isBanned) {
        violations.add(Violation(filePath: filePath, line: line, uri: uri));
      }
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
    if (entity is! File || !entity.path.endsWith('.dart')) {
      continue;
    }
    if (generatedSuffixes.any(entity.path.endsWith)) {
      continue;
    }
    violations.addAll(findViolations(entity.path, entity.readAsStringSync()));
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
