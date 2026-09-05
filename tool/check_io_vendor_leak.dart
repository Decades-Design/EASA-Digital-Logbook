/// #68: CLAUDE.md's Import/export section — "never let a vendor's field
/// naming leak past `io/`" — enforced as a build guard rather than a review
/// habit. A vendor-specific identifier (a ForeFlight/Garmin type, constant
/// or column name) has no business appearing in `domain/`, `data/` or
/// `ui/`: those layers see [CanonicalImportRow]/[Flight]/[Aircraft], never
/// a vendor's own shape.
///
/// Matches syntactically rather than depending on `package:analyzer` (see
/// ADR-0001), the same trade-off `check_layering.dart` documents: comments
/// are stripped first (this project's own docs and dartdocs legitimately
/// *explain* a design decision by naming ForeFlight/Garmin — see
/// `Aircraft`'s own dartdoc — and that is not a leak), but a vendor name
/// inside a string literal — a user-facing label like `'Imported from
/// ForeFlight'` — still counts as a violation. That is a deliberate,
/// accepted over-report: the fix is to hoist the label into `lib/io/` as a
/// named constant the UI imports, not to special-case string literals here
/// and risk a real leak slipping through disguised as one.
///
/// Run: `dart run tool/check_io_vendor_leak.dart`
library;

import 'dart:io';

import 'dart_source.dart';

/// Vendor names banned outside [_ioSegment]. Deliberately narrow and
/// name-based rather than "every vendor CSV import concept" — a generic
/// term like `logbook` or `csv` is not a leak, a proper noun naming one
/// specific format is. Extend this list as new vendors are added (#69
/// ForeFlight, #71 Garmin), never widen the matching strategy to guess at
/// vendors not yet named here.
const List<String> bannedVendorNames = <String>['ForeFlight', 'Garmin'];

/// Path segment marking the exempt tree — vendor-specific code is exactly
/// what lives here.
const String _ioSegment = 'io';

const String _sourceTarget = 'lib';

/// A banned vendor name found outside `lib/io/`.
class VendorLeak {
  const VendorLeak({
    required this.filePath,
    required this.line,
    required this.vendorName,
  });

  final String filePath;
  final int line;
  final String vendorName;

  @override
  String toString() => '$filePath:$line  names "$vendorName"';
}

/// Whether [filePath] sits inside the exempt `lib/io/` tree.
bool _isExempt(String filePath) {
  final segments = filePath.replaceAll(r'\', '/').split('/');
  return segments.contains(_ioSegment);
}

/// Returns every banned vendor name [source] mentions, outside comments.
///
/// A plain, case-sensitive substring match against each name's own
/// proper-noun capitalisation — deliberately *not* bounded by `\b` on
/// either side. Dart identifiers concatenate words with no separator
/// (`ForeFlightAdapter`, `GarminCsvRow`), so a trailing `\b` would let
/// exactly the class names a real adapter uses slip past a check meant to
/// catch them. `foreflight` lowercased inside a sentence explaining *why*
/// a rule exists still reads differently from `ForeFlight` used as an
/// identifier or a label, and case sensitivity alone draws that line.
List<VendorLeak> findVendorLeaks(String filePath, String source) {
  filePath = filePath.replaceAll(r'\', '/');
  if (_isExempt(filePath)) return const [];

  final stripped = stripComments(source);
  final leaks = <VendorLeak>[];

  for (final vendorName in bannedVendorNames) {
    final pattern = RegExp(RegExp.escape(vendorName));
    for (final match in pattern.allMatches(stripped)) {
      final line =
          '\n'.allMatches(stripped.substring(0, match.start)).length + 1;
      leaks.add(
        VendorLeak(filePath: filePath, line: line, vendorName: vendorName),
      );
    }
  }

  return leaks;
}

void main() {
  final directory = Directory(_sourceTarget);
  if (!directory.existsSync()) {
    stdout.writeln(
      'check_io_vendor_leak: $_sourceTarget does not exist yet — nothing to check.',
    );
    exit(0);
  }

  final leaks = <VendorLeak>[];
  for (final entity in directory.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (entity.path.endsWith('.freezed.dart') ||
        entity.path.endsWith('.g.dart')) {
      continue;
    }
    leaks.addAll(findVendorLeaks(entity.path, entity.readAsStringSync()));
  }

  if (leaks.isEmpty) {
    stdout.writeln(
      'check_io_vendor_leak: no vendor-specific identifier outside lib/io/.',
    );
    exit(0);
  }

  stderr.writeln('check_io_vendor_leak: ${leaks.length} leak(s):');
  for (final leak in leaks) {
    stderr.writeln('  $leak');
  }
  stderr.writeln('');
  stderr.writeln(
    'CLAUDE.md: "Never let a vendor\'s field naming past io/." Map into '
    'CanonicalImportRow/Flight/Aircraft inside lib/io/ and have the rest of '
    'the app read that instead.',
  );
  exit(1);
}
