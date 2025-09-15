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
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open link.')),
      );
    }
  } else {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No app available to open link.')),
      );
    }
  }
}

Future<void> openFile(BuildContext context, String path) async {
  try {
    final res = await OpenFilex.open(path);
    if (res.type != ResultType.done && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Can't open this file (${res.message}).")),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Open failed: $e')),
      );
    }
  }
}

bool fileExists(String p) => File(p).existsSync();

/// Downloads a file-like URL into the app's documents/attachments folder and returns the saved path.
/// Shows a SnackBar on failure. Returns null if the URL cannot be fetched.
Future<String?> downloadToAppDir(BuildContext context, String url) async {
  try {
    final uri = Uri.parse(url);
    final resp = await http.get(uri);
    if (resp.statusCode != 200) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed (${resp.statusCode}).')),
        );
      }
      return null;
    }

    final dir = await getApplicationDocumentsDirectory();
    final attachmentsDir = Directory(p.join(dir.path, 'attachments'));
    if (!attachmentsDir.existsSync()) {
      attachmentsDir.createSync(recursive: true);
    }

    var name = _filenameFromUrl(uri);
    if (!name.contains('.')) {
      final ext = _extFromContentType(resp.headers['content-type']);
      if (ext.isNotEmpty) name = '$name$ext';
    }
    final savePath = p.join(attachmentsDir.path, name);
    final file = File(savePath);
    await file.writeAsBytes(resp.bodyBytes);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved to Attachments: ${p.basename(savePath)}')),
      );
    }
    return savePath;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download error: $e')),
      );
    }
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
      } else if (fileExists(a)) {
        files.add(XFile(a, name: p.basename(a)));
      }
    }

    // Build a small manifest.txt to describe the bundle
    final buf = StringBuffer();
    buf.writeln('CPD Attachment Bundle');
    buf.writeln('Profession: $profession');
    buf.writeln('Date: ${date.toIso8601String().split('T').first}');
    buf.writeln('Title: $title');
    if (details.trim().isNotEmpty) {
      buf.writeln('Details: ' + details.replaceAll('\n', ' '));
    }
    buf.writeln('');
    if (files.isNotEmpty) {
      buf.writeln('Included files:');
      for (final f in files) {
        buf.writeln('  • ' + (f.name ?? p.basename(f.path)));
      }
    } else {
      buf.writeln('Included files: (none)');
    }
    buf.writeln('');
    if (urls.isNotEmpty) {
      buf.writeln('Links:');
      for (final u in urls) {
        buf.writeln('  • ' + u);
      }
    } else {
      buf.writeln('Links: (none)');
    }

    // Write manifest and optional links file to temp
    final dir = await getTemporaryDirectory();
    final base = _sanitizeFileName('${date.toIso8601String().split('T').first}_${title}');
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
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Share failed: $e')),
      );
    }
  }
}