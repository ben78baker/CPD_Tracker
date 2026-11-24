import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../l10n/app_localizations.dart';
import '../recording_engine/models.dart';
import 'record_form.dart';
import 'strings.dart';

class FieldSettingsResult {
  const FieldSettingsResult(
    this.field, {
    this.retrospective = false,
    this.heading = false,
  });
  final LayoutField field;
  final bool retrospective;
  final bool heading;
}

class FieldSettingsPage extends StatefulWidget {
  const FieldSettingsPage({
    super.key,
    required this.field,
    this.inserting = false,
    this.protected = false,
    this.needsName = false,
    this.heading = false,
    this.libraryDescription,
  });

  final LayoutField field;
  final bool inserting;
  final bool protected;
  final bool needsName;
  final bool heading;
  final String? libraryDescription;

  @override
  State<FieldSettingsPage> createState() => _FieldSettingsPageState();
}

class _FieldSettingsPageState extends State<FieldSettingsPage> {
  static const _uuid = Uuid();
  late final _field = widget.field;
  late final _name = TextEditingController(
    text: widget.needsName ? '' : _field.labelOverride ?? '',
  );
  late final _help = TextEditingController(text: _field.helpText);
  late final _placeholder = TextEditingController(text: _field.placeholder);
  late final _unit = TextEditingController(text: _field.definition.unit);
  late final _precision = TextEditingController(
    text: _field.definition.decimalPlaces?.toString() ?? '',
  );
  late final _choices = LinkedHashMap.of({
    for (final choice in _field.availableChoices.entries)
      choice.key: TextEditingController(
        text: widget.needsName ? '' : choice.value,
      ),
  });
  late bool _required = _field.required;
  late bool _allowCustomOptions = _field.definition.allowCustomOptions;
  late bool _nonNegative = _field.definition.nonNegative;
  late EditorFieldType _type = EditorFieldType.of(_field);
  late Object? _default = _field.defaultValue;
  bool _retro = false;
  bool _dirty = false;
  bool _error = false;
  bool _leaving = false;

  @override
  void dispose() {
    for (final controller in [
      _name,
      _help,
      _placeholder,
      _unit,
      _precision,
      ..._choices.values,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _optional(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text;
  bool get _selectable =>
      _type == EditorFieldType.single || _type == EditorFieldType.multiple;
  bool get _canChangeChoicePolicy =>
      _selectable &&
      !widget.protected &&
      _field.source == null &&
      _field.id == _field.definition.id;
  bool get _numeric =>
      _type == EditorFieldType.integer || _type == EditorFieldType.decimal;
  bool get _canDefault =>
      _type != EditorFieldType.file && _type != EditorFieldType.photograph;

  LayoutField _buildField({
    required String id,
    required bool replacement,
    bool forPreview = false,
  }) {
    final original = _field.definition;
    final definition = replacement || widget.needsName
        ? FieldDefinition(
            id: id,
            version: 1,
            label: _optional(_name) ?? original.label,
            kind: _type.kind,
            multiline: _type == EditorFieldType.longText,
            unit: _numeric ? _optional(_unit) : null,
            decimalPlaces: _type == EditorFieldType.decimal
                ? int.tryParse(_precision.text)
                : null,
            choices: {
              if (_selectable)
                for (final choice in _choices.entries)
                  choice.key: cleanChoiceLabel(choice.value.text),
            },
            allowCustomOptions: _selectable && _allowCustomOptions,
            nonNegative: _numeric && _nonNegative,
            maxLength: original.maxLength,
            description: replacement ? original.description : null,
            translations: replacement ? original.translations : const {},
          )
        : original;
    return LayoutField(
      id: id,
      definition: definition,
      labelOverride: _optional(_name),
      format: _type.format,
      helpText: _optional(_help),
      placeholder: _optional(_placeholder),
      required: _required,
      source: _field.source,
      addedOptions: identical(definition, original)
          ? _field.addedOptions
          : const {},
      defaultValue: forPreview ? null : _default,
    );
  }

  bool get _semanticChange {
    final definition = _field.definition;
    if (_numeric &&
        (_optional(_unit) != definition.unit ||
            (_type == EditorFieldType.decimal &&
                int.tryParse(_precision.text) != definition.decimalPlaces) ||
            _nonNegative != definition.nonNegative)) {
      return true;
    }
    if (_selectable) {
      final before = _field.availableChoices.entries.toList();
      return _allowCustomOptions != definition.allowCustomOptions ||
          before.length != _choices.length ||
          _choices.entries.indexed.any((item) {
            final (index, choice) = item;
            return before[index].key != choice.key ||
                cleanChoiceLabel(before[index].value) !=
                    cleanChoiceLabel(choice.value.text);
          });
    }
    return false;
  }

  Future<void> _submit() async {
    final s = editorStrings(context);
    try {
      if ((widget.needsName || widget.heading) && _name.text.trim().isEmpty) {
        throw ArgumentError('Missing name');
      }
      if (_selectable &&
          _choices.values.map((c) => choiceLabelKey(c.text)).toSet().length !=
              _choices.length) {
        throw ArgumentError('Duplicate choice labels');
      }
      final changed = _semanticChange && !widget.protected;
      final replace = changed && !widget.inserting;
      final field = _buildField(
        id: replace || changed ? _uuid.v4() : _field.id,
        replacement: changed,
      );
      if (replace &&
          !await editorConfirmation(
            context,
            s.editorReplace,
            _selectable ? s.editorChoiceReplaceHint : s.editorReplaceHint,
            s.editorReplace,
          )) {
        return;
      }
      if (!mounted) return;
      _leaving = true;
      Navigator.pop(
        context,
        FieldSettingsResult(
          field,
          retrospective: _retro,
          heading: widget.heading,
        ),
      );
    } on ArgumentError {
      setState(() => _error = true);
    }
  }

  Future<void> _cancel() async {
    if (_leaving) return;
    final s = editorStrings(context);
    if (_dirty &&
        !await editorConfirmation(
          context,
          s.editorDiscard,
          s.editorUnsaved,
          s.editorDiscardAction,
        )) {
      return;
    }
    if (mounted) {
      setState(() => _leaving = true);
      Navigator.pop(context);
    }
  }

  void _change([VoidCallback? action]) => setState(() {
    _dirty = true;
    _error = false;
    action?.call();
  });

  @override
  Widget build(BuildContext context) {
    final s = editorStrings(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final label = _field.localizedLabel(locale);
    LayoutField? preview;
    if (!widget.heading) {
      try {
        preview = _buildField(
          id: _field.id,
          replacement: _semanticChange,
          forPreview: true,
        );
      } on ArgumentError {
        // An incomplete configuration becomes previewable once it is valid.
      }
    }
    return PopScope(
      canPop: !_dirty || _leaving,
      onPopInvokedWithResult: (popped, _) {
        if (!popped) _cancel();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.heading ? s.editorHeading : s.editorSettings),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(16),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                if (widget.libraryDescription case final description?)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(description),
                  ),
                if (!widget.heading)
                  Text(
                    _type.label(s),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                _input(
                  _name,
                  s.editorName,
                  hint: widget.needsName ? null : label,
                  autofocus: widget.needsName,
                ),
                if (!widget.heading) ...[
                  if (widget.protected)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(s.editorProtectedReason),
                    ),
                  if (!widget.protected)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.editorRequired),
                      value: _required,
                      onChanged: (value) => _change(() => _required = value),
                    ),
                  if (_canChangeChoicePolicy)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.choiceAllowNew),
                      value: _allowCustomOptions,
                      onChanged: (value) => _change(() {
                        _allowCustomOptions = value;
                        if (!value) _default = null;
                      }),
                    ),
                  if (_selectable && !widget.protected) ...[
                    for (final choice in _choices.entries)
                      Row(
                        key: ValueKey(choice.key),
                        children: [
                          Expanded(child: _input(choice.value, s.editorChoice)),
                          IconButton(
                            tooltip: s.editorRemove,
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: _choices.length < 2
                                ? null
                                : () => _change(() {
                                    _choices.remove(choice.key);
                                    WidgetsBinding.instance
                                        .addPostFrameCallback(
                                          (_) => choice.value.dispose(),
                                        );
                                    _default = null;
                                  }),
                          ),
                        ],
                      ),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        onPressed: () => _change(
                          () => _choices[_uuid.v4()] = TextEditingController(),
                        ),
                        icon: const Icon(Icons.add),
                        label: Text(s.editorAddChoice),
                      ),
                    ),
                  ],
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(s.editorAdvanced),
                    children: [
                      _input(_help, s.editorHelp),
                      if (!_selectable &&
                          _type != EditorFieldType.checkbox &&
                          _type != EditorFieldType.yesNo)
                        _input(_placeholder, s.editorPlaceholder),
                      if (_numeric && !widget.protected) ...[
                        _input(_unit, s.editorUnit),
                        if (_type == EditorFieldType.decimal)
                          _input(_precision, s.editorPrecision, numeric: true),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(s.editorNonNegative),
                          value: _nonNegative,
                          onChanged: (value) =>
                              _change(() => _nonNegative = value),
                        ),
                      ],
                      if (_type.kind == FieldKind.boolean ||
                          (_type.kind == FieldKind.attachments &&
                              !widget.protected))
                        DropdownButtonFormField<EditorFieldType>(
                          initialValue: _type,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: s.editorFormatting,
                          ),
                          items: [
                            for (final type
                                in _type.kind == FieldKind.boolean
                                    ? [
                                        EditorFieldType.yesNo,
                                        EditorFieldType.checkbox,
                                      ]
                                    : [
                                        EditorFieldType.file,
                                        EditorFieldType.photograph,
                                      ])
                              DropdownMenuItem(
                                value: type,
                                child: Text(type.label(s)),
                              ),
                          ],
                          onChanged: (value) => _change(() => _type = value!),
                        ),
                      if (_canDefault && !widget.protected && preview != null)
                        _defaultControl(s, preview, locale),
                    ],
                  ),
                  if (widget.inserting)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_retro ? s.editorBoth : s.editorFuture),
                      subtitle: Text(s.editorHistoryHint),
                      value: _retro,
                      onChanged: (value) => _change(() => _retro = value!),
                    ),
                  if (preview != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      s.editorPreview,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    RecordingFieldTile(
                      key: ValueKey(preview.definition.choices.toString()),
                      field: preview,
                      value: null,
                      requireValue: preview.required,
                    ),
                  ],
                ],
                if (_error)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        s.editorInvalid,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: EditorActions(
          onCancel: _cancel,
          onSave: _submit,
          saveLabel: widget.inserting ? s.addField : s.save,
        ),
      ),
    );
  }

  Widget _defaultControl(
    AppLocalizations s,
    LayoutField preview,
    String locale,
  ) {
    if (_type.kind == FieldKind.text ||
        _numeric ||
        _type == EditorFieldType.duration ||
        _type == EditorFieldType.link) {
      final separator = NumberFormat.decimalPattern(locale).symbols.DECIMAL_SEP;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: TextFormField(
          initialValue:
              _default?.toString().replaceFirst(
                '.',
                _type == EditorFieldType.decimal ? separator : '.',
              ) ??
              '',
          decoration: InputDecoration(labelText: s.editorDefault),
          onChanged: (raw) =>
              _change(() => _default = parseTextValue(_type, raw, separator)),
        ),
      );
    }
    return RecordingFieldTile(
      field: LayoutField(
        id: preview.id,
        definition: preview.definition,
        labelOverride: s.editorDefault,
        format: preview.format,
      ),
      value: _default,
      onChanged: (value) => _change(() => _default = value),
    );
  }

  Widget _input(
    TextEditingController controller,
    String label, {
    String? hint,
    bool autofocus = false,
    bool numeric = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: TextField(
      controller: controller,
      autofocus: autofocus,
      decoration: InputDecoration(labelText: label, hintText: hint),
      keyboardType: numeric ? TextInputType.number : null,
      onChanged: (_) => _change(),
    ),
  );
}

Future<bool> editorConfirmation(
  BuildContext context,
  String title,
  String body,
  String action,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(editorStrings(context).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

class EditorActions extends StatelessWidget {
  const EditorActions({
    super.key,
    required this.onCancel,
    required this.onSave,
    required this.saveLabel,
  });
  final VoidCallback? onCancel;
  final VoidCallback? onSave;
  final String saveLabel;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          OutlinedButton(
            onPressed: onCancel,
            child: Text(editorStrings(context).cancel),
          ),
          FilledButton(onPressed: onSave, child: Text(saveLabel)),
        ],
      ),
    ),
  );
}
