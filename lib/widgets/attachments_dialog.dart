

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/attachment_io.dart';
import 'attachment_tile.dart';

/// Shows a dialog listing attachments (paths or URLs).
/// - Tapping an item opens it (image preview / file viewer / link launcher).
/// - Long-press actions (share/remove) are enabled when [enableLongPressActions] is true.
/// - A "Share all" button appears when there are 2+ items; it shares files as attachments
///   and URLs as plain text in the same sheet.
Future<void> showAttachmentsDialog({
  required BuildContext context,
  required List<String> attachments,
  String title = 'Attachments',
  bool enableLongPressActions = true,
  /// Optional callback when a single item is shared via long-press.
  Future<void> Function(String path)? onShareOne,
  /// Optional callback when an item is removed; receives its index from the *original* list.
  Future<void> Function(int)? onRemoveIndex,
}) async {
  if (attachments.isEmpty) {
    await showDialog(
      context: context,
      builder: (ctx) => const AlertDialog(
        title: Text('Attachments'),
        content: Text('No items have been added.'),
      ),
    );
    return;
  }

  // Work on a local copy we can mutate inside the dialog.
  final original = List<String>.from(attachments);

  await showDialog(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          final files = original.where((p) => p.trim().isNotEmpty).toList();

          return AlertDialog(
            title: Row(
              children: [
                Expanded(child: Text(title)),
                if (files.length > 1)
                  FilledButton.icon(
                    onPressed: () async {
                      Navigator.of(ctx).pop();

                      final xfiles = <XFile>[];
                      final urls = <String>[];

                      for (final raw in files) {
                        final p = raw.trim();
                        if (isUrl(p)) {
                          urls.add(p);
                          continue;
                        }
                        if (fileExists(p)) {
                          xfiles.add(XFile(p));
                        }
                      }

                      try {
                        if (xfiles.isNotEmpty && urls.isNotEmpty) {
                          // ignore: deprecated_member_use
                          await Share.shareXFiles(xfiles, text: urls.join('\n'));
                        } else if (xfiles.isNotEmpty) {
                          // ignore: deprecated_member_use
                          await Share.shareXFiles(xfiles);
                        } else if (urls.isNotEmpty) {
                          // ignore: deprecated_member_use
                          await Share.share(urls.join('\n'));
                        } else {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('No shareable files or links found.')),
                            );
                          }
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Share failed: $e')),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.ios_share),
                    label: const Text('Share all'),
                  ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: files.length,
                itemBuilder: (c, i) {
                  final path = files[i];
                  return AttachmentTile(
                    value: path,
                    enableLongPressActions: enableLongPressActions,
                    onShare: onShareOne == null ? null : () => onShareOne(path),
                    onRemove: onRemoveIndex == null
                        ? null
                        : () async {
                            // Ask user to confirm removal first
                            final confirm = await showDialog<bool>(
                              context: ctx,
                              builder: (dctx) => AlertDialog(
                                title: const Text('Remove attachment?'),
                                content: const Text('Do you want to remove this attachment?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(dctx, false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(dctx, true),
                                    child: const Text('Remove'),
                                  ),
                                ],
                              ),
                            );

                            if (confirm != true) return; // cancelled

                            // Map current index back to original list index, then invoke parent removal
                            final originalIdx = original.indexOf(path);
                            if (originalIdx >= 0) {
                              try {
                                await onRemoveIndex(originalIdx);
                              } finally {
                                // Reflect removal in the dialog's local view only after parent handled it
                                setState(() => original.removeAt(originalIdx));
                              }
                            }
                          },
                  );
                },
              ),
            ),
          );
        },
      );
    },
  );
}