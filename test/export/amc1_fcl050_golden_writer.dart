import 'dart:io';

import 'package:easa_digital_log/export/amc1_fcl050_layout.dart';
import 'package:flutter_test/flutter_test.dart';

import 'amc1_fcl050_golden_fixture.dart';

/// Regenerates `test/fixtures/pdf/amc1_fcl050_golden.pdf` from the shared
/// fixture (#79). Deliberately named without a `_test.dart` suffix so
/// `flutter test` (and CI) never picks it up on its own — run it only
/// via `dart run tool/regenerate_amc1_fcl050_golden_pdf.dart`, after a
/// genuine, reviewed layout change.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('write the AMC1 FCL.050 golden PDF', () async {
    final document = await buildAmc1Fcl050Logbook(
      holderName: amc1Fcl050GoldenHolderName,
      holderLicenceNumber: amc1Fcl050GoldenHolderLicenceNumber,
      rows: amc1Fcl050GoldenRows(),
    );
    final bytes = await document.save();

    final file = File('test/fixtures/pdf/amc1_fcl050_golden.pdf');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    // ignore: avoid_print
    print('Wrote ${file.path} (${bytes.length} bytes).');
  });
}
