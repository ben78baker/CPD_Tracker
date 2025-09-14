import 'dart:io';
import 'package:flutter/material.dart';
import '../utils/attachment_io.dart';
import 'package:path/path.dart' as p;

class AttachmentTile extends StatelessWidget {
  const AttachmentTile({
    super.key,
    required this.value,                // path or URL
    this.onRemove,                      // optional delete callback
    this.enableLongPressActions = false,
    this.onShare,                       // optional share callback
  });

  final String value;
  final VoidCallback? onRemove;
  final bool enableLongPressActions;
  final Future<void> Function()? onShare;

  @override
  Widget build(BuildContext context) {
    final url = isUrl(value);
    final exists = fileExists(value);
    final img = exists && isImagePath(value);

    Widget leading;
    if (url) {
      leading = const Icon(Icons.link_outlined);
    } else if (img) {
      leading = ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(File(value), width: 48, height: 48, fit: BoxFit.cover),
      );
    } else {
      leading = const Icon(Icons.insert_drive_file);
    }

    Future<void> handleTap() async {
      if (url) return openUrl(context, value);
      if (exists && img) {
        await showDialog(
          context: context,
          builder: (ctx) => Dialog(
            insetPadding: const EdgeInsets.all(16),
            child: InteractiveViewer(child: Image.file(File(value), fit: BoxFit.contain)),
          ),
        );
      } else if (exists) {
        await openFile(context, value);
      } else {
        // no-op for non-existent file path
      }
    }

    final semanticsLabel = url ? 'Link' : (img ? 'Image attachment' : 'File attachment');

    return Semantics(
      label: semanticsLabel,
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: leading,
        title: Text(p.basename(value), maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: onRemove == null
            ? null
            : IconButton(icon: const Icon(Icons.close), onPressed: onRemove),
        onTap: handleTap,
        onLongPress: !enableLongPressActions ? null : () async {
          final action = await showModalBottomSheet<String>(
            context: context,
            showDragHandle: true,
            builder: (bCtx) => SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (onShare != null)
                  ListTile(
                    leading: const Icon(Icons.ios_share),
                    title: const Text('Share this attachment'),
                    onTap: () => Navigator.pop(bCtx, 'share'),
                  ),
                if (onRemove != null)
                  ListTile(
                    leading: const Icon(Icons.delete_outline),
                    title: const Text('Remove'),
                    onTap: () => Navigator.pop(bCtx, 'remove'),
                  ),
                const SizedBox(height: 8),
              ]),
            ),
          );
          if (action == 'share') await onShare?.call();
          if (action == 'remove') onRemove?.call();
        },
      ),
    );
  }
}