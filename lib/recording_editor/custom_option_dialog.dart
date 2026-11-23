import 'package:flutter/material.dart';

import '../recording_engine/models.dart';
import 'strings.dart';

Future<({String label, bool save})?> showCustomOptionDialog(
  BuildContext context, {
  required LayoutField field,
  required bool canSave,
}) => showDialog<({String label, bool save})>(
  context: context,
  builder: (_) => _CustomOptionDialog(field: field, canSave: canSave),
);

class _CustomOptionDialog extends StatefulWidget {
  const _CustomOptionDialog({required this.field, required this.canSave});

  final LayoutField field;
  final bool canSave;

  @override
  State<_CustomOptionDialog> createState() => _CustomOptionDialogState();
}

class _CustomOptionDialogState extends State<_CustomOptionDialog> {
  String _label = '';
  String? _error;

  void _submit(bool save) {
    final s = editorStrings(context);
    final label = cleanChoiceLabel(_label);
    if (label.isEmpty) {
      setState(() => _error = s.choiceEnterLabel);
      return;
    }
    if (widget.field.availableChoices.values.any(
      (value) => choiceLabelKey(value) == choiceLabelKey(label),
    )) {
      setState(() => _error = s.choiceAlreadyExists);
      return;
    }
    Navigator.pop(context, (label: label, save: save));
  }

  @override
  Widget build(BuildContext context) {
    final s = editorStrings(context);
    return AlertDialog(
      scrollable: true,
      title: Text(s.choiceAddNew),
      content: TextField(
        autofocus: true,
        decoration: InputDecoration(
          labelText: s.editorChoice,
          errorText: _error,
        ),
        onChanged: (value) => setState(() {
          _label = value;
          _error = null;
        }),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.cancel),
        ),
        OutlinedButton(
          onPressed: () => _submit(false),
          child: Text(s.choiceUseOnce),
        ),
        if (widget.canSave)
          FilledButton(
            onPressed: () => _submit(true),
            child: Text(s.choiceSaveOption),
          ),
      ],
    );
  }
}
