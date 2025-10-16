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
  final Future<void> Function()? onRemove;
  final bool enableLongPressActions;
  final Future<void> Function()? onShare;

  @override
  Widget build(BuildContext context) {
    // Resolve relative/old-absolute paths to current container for local files.
    return FutureBuilder<String>(
      future: resolveStoredPath(value),
      builder: (context, snap) {
        final resolved = snap.data; // absolute path for local files; URLs returned unchanged
        final url = isUrl(value);

        // Determine image using the resolved path for locals
        final img = !url && resolved != null && fileExists(resolved) && isImagePath(resolved);

        Widget leading;
        if (url) {
          leading = const Icon(Icons.link_outlined);
        } else if (img) {
          // ignore: unnecessary_non_null_assertion
          final r = resolved!; // non-null here by img guard
          leading = ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.file(
              File(r),
              width: 48,
              height: 48,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported),
            ),
          );
        } else {
          leading = const Icon(Icons.insert_drive_file);
        }

        Future<void> handleTap() async {
          await openAttachment(context, value);
        }

        final semanticsLabel = url ? 'Link' : (img ? 'Image attachment' : 'File attachment');
        final displayName = () {
          if (url) return value;
          if (resolved != null) return p.basename(resolved);
          return p.basename(value);
        }();

        return Semantics(
          label: semanticsLabel,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: leading,
            title: Text(
              displayName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: onRemove == null
                ? null
                : IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.close),
                    onPressed: () async {
                      await onRemove?.call();
                    },
                  ),
            onTap: handleTap,
            onLongPress: !enableLongPressActions
                ? null
                : () async {
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
                    if (action == 'remove') await onRemove?.call();
                  },
          ),
        );
      },
    );
  }
}