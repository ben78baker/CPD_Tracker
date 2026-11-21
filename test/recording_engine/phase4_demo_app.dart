import 'dart:io';

import 'package:cpd_tracker/recording_engine/layout_draft.dart';
import 'package:cpd_tracker/recording_engine/models.dart';
import 'package:cpd_tracker/recording_engine_storage/sqlite_recording_repository.dart';
import 'package:cpd_tracker/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'cpd_form_fixture.dart';
import 'equipment_fixture.dart';

/// Standalone target for a disposable debug app with synthetic data.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      title: 'Recording preview',
      theme: AppTheme.light,
      themeMode: ThemeMode.light,
      home: const _Preview(),
    ),
  );
}

class _Preview extends StatefulWidget {
  const _Preview();
  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  final _form = GlobalKey<FormState>();
  late final Future<SqliteRecordingRepository> _db = _open();
  late bool _equipment =
      const String.fromEnvironment('RECORDING_PREVIEW') == 'equipment';
  late Future<LayoutRevision> _layout = _prepare(_equipment);
  final _values = <String, Object?>{};
  final _links = <String, RecordingAttachment>{};
  LayoutDraft? _draft;
  bool _saving = false;

  Future<SqliteRecordingRepository> _open() async {
    final directory = await Directory.systemTemp.createTemp(
      'recording_preview_',
    );
    return SqliteRecordingRepository.open(
      p.join(directory.path, 'sample.sqlite'),
    );
  }

  Future<LayoutRevision> _prepare(bool equipment) async {
    final template = equipment
        ? measuredEquipmentTemplate(1)
        : cpdFormTemplate();
    final db = await _db;
    final saved = await db.loadTemplate(template.id, template.version);
    if (saved == null) await db.saveTemplate(template);
    final collection = await db.createCollection(template.label);
    final layout = await db.applyTemplate(
      collection.id,
      template,
      expectedVersion: 1,
      maxActiveFields: equipment ? null : cpdActiveFieldLimit,
    );
    final examples = equipment
        ? const {
            'asset': 'P-460',
            'inspection': '2026-11-20',
            'work': 'Replaced the outlet seal and ran a pressure test.',
            'equipment.pressure': '4.20',
            'cycle': 218,
            'result': 'pass',
            'equipment.lockout': true,
          }
        : const {
            'cpd.activityDate': '2026-11-20',
            'cpd.title': 'Clinical handover workshop',
            'cpd.details':
                'Practised a structured handover and discussed common omissions.',
            'cpd.creditedDuration': 90,
          };
    for (final field in layout.fields) {
      if (examples[field.definition.id] case final value?) {
        _values[field.id] = value;
      }
    }
    return layout;
  }

  bool get _editing => _draft != null;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_editing ? 'Edit layout' : 'Recording preview'),
      actions: [
        if (_editing)
          TextButton(
            onPressed: _saving ? null : _add,
            child: const Text('Add field'),
          ),
      ],
    ),
    body: FutureBuilder(
      future: _layout,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Preview failed: ${snapshot.error}'));
        }
        final layout = snapshot.requireData;
        final fields = _draft?.fields ?? layout.fields;
        return Column(
          children: [
            if (!_editing)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('CPD')),
                    ButtonSegment(value: true, label: Text('Equipment')),
                  ],
                  selected: {_equipment},
                  onSelectionChanged: _saving
                      ? null
                      : (values) {
                          if (values.single == _equipment) return;
                          setState(() {
                            _equipment = values.single;
                            _values.clear();
                            _links.clear();
                            _layout = _prepare(_equipment);
                          });
                        },
                ),
              ),
            Expanded(
              child: Form(
                key: _form,
                child: _editing
                    ? ReorderableListView(
                        buildDefaultDragHandles: false,
                        padding: const EdgeInsets.all(16),
                        header: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            _equipment
                                ? '${fields.length} active fields'
                                : '${fields.length} of $cpdActiveFieldLimit fields',
                          ),
                        ),
                        onReorder: (from, to) => setState(
                          () => _draft!.move(
                            fields[from].id,
                            to > from ? to - 1 : to,
                          ),
                        ),
                        children: [
                          for (final (index, field) in fields.indexed)
                            Card(
                              key: ValueKey(field.id),
                              child: ListTile(
                                leading: ReorderableDragStartListener(
                                  index: index,
                                  child: const Icon(
                                    Icons.drag_handle,
                                    semanticLabel: 'Reorder field',
                                  ),
                                ),
                                title: Text(field.label),
                                subtitle: Text(field.definition.kind.name),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (choice) => choice == 'rename'
                                      ? _rename(field)
                                      : setState(
                                          () => _draft!.retire(field.id),
                                        ),
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(
                                      value: 'rename',
                                      child: Text('Rename'),
                                    ),
                                    if (_equipment ||
                                        !field.definition.id.startsWith('cpd.'))
                                      const PopupMenuItem(
                                        value: 'retire',
                                        child: Text('Remove from layout'),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      )
                    : ListView(
                        key: ValueKey(layout.collectionId),
                        padding: const EdgeInsets.all(16),
                        children: [
                          Text(
                            _equipment ? 'Equipment maintenance' : 'CPD record',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 12),
                          for (final field in fields) ...[
                            for (final heading in layout.headings.where(
                              (h) => h.beforeFieldId == field.id,
                            ))
                              _Heading(heading.label),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _field(field),
                            ),
                          ],
                          for (final heading in layout.headings.where(
                            (h) => h.beforeFieldId == null,
                          ))
                            _Heading(heading.label),
                        ],
                      ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 12,
                  children: [
                    OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => setState(
                              () => _draft = _editing
                                  ? null
                                  : LayoutDraft(
                                      layout,
                                      maxActiveFields: _equipment
                                          ? null
                                          : cpdActiveFieldLimit,
                                    ),
                            ),
                      child: Text(_editing ? 'Cancel' : 'Edit layout'),
                    ),
                    FilledButton(
                      onPressed: _saving ? null : () => _save(layout),
                      child: Text(_editing ? 'Save layout' : 'Save sample'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget _field(LayoutField field) {
    final definition = field.definition;
    final decoration = InputDecoration(
      labelText: field.label,
      helperText: field.helpText,
      hintText: field.placeholder,
      suffixText: definition.unit,
    );
    if (field.format == FieldFormat.checkbox) {
      return CheckboxListTile(
        title: Text(field.label),
        value: _values[field.id] as bool? ?? false,
        onChanged: (value) => setState(() => _values[field.id] = value),
      );
    }
    if (definition.kind == FieldKind.boolean) {
      return DropdownButtonFormField<bool>(
        decoration: decoration,
        initialValue: _values[field.id] as bool?,
        items: const [
          DropdownMenuItem(value: true, child: Text('Yes')),
          DropdownMenuItem(value: false, child: Text('No')),
        ],
        onChanged: (value) => _values[field.id] = value,
      );
    }
    if (definition.kind == FieldKind.choice) {
      return DropdownButtonFormField<String>(
        decoration: decoration,
        initialValue: _values[field.id] as String?,
        items: [
          for (final choice in definition.choices.entries)
            DropdownMenuItem(value: choice.key, child: Text(choice.value)),
        ],
        onChanged: (value) => _values[field.id] = value,
      );
    }
    if (definition.kind == FieldKind.multipleChoices) {
      final selected =
          (_values[field.id] as List?)?.cast<String>() ?? const <String>[];
      return InputDecorator(
        decoration: decoration,
        child: Wrap(
          spacing: 8,
          children: [
            for (final choice in definition.choices.entries)
              FilterChip(
                label: Text(choice.value),
                selected: selected.contains(choice.key),
                onSelected: (checked) => setState(
                  () => _values[field.id] = checked
                      ? [...selected, choice.key]
                      : selected.where((id) => id != choice.key).toList(),
                ),
              ),
          ],
        ),
      );
    }
    if (definition.kind == FieldKind.attachments) {
      final hasEvidence = _links.containsKey(field.id);
      return OutlinedButton.icon(
        onPressed: () => setState(() {
          if (hasEvidence) {
            _links.remove(field.id);
          } else {
            _links[field.id] = RecordingAttachment(
              id: const Uuid().v4(),
              kind: AttachmentKind.link,
              locator: 'https://example.com',
              name: 'Sample evidence',
            );
          }
        }),
        icon: Icon(
          hasEvidence
              ? Icons.check
              : field.format == FieldFormat.photograph
              ? Icons.photo_camera
              : Icons.attach_file,
        ),
        label: Text(
          hasEvidence
              ? '${field.label}: sample link'
              : 'Add ${field.label.toLowerCase()}',
        ),
      );
    }
    final numeric =
        definition.kind == FieldKind.duration ||
        definition.kind == FieldKind.integer ||
        definition.kind == FieldKind.decimal;
    return TextFormField(
      key: ValueKey(field.id),
      initialValue: _values[field.id]?.toString(),
      decoration: definition.kind == FieldKind.duration
          ? decoration.copyWith(suffixText: 'min')
          : decoration,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : null,
      maxLines: definition.multiline ? 3 : 1,
      onChanged: (value) => _values[field.id] =
          definition.kind == FieldKind.integer ||
              definition.kind == FieldKind.duration
          ? int.tryParse(value) ?? value
          : value,
    );
  }

  Future<void> _save(LayoutRevision layout) async {
    final messenger = ScaffoldMessenger.of(context);
    final db = await _db;
    if (!mounted || _saving) return;
    setState(() => _saving = true);
    try {
      if (_draft case final draft?) {
        final revised = await db.saveLayoutDraft(draft);
        if (!mounted) return;
        setState(() {
          _layout = Future.value(revised);
          _draft = null;
        });
        messenger.showSnackBar(
          const SnackBar(content: Text('Layout saved in the preview')),
        );
      } else {
        final values = <String, Object>{};
        final attachments = <RecordingAttachment>[];
        for (final field in layout.fields) {
          if (_links[field.id] case final evidence?) {
            final copy = RecordingAttachment(
              id: const Uuid().v4(),
              kind: evidence.kind,
              locator: evidence.locator,
              name: evidence.name,
            );
            values[field.id] = [copy.id];
            attachments.add(copy);
          } else if (_values[field.id] case final value?
              when value != '' && (value is! List || value.isNotEmpty)) {
            values[field.id] = value;
          }
        }
        await db.createRecord(
          layout.collectionId,
          values,
          newAttachments: attachments,
          expectedLayoutVersion: layout.version,
        );
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Sample saved to temporary SQLite')),
          );
        }
      }
    } on ArgumentError catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(error.message.toString())),
        );
      }
    } on StateError catch (error) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _rename(LayoutField field) async {
    var label = field.label;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename field'),
        content: TextFormField(
          initialValue: label,
          onChanged: (text) => label = text,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, label.trim()),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (!mounted || result == null || result.isEmpty) return;
    setState(
      () => _draft!.configure(
        LayoutField(
          id: field.id,
          definition: field.definition,
          required: field.required,
          labelOverride: result,
          helpText: field.helpText,
          placeholder: field.placeholder,
          format: field.format,
          source: field.source,
          defaultValue: field.defaultValue,
        ),
      ),
    );
  }

  Future<void> _add() async {
    final result = await showModalBottomSheet<LayoutField>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('Create custom field'),
              subtitle: const Text('Add a short text field for this preview'),
              onTap: () {
                final id = const Uuid().v4();
                Navigator.pop(
                  context,
                  LayoutField(
                    id: id,
                    definition: FieldDefinition(
                      id: id,
                      version: 1,
                      label: 'Custom text',
                      kind: FieldKind.text,
                    ),
                  ),
                );
              },
            ),
            if (!_equipment)
              ListTile(
                leading: const Icon(Icons.library_books_outlined),
                title: const Text('Add Learning objective'),
                subtitle: const Text('Field Library sample'),
                onTap: () => Navigator.pop(
                  context,
                  cpdFieldLibrary
                      .search('learning goal')
                      .single
                      .instantiate(const Uuid().v4()),
                ),
              ),
          ],
        ),
      ),
    );
    if (!mounted || result == null) return;
    try {
      setState(() => _draft!.add(result));
    } on ArgumentError catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message.toString())));
      }
    }
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(label, style: Theme.of(context).textTheme.titleSmall),
  );
}
