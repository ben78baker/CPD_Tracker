import 'dart:io';

import 'package:cpd_tracker/utils/attachment_io.dart';
import 'package:cpd_tracker/utils/export_attachment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory documentsDirectory;

  setUp(() {
    documentsDirectory = Directory.systemTemp.createTempSync(
      'cpd_export_attachments_',
    );
  });

  tearDown(() {
    if (documentsDirectory.existsSync()) {
      documentsDirectory.deleteSync(recursive: true);
    }
  });

  Future<String> resolveFromTestDocuments(String stored) async {
    return resolveStoredPathForDocumentsDirectory(
      stored,
      documentsDirectory.path,
    );
  }

  group('ExportAttachment URL classification', () {
    test('classifies HTTP URLs', () async {
      final attachment = await ExportAttachment.classify(
        'http://example.com/evidence',
      );

      expect(attachment.kind, ExportAttachmentKind.httpUrl);
      expect(attachment.isUrl, isTrue);
    });

    test('classifies HTTPS URLs', () async {
      final attachment = await ExportAttachment.classify(
        'https://example.com/evidence',
      );

      expect(attachment.kind, ExportAttachmentKind.httpsUrl);
      expect(attachment.isUrl, isTrue);
    });

    test('classifies mailto URLs', () async {
      final attachment = await ExportAttachment.classify(
        'mailto:evidence@example.com',
      );

      expect(attachment.kind, ExportAttachmentKind.mailtoUrl);
      expect(attachment.isUrl, isTrue);
    });

    test('classifies tel URLs', () async {
      final attachment = await ExportAttachment.classify('tel:+441234567890');

      expect(attachment.kind, ExportAttachmentKind.telUrl);
      expect(attachment.isUrl, isTrue);
    });
  });

  group('ExportAttachment local evidence classification', () {
    test('classifies an existing local image', () async {
      final stored = p.join('attachments', 'photo.JPG');
      final resolved = resolveStoredPathForDocumentsDirectory(
        stored,
        documentsDirectory.path,
      );
      File(resolved).createSync(recursive: true);

      final attachment = await ExportAttachment.classify(
        stored,
        pathResolver: resolveFromTestDocuments,
      );

      expect(attachment.kind, ExportAttachmentKind.localImage);
      expect(attachment.resolvedPath, resolved);
      expect(attachment.isAvailableLocal, isTrue);
    });

    test('classifies an existing local non-image file', () async {
      final stored = p.join('attachments', 'certificate.pdf');
      final resolved = resolveStoredPathForDocumentsDirectory(
        stored,
        documentsDirectory.path,
      );
      File(resolved).createSync(recursive: true);

      final attachment = await ExportAttachment.classify(
        stored,
        pathResolver: resolveFromTestDocuments,
      );

      expect(attachment.kind, ExportAttachmentKind.localFile);
      expect(attachment.resolvedPath, resolved);
      expect(attachment.isAvailableLocal, isTrue);
    });

    test('represents missing local evidence explicitly', () async {
      const stored = 'attachments/missing.pdf';

      final attachment = await ExportAttachment.classify(
        stored,
        pathResolver: resolveFromTestDocuments,
      );

      expect(attachment.kind, ExportAttachmentKind.missingLocal);
      expect(attachment.resolvedPath, p.join(documentsDirectory.path, stored));
      expect(attachment.isAvailableLocal, isFalse);
    });
  });

  group('stored attachment path resolution', () {
    test('resolves an app-relative attachment path', () {
      const stored = 'attachments/photo.jpg';

      final resolved = resolveStoredPathForDocumentsDirectory(
        stored,
        documentsDirectory.path,
      );

      expect(resolved, p.join(documentsDirectory.path, stored));
    });

    test('rebases a legacy Documents path into the current container', () {
      const stored =
          '/var/mobile/Containers/Data/Application/OLD/Documents/'
          'attachments/legacy.pdf';

      final resolved = resolveStoredPathForDocumentsDirectory(
        stored,
        documentsDirectory.path,
      );

      expect(
        resolved,
        p.join(documentsDirectory.path, 'attachments', 'legacy.pdf'),
      );
    });
  });
}
