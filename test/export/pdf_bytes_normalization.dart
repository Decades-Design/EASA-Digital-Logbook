/// The one byte range `package:pdf` 3.13.0 cannot be made deterministic —
/// see `amc1_fcl050_determinism_test.dart`'s own dartdoc for why.
final RegExp _idTrailerEntry = RegExp(
  r'/ID\s*\[\s*<[0-9A-Fa-f]*>\s*<[0-9A-Fa-f]*>\s*\]',
);

/// Blanks the PDF's own random `/ID` trailer entry so two otherwise-
/// identical documents compare equal. Operates on the bytes as Latin-1
/// text (a lossless 1:1 byte↔code-unit mapping for the 0-255 range PDF
/// bytes occupy, binary streams included) so a single string replace can
/// reach the trailer without needing to parse the file's structure.
List<int> normalizeNonDeterministicBytes(List<int> bytes) {
  final text = String.fromCharCodes(bytes);
  final normalized = text.replaceAll(_idTrailerEntry, '/ID[<0><0>]');
  return normalized.codeUnits;
}
