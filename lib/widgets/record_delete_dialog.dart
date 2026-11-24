import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'tactile_button.dart';

Future<bool> confirmRecordDeletion(
  BuildContext context, {
  bool restore = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) {
        final s = AppLocalizations.of(context)!;
        return AlertDialog(
          title: Text(restore ? s.restoreRecordTitle : s.deleteRecordTitle),
          content: Text(
            restore ? s.restoreRecordConfirm : s.deleteRecordConfirm,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.cancel),
            ),
            TactileButton(
              onPressed: () => Navigator.pop(context, true),
              variant: restore
                  ? TactileButtonVariant.primary
                  : TactileButtonVariant.destructive,
              child: Text(restore ? s.restore : s.delete),
            ),
          ],
        );
      },
    ) ??
    false;
