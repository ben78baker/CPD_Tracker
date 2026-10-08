import 'attachment_io.dart';

enum ExportAttachmentKind {
  localImage,
  localPdf,
  localFile,
  httpUrl,
  httpsUrl,
  mailtoUrl,
  telUrl,
  missingLocal,
}

typedef ExportAttachmentPathResolver = Future<String> Function(String stored);
typedef ExportAttachmentPathExists = bool Function(String path);

/// Export-only interpretation of a legacy attachment string.
///
/// This does not alter the persisted `CpdEntry.attachments` representation.
class ExportAttachment {
  const ExportAttachment._({
    required this.storedValue,
    required this.kind,
    this.resolvedPath,
    this.uri,
  });

  static Future<ExportAttachment> classify(
    String storedValue, {
    ExportAttachmentPathResolver? pathResolver,
    ExportAttachmentPathExists? pathExists,
  }) async {
    final trimmed = storedValue.trim();
    final uri = Uri.tryParse(trimmed);

    switch (uri?.scheme.toLowerCase()) {
      case 'http':
        return ExportAttachment._(
          storedValue: storedValue,
          kind: ExportAttachmentKind.httpUrl,
          uri: uri,
        );
      case 'https':
        return ExportAttachment._(
          storedValue: storedValue,
          kind: ExportAttachmentKind.httpsUrl,
          uri: uri,
        );
      case 'mailto':
        return ExportAttachment._(
          storedValue: storedValue,
          kind: ExportAttachmentKind.mailtoUrl,
          uri: uri,
        );
      case 'tel':
        return ExportAttachment._(
          storedValue: storedValue,
          kind: ExportAttachmentKind.telUrl,
          uri: uri,
        );
    }

    final resolve = pathResolver ?? resolveStoredPath;
    final exists = pathExists ?? fileExists;
    final resolvedPath = await resolve(storedValue);
    if (!exists(resolvedPath)) {
      return ExportAttachment._(
        storedValue: storedValue,
        kind: ExportAttachmentKind.missingLocal,
        resolvedPath: resolvedPath,
      );
    }

    return ExportAttachment._(
      storedValue: storedValue,
      kind: isImagePath(resolvedPath)
          ? ExportAttachmentKind.localImage
          : resolvedPath.toLowerCase().endsWith('.pdf')
          ? ExportAttachmentKind.localPdf
          : ExportAttachmentKind.localFile,
      resolvedPath: resolvedPath,
    );
  }

  final String storedValue;
  final ExportAttachmentKind kind;
  final String? resolvedPath;
  final Uri? uri;

  bool get isUrl => switch (kind) {
    ExportAttachmentKind.httpUrl ||
    ExportAttachmentKind.httpsUrl ||
    ExportAttachmentKind.mailtoUrl ||
    ExportAttachmentKind.telUrl => true,
    _ => false,
  };

  bool get isAvailableLocal => switch (kind) {
    ExportAttachmentKind.localImage ||
    ExportAttachmentKind.localPdf ||
    ExportAttachmentKind.localFile => true,
    _ => false,
  };
}
