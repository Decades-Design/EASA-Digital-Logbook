/// Regenerates `test/fixtures/pdf/amc1_fcl050_golden.pdf` (#79) — the
/// reference `amc1_fcl050_determinism_test.dart` compares every export
/// against. Run this only after a deliberate, reviewed change to the
/// AMC1 FCL.050 layout; a golden file that moves silently defeats the
/// whole point of the golden test.
///
/// Shells out to `flutter test` rather than running the generator
/// directly: `buildAmc1Fcl050Logbook` loads font assets via `rootBundle`,
/// which needs a Flutter test binding to resolve — `dart run` alone
/// can't provide one, the same reason `check_schema_snapshot.dart`
/// shells out to `flutter pub run drift_dev` instead of running it
/// in-process.
///
/// Run: `dart run tool/regenerate_amc1_fcl050_golden_pdf.dart`
library;

import 'dart:io';

Future<void> main() async {
  final result = await Process.run('flutter', [
    'test',
    'test/export/amc1_fcl050_golden_writer.dart',
  ], runInShell: true);

  stdout.write(result.stdout);
  stderr.write(result.stderr);

  if (result.exitCode != 0) {
    stderr.writeln(
      'regenerate_amc1_fcl050_golden_pdf: failed to regenerate the golden '
      'PDF.',
    );
    exit(1);
  }

  stdout.writeln(
    'regenerate_amc1_fcl050_golden_pdf: wrote '
    'test/fixtures/pdf/amc1_fcl050_golden.pdf — review the diff (e.g. open '
    'it and compare on paper) before committing.',
  );
}
