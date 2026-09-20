import 'dart:io';

import 'package:easa_digital_log/export/amc1_fcl050_layout.dart';
import 'package:flutter_test/flutter_test.dart';

import 'amc1_fcl050_golden_fixture.dart';
import 'pdf_bytes_normalization.dart';

/// #79's acceptance criteria. `package:pdf` 3.13.0 (our pinned version,
/// also the latest on pub.dev) computes the `/ID` trailer entry from
/// `DateTime.now()` plus 32 bytes of `Random.secure()` — deliberate
/// security hardening added in 3.11.2, with no public constructor
/// parameter or setter to override it. That field carries no visible
/// content (a file-identity tag, not anything printed), so
/// [normalizeNonDeterministicBytes] blanks exactly that one field before
/// every comparison here — "byte-identical" in this suite means
/// identical apart from that field, which is the only bar the underlying
/// library actually lets us clear.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('no embedded generation timestamp', () async {
    final document = await buildAmc1Fcl050Logbook(
      holderName: amc1Fcl050GoldenHolderName,
      holderLicenceNumber: amc1Fcl050GoldenHolderLicenceNumber,
      rows: amc1Fcl050GoldenRows(),
    );
    final bytes = await document.save();

    // /CreationDate is only ever written inside a PdfInfo object, which
    // `pw.Document()` only creates when given a title/author/producer/etc
    // — buildAmc1Fcl050Logbook passes none, so no PdfInfo, no timestamp.
    expect(String.fromCharCodes(bytes), isNot(contains('/CreationDate')));
  });

  test('building the same export twice produces byte-identical output, aside '
      "from the PDF's own random file-identity tag", () async {
    Future<List<int>> build() async {
      final document = await buildAmc1Fcl050Logbook(
        holderName: amc1Fcl050GoldenHolderName,
        holderLicenceNumber: amc1Fcl050GoldenHolderLicenceNumber,
        rows: amc1Fcl050GoldenRows(),
      );
      return document.save();
    }

    final first = normalizeNonDeterministicBytes(await build());
    final second = normalizeNonDeterministicBytes(await build());

    expect(first, equals(second));
  });

  test('matches the committed golden PDF, aside from the file-identity tag — '
      'regenerate deliberately with '
      'dart run tool/regenerate_amc1_fcl050_golden_pdf.dart', () async {
    final document = await buildAmc1Fcl050Logbook(
      holderName: amc1Fcl050GoldenHolderName,
      holderLicenceNumber: amc1Fcl050GoldenHolderLicenceNumber,
      rows: amc1Fcl050GoldenRows(),
    );
    final fresh = normalizeNonDeterministicBytes(await document.save());

    final goldenFile = File('test/fixtures/pdf/amc1_fcl050_golden.pdf');
    final golden = normalizeNonDeterministicBytes(
      await goldenFile.readAsBytes(),
    );

    expect(fresh, equals(golden));
  });
}
