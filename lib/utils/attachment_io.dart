import 'dart:io';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';


bool isImagePath(String p) => p.toLowerCase().endsWith('.png') ||
    p.toLowerCase().endsWith('.jpg') ||
    p.toLowerCase().endsWith('.jpeg') ||
    p.toLowerCase().endsWith('.heic') ||
    p.toLowerCase().endsWith('.gif') ||
    p.toLowerCase().endsWith('.bmp') ||
    p.toLowerCase().endsWith('.webp');

bool isUrl(String s) {
  try {
    final u = Uri.parse(s.trim());
    return u.hasScheme && (u.scheme == 'http' || u.scheme == 'https' || u.scheme == 'mailto' || u.scheme == 'tel');
  } catch (_) {
    return false;
  }
}

/// Very light heuristic: treat common document/image extensions as directly downloadable.
bool isLikelyFileUrl(String s) {
  if (!isUrl(s)) return false;
  final lower = s.toLowerCase();
  const exts = [
    '.pdf', '.png', '.jpg', '.jpeg', '.heic', '.gif', '.bmp', '.webp',
    '.csv', '.txt', '.rtf', '.doc', '.docx', '.ppt', '.pptx', '.xls', '.xlsx'
  ];
  return exts.any((e) => lower.contains(e));
}

String _filenameFromUrl(Uri uri, {String fallbackPrefix = 'download'}) {
  // Prefer last path segment if it looks like a file name
  final seg = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
  if (seg.contains('.') && seg.length <= 200) return seg;
  // Otherwise try a query parameter like ?filename=...
  final qName = uri.queryParameters['filename'] ?? uri.queryParameters['file'] ?? '';
  if (qName.isNotEmpty && qName.contains('.')) return qName;
  // Fallback unique name
  final ts = DateTime.now().millisecondsSinceEpoch;
  return '$fallbackPrefix-$ts';
}

String _extFromContentType(String? ct) {
  if (ct == null) return '';
  final type = ct.toLowerCase();
  if (type.contains('pdf')) return '.pdf';
  if (type.contains('png')) return '.png';
  if (type.contains('jpeg') || type.contains('jpg')) return '.jpg';
  if (type.contains('heic')) return '.heic';
  if (type.contains('gif')) return '.gif';
  if (type.contains('bmp')) return '.bmp';
  if (type.contains('webp')) return '.webp';
  if (type.contains('csv')) return '.csv';
  if (type.contains('plain')) return '.txt';
  if (type.contains('msword')) return '.doc';
  if (type.contains('officedocument.wordprocessingml')) return '.docx';
  if (type.contains('vnd.ms-powerpoint')) return '.ppt';
  if (type.contains('officedocument.presentationml')) return '.pptx';
  if (type.contains('vnd.ms-excel')) return '.xls';
  if (type.contains('officedocument.spreadsheetml')) return '.xlsx';
  return '';
}

Future<void> openUrl(BuildContext context, String s) async {
  final uri = Uri.parse(s.trim());
  if (await canLaunchUrl(uri)) {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open link.')),
      );
    }
  } else {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No app available to open link.')),
    );
  }
}

Future<void> openFile(BuildContext context, String path) async {
  try {
    final res = await OpenFilex.open(path);
    if (!context.mounted) return;
    if (res.type != ResultType.done) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Can't open this file (${res.message}).")),
      );
    }
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Open failed: $e')),
    );
  }
}

bool fileExists(String p) => File(p).existsSync();

Future<String> _currentDocsPath() async {
  final docs = await getApplicationDocumentsDirectory();
  return docs.path;
}

/// Turn an absolute path under Documents into a relative like `attachments/file.ext`.
Future<String> toAppRelative(String absolutePath) async {
  final docsPath = await _currentDocsPath();
  if (absolutePath.startsWith(docsPath)) {
    return p.relative(absolutePath, from: docsPath);
  }
  return absolutePath;
}

/// Resolve a stored path to the current container's absolute path.
/// - URLs: returned unchanged
/// - Absolute paths with `/Documents/`: rebase onto current Documents dir
/// - Relative paths: joined to current Documents dir
Future<String> resolveStoredPath(String stored) async {
  if (isUrl(stored)) return stored;
  final docsPath = await _currentDocsPath();
  if (stored.startsWith('/')) {
    final i = stored.indexOf('/Documents/');
    if (i != -1) {
      final tail = stored.substring(i + '/Documents/'.length);
      return p.join(docsPath, tail);
    }
    return stored; // some other absolute path
  }
  return p.join(docsPath, stored);
}

/// Ensure and return the app's attachments directory inside Documents.
Future<Directory> getAppAttachmentsDir() async {
  final docs = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(docs.path, 'attachments'));
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  return dir;
}

/// Copy a local file into the app's attachments directory and return the new path.
/// If [preferredName] is supplied it will be used (sanitized) for the filename; otherwise
/// we derive it from the source path. A timestamp is appended to avoid collisions.
Future<String> copyLocalToAppDir(String sourcePath, {String? preferredName}) async {
  final dir = await getAppAttachmentsDir();
  final baseNoExt = preferredName != null && preferredName.isNotEmpty
      ? _sanitizeFileName(p.basenameWithoutExtension(preferredName))
      : _sanitizeFileName(p.basenameWithoutExtension(sourcePath));
  final ext = p.extension(preferredName?.isNotEmpty == true ? preferredName! : sourcePath);
  final ts = DateTime.now().millisecondsSinceEpoch;
  final destPath = p.join(dir.path, '${baseNoExt}_$ts$ext');
  await File(sourcePath).copy(destPath);
  return await toAppRelative(destPath);
}

/// Import an attachment (local path or URL) into the app's attachments directory.
/// Returns the saved local path, or null on failure. Shows a SnackBar on error.
Future<String?> importAttachmentToApp(BuildContext context, String attachment, {String? displayName}) async {
  try {
    if (isUrl(attachment)) {
      // For URLs, try to download if it looks like a file. Otherwise just open in browser.
      if (isLikelyFileUrl(attachment)) {
        return await downloadToAppDir(context, attachment);
      } else {
        await openUrl(context, attachment);
        return null;
      }
    }

    // Local path — copy into app dir if it exists
    if (fileExists(attachment)) {
      final saved = await copyLocalToAppDir(attachment, preferredName: displayName);
      if (!context.mounted) return saved;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved to Attachments: ${p.basename(saved)}')),
      );
      return saved;
    }

    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Attachment not found on device.')),
    );
    return null;
  } catch (e) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Import failed: $e')),
    );
    return null;
  }
}

/// Downloads a file-like URL into the app's documents/attachments folder and returns the saved path.
/// Shows a SnackBar on failure. Returns null if the URL cannot be fetched.
Future<String?> downloadToAppDir(BuildContext context, String url) async {
  try {
    final uri = Uri.parse(url);
    final resp = await http.get(uri);
    if (resp.statusCode != 200) {
      if (!context.mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed (${resp.statusCode}).')),
      );
      return null;
    }

    final attachmentsDir = await getAppAttachmentsDir();

    var name = _filenameFromUrl(uri);
    if (!name.contains('.')) {
      final ext = _extFromContentType(resp.headers['content-type']);
      if (ext.isNotEmpty) name = '$name$ext';
    }
    final savePath = p.join(attachmentsDir.path, name);
    final file = File(savePath);
    await file.writeAsBytes(resp.bodyBytes);

    if (!context.mounted) return await toAppRelative(savePath);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved to Attachments: ${p.basename(savePath)}')),
    );
    return await toAppRelative(savePath);
  } catch (e) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Download error: $e')),
    );
    return null;
  }
}

String _sanitizeFileName(String s) {
  final cleaned = s.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  return cleaned.isEmpty ? 'file' : cleaned;
}

/// Shares a record's attachments (local files + URLs) along with a small
/// manifest so the recipient can link files back to the record.
///
/// [attachments] may contain local file paths and/or URLs.
Future<void> shareAttachmentsForRecord(
  BuildContext context, {
  required String profession,
  required DateTime date,
  required String title,
  String details = '',
  required List<String> attachments,
}) async {
  try {
    // Separate local file paths and URLs
    final files = <XFile>[];
    final urls = <String>[];
    for (final a in attachments) {
      if (isUrl(a)) {
        urls.add(a);
      } else {
        final abs = await resolveStoredPath(a);
        if (fileExists(abs)) {
          files.add(XFile(abs, name: p.basename(abs)));
        }
      }
    }

    // Build a small manifest.txt to describe the bundle
    final buf = StringBuffer();
    buf.writeln('CPD Attachment Bundle');
    buf.writeln('Profession: $profession');
    buf.writeln('Date: ${date.toIso8601String().split('T').first}');
    buf.writeln('Title: $title');
    if (details.trim().isNotEmpty) {
      buf.writeln('Details: ${details.replaceAll('\n', ' ')}');
    }
    buf.writeln('');
    if (files.isNotEmpty) {
      buf.writeln('Included files:');
      for (final f in files) {
        buf.writeln('  • ${f.name}');
      }
    } else {
      buf.writeln('Included files: (none)');
    }
    buf.writeln('');
    if (urls.isNotEmpty) {
      buf.writeln('Links:');
      for (final u in urls) {
        buf.writeln('  • $u');
      }
    } else {
      buf.writeln('Links: (none)');
    }

    // Write manifest and optional links file to temp
    final dir = await getTemporaryDirectory();
    final base = _sanitizeFileName('${date.toIso8601String().split('T').first}_$title');
    final manifestPath = p.join(dir.path, '${base}_manifest.txt');
    final manifestFile = File(manifestPath);
    await manifestFile.writeAsString(buf.toString());

    final shareFiles = <XFile>[...files, XFile(manifestFile.path, name: p.basename(manifestFile.path))];

    final subject = 'CPD attachments • $profession • ${date.toIso8601String().split('T').first}';
    final body = urls.isEmpty
        ? 'Attachments for "$title" ($profession).'
        : 'Attachments for "$title" ($profession). Links included in manifest.';

    await SharePlus.instance.share(
      ShareParams(
        files: shareFiles,
        subject: subject,
        text: body,
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Share failed: $e')),
    );
  }
}

/// Open an attachment referenced by a stored path or URL.
/// - For http/https/mailto/tel links, launches the appropriate external app.
/// - For local files, resolves relative or old-absolute paths to the current
///   app container and opens with the platform default handler.
Future<void> openAttachment(BuildContext context, String stored) async {
  try {
    // URLs: open in browser / dialer / mail
    if (isUrl(stored)) {
      await openUrl(context, stored);
      return;
    }

    // Local file: resolve to current container
    final abs = await resolveStoredPath(stored);
    if (!fileExists(abs)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('File not found: ${p.basename(stored)}')),
        );
      }
      return;
    }

    // Use the existing file opener (OpenFilex)
    if (!context.mounted) return;
    await openFile(context, abs);
  } catch (e) {
    debugPrint('[Attach] openAttachment failed: $e');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Unable to open attachment: $e')),
    );
  }
}