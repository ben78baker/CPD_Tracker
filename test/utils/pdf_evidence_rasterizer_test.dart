import 'dart:io';
import 'dart:typed_data';

import 'package:cpd_tracker/utils/pdf_evidence_rasterizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:printing/printing.dart';

void main() {
  late Directory temporaryDirectory;
  late File sourcePdf;

  setUp(() {
    temporaryDirectory = Directory.systemTemp.createTempSync(
      'cpd_pdf_rasterizer_test_',
    );
    sourcePdf = File('${temporaryDirectory.path}/evidence.pdf')
      ..writeAsBytesSync(<int>[37, 80, 68, 70, 45, 116, 101, 115, 116]);
  });

  tearDown(() {
    if (temporaryDirectory.existsSync()) {
      temporaryDirectory.deleteSync(recursive: true);
    }
  });

  test(
    'rasterises portrait and landscape pages sequentially at 200 DPI',
    () async {
      final originalBytes = sourcePdf.readAsBytesSync();
      double? requestedDpi;
      final rasterizer = PrintingCpdPdfEvidenceRasterizer(
        infoLoader: () async => const PrintingInfo(canRaster: true),
        rasterStream: (document, dpi) async* {
          expect(document, originalBytes);
          requestedDpi = dpi;
          yield _solidRaster(
            width: 120,
            height: 180,
            red: 10,
            green: 20,
            blue: 30,
          );
          yield _solidRaster(
            width: 240,
            height: 120,
            red: 40,
            green: 50,
            blue: 60,
          );
        },
      );
      final output = Directory('${temporaryDirectory.path}/operation');

      final pages = await rasterizer.rasterize(
        sourcePath: sourcePdf.path,
        outputDirectory: output,
        outputPrefix: 'record_1_evidence_1',
      );

      expect(requestedDpi, cpdPdfEvidenceDpi);
      expect(pages.map((page) => page.sourcePageNumber), [1, 2]);
      expect(pages.map((page) => (page.pixelWidth, page.pixelHeight)), [
        (120, 180),
        (240, 120),
      ]);
      expect(pages[0].path, endsWith('record_1_evidence_1_page_0001.jpg'));
      expect(pages[1].path, endsWith('record_1_evidence_1_page_0002.jpg'));
      for (final page in pages) {
        final decoded = img.decodeJpg(File(page.path).readAsBytesSync());
        expect(decoded, isNotNull);
        expect(decoded!.width, page.pixelWidth);
        expect(decoded.height, page.pixelHeight);
      }
      expect(sourcePdf.readAsBytesSync(), originalBytes);
    },
  );

  test('JPEG encoding composites transparent PDF areas onto white', () async {
    final rasterizer = PrintingCpdPdfEvidenceRasterizer(
      infoLoader: () async => const PrintingInfo(canRaster: true),
      rasterStream: (_, _) =>
          Stream.value(PdfRaster(1, 1, Uint8List.fromList(<int>[0, 0, 0, 0]))),
    );

    final pages = await rasterizer.rasterize(
      sourcePath: sourcePdf.path,
      outputDirectory: Directory('${temporaryDirectory.path}/white'),
      outputPrefix: 'transparent',
    );
    final decoded = img.decodeJpg(File(pages.single.path).readAsBytesSync())!;
    final pixel = decoded.getPixel(0, 0);

    expect(pixel.r, greaterThanOrEqualTo(250));
    expect(pixel.g, greaterThanOrEqualTo(250));
    expect(pixel.b, greaterThanOrEqualTo(250));
  });

  test('removes partial page files when rasterisation fails', () async {
    final rasterizer = PrintingCpdPdfEvidenceRasterizer(
      infoLoader: () async => const PrintingInfo(canRaster: true),
      rasterStream: (_, _) async* {
        yield _solidRaster(width: 20, height: 30);
        throw const FormatException('corrupt second page');
      },
    );
    final output = Directory('${temporaryDirectory.path}/failed');

    await expectLater(
      rasterizer.rasterize(
        sourcePath: sourcePdf.path,
        outputDirectory: output,
        outputPrefix: 'failed',
      ),
      throwsFormatException,
    );

    expect(output.listSync(), isEmpty);
  });

  test(
    'reports unsupported rasterisation instead of producing empty output',
    () async {
      final rasterizer = PrintingCpdPdfEvidenceRasterizer(
        infoLoader: () async => const PrintingInfo(canRaster: false),
        rasterStream: (_, _) => const Stream<PdfRaster>.empty(),
      );

      await expectLater(
        rasterizer.rasterize(
          sourcePath: sourcePdf.path,
          outputDirectory: Directory('${temporaryDirectory.path}/unsupported'),
          outputPrefix: 'unsupported',
        ),
        throwsUnsupportedError,
      );
    },
  );
}

PdfRaster _solidRaster({
  required int width,
  required int height,
  int red = 120,
  int green = 130,
  int blue = 140,
}) {
  final pixels = Uint8List(width * height * 4);
  for (var index = 0; index < pixels.length; index += 4) {
    pixels[index] = red;
    pixels[index + 1] = green;
    pixels[index + 2] = blue;
    pixels[index + 3] = 255;
  }
  return PdfRaster(width, height, pixels);
}
