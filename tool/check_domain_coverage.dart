/// Enforces issue #7: `lib/domain/` computes the numbers that go in a legal
/// document and is held to a higher bar than the rest of the app — a
/// blanket repo-wide coverage threshold would be gamed by widget tests, so
/// this is scoped to the one layer that matters.
///
/// Run: `dart run tool/check_domain_coverage.dart <path-to-lcov.info> [threshold%]`
/// after `flutter test --coverage` has produced the trace file. Exits 1 if
/// coverage under [defaultTarget] falls below the threshold (default 90%).
library;

import 'dart:io';

const String defaultTarget = 'lib/domain/';
const double defaultThresholdPercent = 90;

/// `analysis_options.yaml` excludes generated code from analysis for the
/// same reason — it is not ours to lint or to hold to a coverage bar. See
/// ADR-0006 and `tool/check_layering.dart`'s own `generatedSuffixes`.
const List<String> generatedSuffixes = <String>['.freezed.dart', '.g.dart'];

/// One `SF:`...`end_of_record` block's totals for a single source file, from
/// an lcov trace file.
class FileCoverage {
  const FileCoverage({
    required this.path,
    required this.linesFound,
    required this.linesHit,
  });

  final String path;
  final int linesFound;
  final int linesHit;
}

/// Parses an lcov trace file (the format `flutter test --coverage` writes to
/// `coverage/lcov.info`) into one [FileCoverage] per `SF:` record.
///
/// Paths are normalised to forward slashes — `flutter test --coverage`
/// writes backslash-separated `SF:` paths on Windows, the same footgun
/// `check_layering.dart` (#98) has for its own reported paths.
///
/// Falls back to counting `DA:` lines directly when a record has no `LF:`/
/// `LH:` summary line, since some lcov producers omit them for a record
/// with zero coverable lines.
List<FileCoverage> parseLcov(String content) {
  final records = <FileCoverage>[];
  String? currentPath;
  var daFound = 0;
  var daHit = 0;
  int? lf;
  int? lh;

  void flush() {
    if (currentPath == null) {
      return;
    }
    records.add(
      FileCoverage(
        path: currentPath!.replaceAll(r'\', '/'),
        linesFound: lf ?? daFound,
        linesHit: lh ?? daHit,
      ),
    );
    currentPath = null;
    daFound = 0;
    daHit = 0;
    lf = null;
    lh = null;
  }

  for (final rawLine in content.split('\n')) {
    final line = rawLine.trim();
    if (line.startsWith('SF:')) {
      currentPath = line.substring(3);
    } else if (line.startsWith('DA:')) {
      final hits = int.parse(line.substring(3).split(',')[1]);
      daFound++;
      if (hits > 0) {
        daHit++;
      }
    } else if (line.startsWith('LF:')) {
      lf = int.parse(line.substring(3));
    } else if (line.startsWith('LH:')) {
      lh = int.parse(line.substring(3));
    } else if (line == 'end_of_record') {
      flush();
    }
  }
  flush(); // Tolerate a trace file that doesn't end with end_of_record.

  return records;
}

/// The records that count toward [target]'s coverage figure: under [target],
/// and not a generated file.
List<FileCoverage> recordsUnder(List<FileCoverage> all, String target) => [
  for (final record in all)
    if (record.path.startsWith(target) &&
        !generatedSuffixes.any(record.path.endsWith))
      record,
];

/// The aggregate percentage across [records], by summed lines — not an
/// average of per-file percentages, so one large well-tested file cannot be
/// outweighed by several tiny untested ones.
double aggregatePercent(List<FileCoverage> records) {
  final linesFound = records.fold<int>(0, (sum, r) => sum + r.linesFound);
  final linesHit = records.fold<int>(0, (sum, r) => sum + r.linesHit);
  return linesFound == 0 ? 100 : (linesHit / linesFound) * 100;
}

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'usage: dart run tool/check_domain_coverage.dart <lcov.info> [threshold%]',
    );
    exit(2);
  }

  final lcovFile = File(args[0]);
  final threshold = args.length > 1
      ? double.parse(args[1])
      : defaultThresholdPercent;

  if (!lcovFile.existsSync()) {
    stderr.writeln(
      'check_domain_coverage: ${args[0]} not found — run `flutter test '
      '--coverage` first.',
    );
    exit(2);
  }

  final all = parseLcov(lcovFile.readAsStringSync());
  final domain = recordsUnder(all, defaultTarget);

  if (domain.isEmpty) {
    stderr.writeln(
      'check_domain_coverage: no coverage records under $defaultTarget — '
      'is the target path right, or did the trace file come from a '
      'partial test run?',
    );
    exit(2);
  }

  final linesFound = domain.fold<int>(0, (sum, r) => sum + r.linesFound);
  final linesHit = domain.fold<int>(0, (sum, r) => sum + r.linesHit);
  final percent = aggregatePercent(domain);

  final summary =
      'check_domain_coverage: $defaultTarget ${percent.toStringAsFixed(1)}% '
      '($linesHit/$linesFound lines) across ${domain.length} file(s), '
      'threshold ${threshold.toStringAsFixed(0)}%.';
  stdout.writeln(summary);

  final summaryPath = Platform.environment['GITHUB_STEP_SUMMARY'];
  if (summaryPath != null) {
    File(summaryPath).writeAsStringSync(
      '### Domain coverage\n\n$summary\n',
      mode: FileMode.append,
    );
  }

  if (percent < threshold) {
    stderr.writeln('check_domain_coverage: below threshold, failing.');
    exit(1);
  }
}
