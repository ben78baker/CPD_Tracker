import 'package:flutter/material.dart';
import 'attachment_tile.dart';
import '../l10n/app_localizations.dart';
import 'tactile_button.dart';

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
  List<String>? displayNames,
  Future<void> Function(int)? onShareAt,
  Future<bool> Function(int)? onRemoveCurrent,
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
  final names = displayNames?.toList();
  var removing = false;

  await showDialog(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          final files = original.indexed
              .where((file) => file.$2.trim().isNotEmpty)
              .toList();

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
                  final (originalIdx, path) = files[i];
                  return AttachmentTile(
                    value: path,
                    displayName: names?[originalIdx],
                    enableLongPressActions: enableLongPressActions,
                    onShare: onShareAt != null
                        ? () => onShareAt(originalIdx)
                        : onShareOne == null
                        ? null
                        : () => onShareOne(path),
                    onRemove: onRemoveIndex == null && onRemoveCurrent == null
                        ? null
                        : () async {
                            if (removing) return;
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
                                  TactileButton(
                                    onPressed: () => Navigator.pop(dctx, true),
                                    variant: TactileButtonVariant.destructive,
                                    child: Text(
                                      AppLocalizations.of(dctx)!.remove,
                                    ),
                                  ),
                                ],
                              ),
                            );

                            if (confirm != true || removing) return;
                            removing = true;
                            try {
                              if (onRemoveCurrent != null) {
                                if (!await onRemoveCurrent(originalIdx)) return;
                              } else {
                                await onRemoveIndex!(originalIdx);
                              }
                              if (!ctx.mounted) return;
                              setState(() {
                                original.removeAt(originalIdx);
                                names?.removeAt(originalIdx);
                              });
                            } finally {
                              removing = false;
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
