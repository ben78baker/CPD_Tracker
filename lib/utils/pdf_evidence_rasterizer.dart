import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:printing/printing.dart';

const cpdPdfEvidenceDpi = 200.0;
const cpdPdfEvidenceJpegQuality = 95;

class CpdPdfRasterPage {
  const CpdPdfRasterPage({
    required this.path,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.sourcePageNumber,
  });

  final String path;
  final int pixelWidth;
  final int pixelHeight;
  final int sourcePageNumber;
}

abstract interface class CpdPdfEvidenceRasterizer {
  Future<List<CpdPdfRasterPage>> rasterize({
    required String sourcePath,
    required Directory outputDirectory,
    required String outputPrefix,
  });
}

typedef CpdPrintingInfoLoader = Future<PrintingInfo> Function();
typedef CpdPrintingRasterStream =
    Stream<PdfRaster> Function(Uint8List document, double dpi);

/// Rasterises source PDF pages one at a time using the existing native
/// `printing` implementation.
///
/// Each raw RGBA page is converted immediately to a high-quality JPEG. The
/// JPEG encoder composites transparent areas onto white, which matches normal
/// PDF paper rendering and avoids retaining all raw pages in memory.
class PrintingCpdPdfEvidenceRasterizer implements CpdPdfEvidenceRasterizer {
  PrintingCpdPdfEvidenceRasterizer({
    this.dpi = cpdPdfEvidenceDpi,
    this.jpegQuality = cpdPdfEvidenceJpegQuality,
    this.pageTimeout = const Duration(seconds: 60),
    CpdPrintingInfoLoader? infoLoader,
    CpdPrintingRasterStream? rasterStream,
  }) : _infoLoader = infoLoader ?? Printing.info,
       _rasterStream =
           rasterStream ??
           ((document, dpi) => Printing.raster(document, dpi: dpi));

  final double dpi;
  final int jpegQuality;
  final Duration pageTimeout;
  final CpdPrintingInfoLoader _infoLoader;
  final CpdPrintingRasterStream _rasterStream;

  @override
  Future<List<CpdPdfRasterPage>> rasterize({
    required String sourcePath,
    required Directory outputDirectory,
    required String outputPrefix,
  }) async {
    final info = await _infoLoader();
    if (!info.canRaster) {
      throw UnsupportedError('PDF rasterisation is unavailable');
    }

    await outputDirectory.create(recursive: true);
    final sourceBytes = await File(sourcePath).readAsBytes();
    final pages = <CpdPdfRasterPage>[];
    final createdFiles = <File>[];

    try {
      var pageNumber = 0;
      final stream = _rasterStream(sourceBytes, dpi).timeout(pageTimeout);
      await for (final raster in stream) {
        pageNumber++;
        final image = img.Image.fromBytes(
          width: raster.width,
          height: raster.height,
          bytes: raster.pixels.buffer,
          bytesOffset: raster.pixels.offsetInBytes,
          numChannels: 4,
          order: img.ChannelOrder.rgba,
          backgroundColor: img.ColorRgb8(255, 255, 255),
        );
        final jpeg = img.encodeJpg(image, quality: jpegQuality);
        final file = File(
          p.join(
            outputDirectory.path,
            '${outputPrefix}_page_${pageNumber.toString().padLeft(4, '0')}.jpg',
          ),
        );
        await file.writeAsBytes(jpeg, flush: true);
        createdFiles.add(file);
        pages.add(
          CpdPdfRasterPage(
            path: file.path,
            pixelWidth: raster.width,
            pixelHeight: raster.height,
            sourcePageNumber: pageNumber,
          ),
        );
      }

      if (pages.isEmpty) {
        throw const FormatException('PDF contains no renderable pages');
      }
      return List<CpdPdfRasterPage>.unmodifiable(pages);
    } catch (_) {
      for (final file in createdFiles) {
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {
          // The operation directory is also removed by the caller in finally.
        }
      }
      rethrow;
    }
  }
}
