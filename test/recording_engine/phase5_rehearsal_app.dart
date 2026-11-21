import 'dart:convert';
import 'dart:io';

import 'package:cpd_tracker/cpd_compatibility/cpd_layout_policy.dart';
import 'package:cpd_tracker/l10n/app_localizations.dart';
import 'package:cpd_tracker/recording_editor/edit_fields_page.dart';
import 'package:cpd_tracker/recording_editor/field_settings.dart';
import 'package:cpd_tracker/recording_editor/record_form.dart';
import 'package:cpd_tracker/recording_editor/strings.dart';
import 'package:cpd_tracker/recording_editor/template_preview.dart';
import 'package:cpd_tracker/recording_engine/models.dart';
import 'package:cpd_tracker/recording_engine/record_export.dart';
import 'package:cpd_tracker/recording_engine_storage/sqlite_recording_repository.dart';
import 'package:cpd_tracker/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'phase5_fixtures.dart';

/// Run in a disposable application ID. Production navigation never imports
/// this target or creates the rehearsal database.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  const locale = String.fromEnvironment('EDITOR_LOCALE', defaultValue: 'en');
  runApp(
    MaterialApp(
      theme: AppTheme.light,
      locale: const Locale(locale),
      debugShowCheckedModeBanner: false,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: const _Rehearsal(),
    ),
  );
}

class _Rehearsal extends StatefulWidget {
  const _Rehearsal();
  @override
  State<_Rehearsal> createState() => _RehearsalState();
}

class _RehearsalState extends State<_Rehearsal> {
  late final _repository = _open();
  late Future<_CollectionView> _view = _load(0);
  int _selected = 0;

  Future<SqliteRecordingRepository> _open() async {
    final support = await getApplicationSupportDirectory();
    final sandbox = Directory(p.join(support.path, 'phase5_rehearsal'));
    await sandbox.create(recursive: true);
    return SqliteRecordingRepository.open(
      p.join(sandbox.path, 'editor-samples.sqlite'),
    );
  }

  Future<_CollectionView> _load(int selected) async {
    final recipe = phase5Templates[selected];
    final db = await _repository;
    final collectionId = await db.transaction((tx) async {
      final existing = (await tx.loadHostState(
        'phase5.collections',
      ))[recipe.id];
      if (existing != null) return existing;
      await tx.saveTemplate(
        recipe,
        maxActiveFields: selected < 2 ? cpdActiveFieldLimit : null,
      );
      final collection = await tx.createCollection(recipe.label);
      await tx.applyTemplate(
        collection.id,
        recipe,
        expectedVersion: 1,
        maxActiveFields: selected < 2 ? cpdActiveFieldLimit : null,
      );
      await tx.saveHostValue('phase5.collections', recipe.id, collection.id);
      return collection.id;
    });
    return _CollectionView(
      db,
      collectionId,
      await db.loadLayouts(collectionId),
      await db.loadRecords(collectionId),
      isCpd: selected < 2,
    );
  }

  void _refresh() => setState(() => _view = _load(_selected));

  Future<void> _editor(_CollectionView contents) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute<LayoutRevision>(
        builder: (_) => EditFieldsPage(
          title: phase5Templates[_selected].localizedLabel(
            Localizations.localeOf(context).toLanguageTag(),
          ),
          layout: contents.active,
          library: contents.isCpd ? phase5Library : equipmentLibrary,
          maxActiveFields: contents.isCpd ? cpdActiveFieldLimit : null,
          protectedDefinitionIds: contents.isCpd
              ? cpdFieldKinds.keys.toSet()
              : const {},
          save: (draft) => contents.db.transaction((tx) async {
            if (contents.isCpd) {
              checkCpdLayoutEdit(contents.active.fields, draft.fields);
            }
            return tx.saveLayoutDraft(draft);
          }),
        ),
      ),
    );
    if (mounted && result != null) _refresh();
  }

  Future<void> _record(
    _CollectionView contents, [
    RecordingRecord? record,
  ]) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _RecordPage(contents, record: record),
      ),
    );
    if (mounted) _refresh();
  }

  void _templatePreview() {
    final template = nursingPreviewTemplate(1);
    final example = nursingCompletedExample(template);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TemplatePreviewPage(
          template: template,
          profession: 'Nursing and midwifery',
          country: 'United Kingdom',
          professionalBody: 'Nursing and Midwifery Council',
          scheme: 'NMC revalidation',
          reviewed: DateTime(2026, 11, 20),
          featuresAndLimits: const [
            'Capture learning, participatory minutes, Code themes and evidence together.',
            'This activity log supports personal recording. Approved reflective accounts and regulator submission are separate.',
            'Custom Fields can later edit an adopted copy. Preview changes are temporary.',
          ],
          examples: [example, nursingCompletedExample(template, group: false)],
          sampleAttachmentLabel: 'Workshop agenda (sample)',
          sampleReport: nursingExamplePdf,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = editorStrings(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    return Scaffold(
      appBar: AppBar(title: Text(s.editorRecords)),
      body: FutureBuilder(
        future: _view,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }
          final contents = snapshot.requireData;
          return BoundedList(
            children: [
              DropdownButtonFormField<int>(
                initialValue: _selected,
                isExpanded: true,
                items: [
                  for (final (index, recipe) in phase5Templates.indexed)
                    DropdownMenuItem(
                      value: index,
                      child: Text(
                        recipe.localizedLabel(locale),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) {
                  _selected = value!;
                  _refresh();
                },
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => _editor(contents),
                    icon: const Icon(Icons.tune),
                    label: Text(s.editFields),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _record(contents),
                    icon: const Icon(Icons.add),
                    label: Text(s.editorNewRecord),
                  ),
                  TextButton.icon(
                    onPressed: _templatePreview,
                    icon: const Icon(Icons.visibility_outlined),
                    label: Text(s.editorTemplateDetails),
                  ),
                ],
              ),
              for (final (index, record) in contents.records.indexed)
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text('${s.editorExample} ${index + 1}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _record(contents, record),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _CollectionView {
  const _CollectionView(
    this.db,
    this.id,
    this.layouts,
    this.records, {
    required this.isCpd,
  });
  final SqliteRecordingRepository db;
  final String id;
  final List<LayoutRevision> layouts;
  final List<RecordingRecord> records;
  final bool isCpd;
  LayoutRevision get active => layouts.last;
}

class _RecordPage extends StatefulWidget {
  const _RecordPage(this.contents, {this.record});
  final _CollectionView contents;
  final RecordingRecord? record;
  @override
  State<_RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends State<_RecordPage> {
  late final int _version =
      widget.record?.layoutVersion ?? widget.contents.active.version;
  late final _fields = resolveFields(_version, widget.contents.layouts);
  late final _values = <String, Object>{
    if (widget.record case final record?)
      ...record.values
    else
      ...initialFieldValues(_fields),
  };
  final _changes = <String, Object?>{};
  final _sampleId = const Uuid().v4();
  String? _error;
  bool _saving = false;

  Future<void> _save() async {
    final s = editorStrings(context);
    final store = widget.contents;
    final existing = widget.record;
    setState(() => _saving = true);
    try {
      final attachments = [
        if (_values.values.whereType<List>().any(
          (value) => value.contains(_sampleId),
        ))
          RecordingAttachment(
            id: _sampleId,
            kind: AttachmentKind.link,
            locator: 'https://example.com/sample-evidence',
            name: s.editorSampleFile,
          ),
      ];
      if (store.isCpd) {
        final bindings = cpdFieldBindings(_fields);
        final title = _values[bindings['cpd.title']] as String? ?? '';
        final detail = _values[bindings['cpd.details']] as String? ?? '';
        if (title.trim().isEmpty && detail.trim().isEmpty) {
          throw ArgumentError('No activity text.');
        }
        if (existing == null) {
          _values.putIfAbsent(bindings['cpd.creditedDuration']!, () => 0);
        }
      }
      if (existing == null) {
        await store.db.createRecord(
          store.id,
          _values,
          expectedLayoutVersion: _version,
          newAttachments: attachments,
        );
      } else {
        await store.db.updateValues(
          existing.id,
          _changes,
          expectedVersion: existing.version,
          newAttachments: attachments,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } on ArgumentError {
      if (mounted) setState(() => _error = s.editorBadRecord);
    } on StateError {
      if (mounted) setState(() => _error = s.editorSaveError);
    } on Exception {
      if (mounted) setState(() => _error = s.editorSaveError);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _change(String id, Object? value) => setState(() {
    if (value == null) {
      _values.remove(id);
    } else {
      _values[id] = value;
    }
    _changes[id] = value;
    _error = null;
  });

  @override
  Widget build(BuildContext context) {
    final s = editorStrings(context);
    final ids = widget.contents.active.fields.map((field) => field.id).toSet();
    final historical = _fields
        .where((field) => !ids.contains(field.id))
        .toList();
    final current = _fields.where((field) => ids.contains(field.id)).toList();
    final revision = widget.contents.layouts.singleWhere(
      (layout) => layout.version == _version,
    );
    final currentIds = current.map((field) => field.id).toSet();
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.record == null ? s.editorNewRecord : s.editorExample,
          ),
          actions: [
            if (widget.record case final record?)
              IconButton(
                tooltip: s.editorExport,
                icon: const Icon(Icons.ios_share),
                onPressed: () {
                  final rows = recordExportRows(
                    record,
                    _fields,
                    locale: Localizations.localeOf(context).toLanguageTag(),
                  );
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: Text(s.editorExport)),
                        body: BoundedList(
                          children: [
                            SelectableText(
                              const JsonEncoder.withIndent(
                                '  ',
                              ).convert([recordExportHeader, ...rows]),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
        body: BoundedList(
          children: [
            RecordingForm(
              fields: current,
              values: _values,
              headings: revision.headings
                  .where(
                    (h) =>
                        h.beforeFieldId == null ||
                        currentIds.contains(h.beforeFieldId),
                  )
                  .toList(),
              onChanged: _change,
              sampleAttachmentId: _sampleId,
            ),
            if (historical.isNotEmpty) ...[
              Semantics(
                header: true,
                child: Text(
                  s.editorHistorical,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Text(s.editorHistoryHint),
              RecordingForm(
                fields: historical,
                values: _values,
                onChanged: _change,
              ),
            ],
            if (_error case final error?)
              Semantics(
                liveRegion: true,
                child: Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
        bottomNavigationBar: EditorActions(
          onCancel: _saving ? null : () => Navigator.of(context).pop(),
          onSave: _saving ? null : _save,
          saveLabel: s.save,
        ),
      ),
    );
  }
}
