import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../recording_engine/models.dart';
import '../widgets/form_section_tile.dart';
import 'strings.dart';

enum EditorFieldType {
  shortText,
  longText,
  integer,
  decimal,
  date,
  duration,
  single,
  multiple,
  yesNo,
  checkbox,
  link,
  file,
  photograph,
  heading;

  FieldKind get kind => switch (this) {
    shortText || longText => FieldKind.text,
    integer => FieldKind.integer,
    decimal => FieldKind.decimal,
    date => FieldKind.date,
    duration => FieldKind.duration,
    single => FieldKind.choice,
    multiple => FieldKind.multipleChoices,
    yesNo || checkbox => FieldKind.boolean,
    link => FieldKind.url,
    file || photograph => FieldKind.attachments,
    heading => throw StateError('A heading has no stored value.'),
  };

  FieldFormat get format => switch (this) {
    checkbox => FieldFormat.checkbox,
    photograph => FieldFormat.photograph,
    _ => FieldFormat.standard,
  };

  static EditorFieldType of(LayoutField field) =>
      switch (field.definition.kind) {
        FieldKind.text => field.definition.multiline ? longText : shortText,
        FieldKind.integer => integer,
        FieldKind.decimal => decimal,
        FieldKind.date => date,
        FieldKind.duration => duration,
        FieldKind.choice => single,
        FieldKind.multipleChoices => multiple,
        FieldKind.boolean =>
          field.format == FieldFormat.checkbox ? checkbox : yesNo,
        FieldKind.url => link,
        FieldKind.attachments =>
          field.format == FieldFormat.photograph ? photograph : file,
      };

  String label(AppLocalizations s) => switch (this) {
    shortText => s.editorShort,
    longText => s.editorLong,
    integer => s.editorInteger,
    decimal => s.editorDecimal,
    date => s.editorDate,
    duration => s.editorDuration,
    single => s.editorSingle,
    multiple => s.editorMultiple,
    yesNo => s.editorYesNo,
    checkbox => s.editorCheckbox,
    link => s.editorLink,
    file => s.editorFile,
    photograph => s.editorPhoto,
    heading => s.editorHeading,
  };

  IconData get icon => switch (this) {
    shortText || longText => Icons.notes,
    integer || decimal => Icons.numbers,
    date => Icons.calendar_today_outlined,
    duration => Icons.schedule,
    single => Icons.list,
    multiple || yesNo || checkbox => Icons.check_box_outlined,
    link => Icons.link,
    file => Icons.attach_file,
    photograph => Icons.photo_camera_outlined,
    heading => Icons.title,
  };
}

/// Used by the layout editor, interactive preview and sample record editor.
class RecordingFieldTile extends StatelessWidget {
  const RecordingFieldTile({
    super.key,
    required this.field,
    this.value,
    this.onChanged,
    this.requireValue = false,
    this.sampleAttachmentId,
    this.attachmentLabels = const {},
    this.addAttachment,
    this.openAttachment,
  });

  final LayoutField field;
  final Object? value;
  final ValueChanged<Object?>? onChanged;
  final bool requireValue;
  final String? sampleAttachmentId;
  final Map<String, String> attachmentLabels;
  final VoidCallback? addAttachment;
  final ValueChanged<String>? openAttachment;

  @override
  Widget build(BuildContext context) {
    final s = editorStrings(context);
    final locale = Localizations.localeOf(context);
    final type = EditorFieldType.of(field);
    final label = field.localizedLabel(locale.toLanguageTag());
    final enabled = onChanged != null;
    final definition = field.definition;
    final decoration = InputDecoration(
      hintText: field.placeholder ?? type.label(s),
      suffixText:
          definition.unit ??
          (type == EditorFieldType.duration ? s.editorMinutes : null),
    );
    final Widget control;
    switch (type) {
      case EditorFieldType.date:
        final date = value is String
            ? DateTime.tryParse(value as String)
            : null;
        control = Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: !enabled
                    ? null
                    : () async {
                        final now = DateTime.now();
                        final selected = await showDatePicker(
                          context: context,
                          firstDate: DateTime(1),
                          lastDate: DateTime(9999),
                          initialDate: date ?? now,
                        );
                        if (context.mounted && selected != null) {
                          onChanged!(
                            selected.toIso8601String().split('T').first,
                          );
                        }
                      },
                icon: Icon(type.icon),
                label: Text(
                  date == null
                      ? decoration.hintText!
                      : MaterialLocalizations.of(
                          context,
                        ).formatCompactDate(date),
                ),
              ),
            ),
            if (enabled && date != null)
              IconButton(
                tooltip: s.editorClear,
                onPressed: () => onChanged!(null),
                icon: const Icon(Icons.clear),
              ),
          ],
        );
      case EditorFieldType.single:
        control = Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                key: ValueKey(value == null),
                decoration: decoration,
                isExpanded: true,
                initialValue: value as String?,
                items: [
                  for (final choice in definition.choices.entries)
                    DropdownMenuItem(
                      value: choice.key,
                      child: Text(choice.value),
                    ),
                ],
                selectedItemBuilder: (context) => [
                  for (final choice in definition.choices.values)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(choice, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: enabled ? onChanged : null,
              ),
            ),
            if (enabled && value != null)
              IconButton(
                tooltip: s.editorClear,
                icon: const Icon(Icons.clear),
                onPressed: () => onChanged!(null),
              ),
          ],
        );
      case EditorFieldType.multiple:
        final selected = (value as List?)?.cast<String>() ?? const [];
        control = Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final choice in definition.choices.entries)
              FilterChip(
                label: Text(choice.value),
                selected: selected.contains(choice.key),
                onSelected: !enabled
                    ? null
                    : (checked) {
                        final next = {...selected};
                        checked
                            ? next.add(choice.key)
                            : next.remove(choice.key);
                        onChanged!(next.isEmpty ? null : next.toList());
                      },
              ),
          ],
        );
      case EditorFieldType.yesNo:
      case EditorFieldType.checkbox:
        control = Wrap(
          spacing: 8,
          children: [
            if (type == EditorFieldType.checkbox)
              Checkbox(
                value: value as bool?,
                tristate: true,
                semanticLabel: label,
                onChanged: !enabled ? null : onChanged,
              )
            else
              for (final (option, text) in [
                (true, s.editorYes),
                (false, s.editorNo),
              ])
                ChoiceChip(
                  label: Text(text),
                  selected: value == option,
                  onSelected: !enabled
                      ? null
                      : (selected) => onChanged!(selected ? option : null),
                ),
          ],
        );
      case EditorFieldType.file:
      case EditorFieldType.photograph:
        final attachments = (value as List?)?.cast<String>() ?? const [];
        control = Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final id in attachments)
              InputChip(
                avatar: Icon(type.icon, size: 18),
                label: Text(attachmentLabels[id] ?? s.editorSampleFile),
                onPressed: openAttachment == null
                    ? null
                    : () => openAttachment!(id),
                isEnabled:
                    enabled ||
                    openAttachment != null ||
                    sampleAttachmentId == null,
                onDeleted: !enabled
                    ? null
                    : () {
                        final remaining = attachments
                            .where((item) => item != id)
                            .toList();
                        onChanged!(remaining.isEmpty ? null : remaining);
                      },
              ),
            if (addAttachment != null)
              OutlinedButton.icon(
                onPressed: enabled ? addAttachment : null,
                icon: Icon(type.icon),
                label: Text(s.trialAddEvidence),
              )
            else if (attachments.isEmpty ||
                (sampleAttachmentId != null &&
                    !attachments.contains(sampleAttachmentId)))
              OutlinedButton.icon(
                onPressed: enabled && sampleAttachmentId != null
                    ? () => onChanged!([...attachments, sampleAttachmentId!])
                    : null,
                icon: Icon(type.icon),
                label: Text(s.editorSampleFile),
              ),
          ],
        );
      default:
        final numeric =
            type == EditorFieldType.integer ||
            type == EditorFieldType.decimal ||
            type == EditorFieldType.duration;
        final separator = NumberFormat.decimalPattern(
          locale.toLanguageTag(),
        ).symbols.DECIMAL_SEP;
        final text = value?.toString() ?? '';
        final displayed = type == EditorFieldType.decimal
            ? text.replaceFirst('.', separator)
            : text;
        control = Semantics(
          label: label,
          child: TextFormField(
            enabled: enabled,
            initialValue: displayed,
            decoration: decoration,
            minLines: type == EditorFieldType.longText ? 2 : 1,
            maxLines: type == EditorFieldType.longText ? 5 : 1,
            keyboardType: numeric
                ? TextInputType.numberWithOptions(
                    decimal: type == EditorFieldType.decimal,
                    signed: type != EditorFieldType.duration,
                  )
                : type == EditorFieldType.link
                ? TextInputType.url
                : type == EditorFieldType.longText
                ? TextInputType.multiline
                : TextInputType.text,
            onChanged: !enabled
                ? null
                : (raw) => onChanged!(parseTextValue(type, raw, separator)),
          ),
        );
    }
    return FormSectionTile(
      label: label,
      icon: type.icon,
      supportingText: [
        if (requireValue) s.editorRequired,
        ?field.helpText,
      ].join(' · ').ifEmptyNull,
      child: control,
    );
  }
}

extension on String {
  String? get ifEmptyNull => isEmpty ? null : this;
}

Object? parseTextValue(EditorFieldType type, String raw, String separator) {
  if (raw.trim().isEmpty) return null;
  if (type == EditorFieldType.integer || type == EditorFieldType.duration) {
    return int.tryParse(raw, radix: 10) ?? raw;
  }
  if (type == EditorFieldType.decimal && separator != '.') {
    if (raw.contains('.') && raw.contains(separator)) return raw;
    return raw.replaceFirst(separator, '.');
  }
  return raw;
}

class RecordingForm extends StatelessWidget {
  const RecordingForm({
    super.key,
    required this.fields,
    this.headings = const [],
    required this.values,
    this.onChanged,
    this.sampleAttachmentId,
    this.attachmentLabels = const {},
    this.requiredIds,
    this.addAttachment,
    this.openAttachment,
  });

  final List<LayoutField> fields;
  final List<SectionHeading> headings;
  final Map<String, Object> values;
  final void Function(String id, Object? value)? onChanged;
  final String? sampleAttachmentId;
  final Map<String, String> attachmentLabels;
  final Set<String>? requiredIds;
  final ValueChanged<LayoutField>? addAttachment;
  final ValueChanged<String>? openAttachment;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final field in fields) ...[
        for (final heading in headings.where(
          (item) => item.beforeFieldId == field.id,
        ))
          _Heading(heading.label),
        Padding(
          key: ValueKey(field.id),
          padding: const EdgeInsets.only(bottom: 12),
          child: RecordingFieldTile(
            field: field,
            value: values[field.id],
            requireValue: requiredIds?.contains(field.id) ?? field.required,
            sampleAttachmentId: sampleAttachmentId,
            attachmentLabels: attachmentLabels,
            addAttachment: addAttachment == null
                ? null
                : () => addAttachment!(field),
            openAttachment: openAttachment,
            onChanged: onChanged == null
                ? null
                : (value) => onChanged!(field.id, value),
          ),
        ),
      ],
      for (final heading in headings.where(
        (item) => item.beforeFieldId == null,
      ))
        _Heading(heading.label),
    ],
  );
}

class _Heading extends StatelessWidget {
  const _Heading(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Semantics(
      header: true,
      child: Text(label, style: Theme.of(context).textTheme.titleLarge),
    ),
  );
}
