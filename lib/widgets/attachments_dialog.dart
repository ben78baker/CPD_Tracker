import 'package:flutter/material.dart';
import 'attachment_tile.dart';
import '../l10n/app_localizations.dart';

/// Shows a dialog listing attachments (paths or URLs).
/// - Tapping an item opens it (image preview / file viewer / link launcher).
/// - Long-press actions (share/remove) are enabled when [enableLongPressActions] is true.
Future<void> showAttachmentsDialog({
  required BuildContext context,
  required List<String> attachments,
  String? title,
  bool enableLongPressActions = true,

  /// Optional callback when a single item is shared via long-press.
  Future<void> Function(String path)? onShareOne,

  /// Optional callback when an item is removed; receives its index from the *original* list.
  Future<void> Function(int)? onRemoveIndex,
}) async {
  if (attachments.isEmpty) {
    await showDialog(
      context: context,
      builder: (ctx) {
        final loc = AppLocalizations.of(ctx)!;
        return AlertDialog(
          title: Text(loc.attachments),
          content: Text(loc.noItemsAdded),
        );
      },
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
                Expanded(
                  child: Text(title ?? AppLocalizations.of(ctx)!.attachments),
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
                                title: Text(
                                  AppLocalizations.of(
                                    dctx,
                                  )!.removeAttachmentTitle,
                                ),
                                content: Text(
                                  AppLocalizations.of(
                                    dctx,
                                  )!.removeAttachmentBody,
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(dctx, false),
                                    child: Text(
                                      AppLocalizations.of(dctx)!.cancel,
                                    ),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(dctx, true),
                                    child: Text(
                                      AppLocalizations.of(dctx)!.remove,
                                    ),
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
