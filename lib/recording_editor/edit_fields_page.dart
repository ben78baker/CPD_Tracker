import 'package:flutter/material.dart';

import '../recording_engine/field_library.dart';
import '../recording_engine/layout_draft.dart';
import '../recording_engine/models.dart';
import 'field_picker.dart';
import 'field_settings.dart';
import 'record_form.dart';
import 'strings.dart';
import 'template_preview.dart';

class EditFieldsPage extends StatefulWidget {
  const EditFieldsPage({
    super.key,
    required this.title,
    required this.layout,
    required this.library,
    required this.save,
    this.maxActiveFields,
    this.protectedDefinitionIds = const {},
    this.initialDraft,
    this.initiallyDirty = false,
    this.arrangementOnly = false,
    this.suppliedLayout,
    this.reportExclusions,
    this.requiredReportDefinitions = const {},
    this.fieldsWithValues,
    this.onDraftChanged,
    this.onCancel,
    this.onReviewTemplate,
  });

  final String title;
  final LayoutRevision layout;
  final FieldLibrary library;
  final Future<String> Function(LayoutDraft draft, Set<String> excluded) save;
  final int? maxActiveFields;
  final Set<String> protectedDefinitionIds;
  final LayoutDraft? initialDraft;
  final bool initiallyDirty;
  final bool arrangementOnly;
  final LayoutRevision? suppliedLayout;
  final Set<String>? reportExclusions;
  final Set<String> requiredReportDefinitions;
  final Set<String>? fieldsWithValues;
  final Future<void> Function(LayoutDraft, Set<String>)? onDraftChanged;
  final Future<void> Function()? onCancel;
  final void Function(BuildContext)? onReviewTemplate;

  @override
  State<EditFieldsPage> createState() => _EditFieldsPageState();
}

enum _FieldAction { remove, report, settings, up, down }

enum _TemplateAction { reset, review }

class _EditFieldsPageState extends State<EditFieldsPage> {
  late var _draft = widget.initialDraft == null
      ? LayoutDraft(widget.layout, maxActiveFields: widget.maxActiveFields)
      : LayoutDraft.fromJson(
          widget.initialDraft!.toJson(),
          maxActiveFields: widget.maxActiveFields,
        );
  late final _reportExclusions = <String>{...?widget.reportExclusions};
  late bool _dirty = widget.initiallyDirty;
  bool _cancelling = false;
  bool _saving = false;
  bool _leaving = false;
  String? _error;
  String? _announcement;

  bool get _atCapacity =>
      _draft.activeFieldCount >= (widget.maxActiveFields ?? double.infinity);
  bool _protected(LayoutField? field) =>
      widget.protectedDefinitionIds.contains(field?.definition.id) ||
      widget.requiredReportDefinitions.contains(field?.definition.id) ||
      (widget.arrangementOnly && field?.required == true);

  List<LayoutField> get _missingSupplied {
    final active = _draft.fields.map((field) => field.id).toSet();
    return (widget.suppliedLayout?.fields ?? const <LayoutField>[])
        .where((field) => !active.contains(field.id))
        .toList();
  }

  Future<void> _resetTemplate() async {
    final s = editorStrings(context);
    if (!await editorConfirmation(
          context,
          s.p6RestoreDefaults,
          s.p6ResetHint,
          s.p6RestoreDefaults,
        ) ||
        !mounted) {
      return;
    }
    final supplied = widget.suppliedLayout!;
    final replacement = LayoutDraft(
      LayoutRevision(
        collectionId: _draft.collectionId,
        version: _draft.baseVersion,
        fields: const [],
      ),
      maxActiveFields: widget.maxActiveFields,
    );
    for (final field in supplied.fields) {
      replacement.reinstate(field);
    }
    replacement.setHeadings(supplied.headings);
    _change(() {
      _draft = replacement;
      _reportExclusions.clear();
    });
  }

  Future<void> _reinstate() async {
    final selected = await showModalBottomSheet<LayoutField>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final field in _missingSupplied)
              ListTile(
                title: Text(
                  field.localizedLabel(
                    Localizations.localeOf(context).toLanguageTag(),
                  ),
                ),
                onTap: () => Navigator.pop(context, field),
              ),
          ],
        ),
      ),
    );
    if (mounted && selected != null) _change(() => _draft.reinstate(selected));
  }

  /// Indexing headings and fields in visible order makes both drag and menu
  /// reordering operate on the same sequence.
  List<({String id, LayoutField? field, SectionHeading? heading})> get _items =>
      [
        for (final field in _draft.fields) ...[
          for (final heading in _draft.headings.where(
            (h) => h.beforeFieldId == field.id,
          ))
            (id: heading.id, field: null, heading: heading),
          (id: field.id, field: field, heading: null),
        ],
        for (final heading in _draft.headings.where(
          (h) => h.beforeFieldId == null,
        ))
          (id: heading.id, field: null, heading: heading),
      ];

  void _applyOrder(
    List<({String id, LayoutField? field, SectionHeading? heading})> items,
  ) {
    final fieldIds = items
        .where((item) => item.field != null)
        .map((item) => item.id);
    for (final (index, id) in fieldIds.indexed) {
      _draft.move(id, index);
    }
    final headings = <SectionHeading>[];
    String? anchor;
    for (final item in items.reversed) {
      if (item.heading case final heading?) {
        headings.add(
          SectionHeading(heading.id, heading.label, beforeFieldId: anchor),
        );
      } else {
        anchor = item.id;
      }
    }
    _draft.setHeadings(headings.reversed);
  }

  void _move(int from, int to) {
    if (from == to || _saving) return;
    final items = _items;
    final item = items.removeAt(from);
    items.insert(to, item);
    final s = editorStrings(context);
    _change(() {
      _applyOrder(items);
      final label =
          item.field?.localizedLabel(
            Localizations.localeOf(context).toLanguageTag(),
          ) ??
          item.heading!.label;
      _announcement = '$label. ${s.editorPosition(to + 1, items.length)}';
    });
  }

  Future<void> _add() async {
    final result = await showFieldPicker(
      context,
      library: widget.library,
      atCapacity: _atCapacity,
      usedLibraryIds: {
        for (final field in _draft.fields)
          if (field.source case final source?) source.id,
      },
    );
    if (!mounted || result == null) return;
    _change(() {
      if (result.heading) {
        _draft.setHeadings([
          ..._draft.headings,
          SectionHeading(result.field.id, result.field.label),
        ]);
      } else {
        _draft.add(result.field, applyToExisting: result.retrospective);
      }
    });
  }

  Future<void> _edit(LayoutField? field, SectionHeading? heading) async {
    final source =
        field ??
        LayoutField(
          id: heading!.id,
          labelOverride: heading.label,
          definition: FieldDefinition(
            id: heading.id,
            version: 1,
            label: heading.label,
            kind: FieldKind.text,
          ),
        );
    final result = await Navigator.of(context).push(
      MaterialPageRoute<FieldSettingsResult>(
        builder: (_) => FieldSettingsPage(
          field: source,
          heading: heading != null,
          protected: _protected(field),
        ),
      ),
    );
    if (!mounted || result == null) return;
    _change(() {
      if (heading != null) {
        _draft.setHeadings([
          for (final previous in _draft.headings)
            if (previous.id == heading.id)
              SectionHeading(
                heading.id,
                result.field.label,
                beforeFieldId: heading.beforeFieldId,
              )
            else
              previous,
        ]);
      } else if (source.id != result.field.id) {
        _draft.replace(source.id, result.field);
        if (_reportExclusions.contains(source.id)) {
          _reportExclusions.add(result.field.id);
        }
      } else {
        _draft.configure(result.field);
      }
    });
  }

  Future<void> _remove(String id, LayoutField? field) async {
    if (_protected(field)) return;
    final s = editorStrings(context);
    final hasHistory =
        field != null &&
        (widget.fieldsWithValues?.contains(id) ??
            widget.layout.fields.any((original) => original.id == id));
    if (hasHistory &&
        !await editorConfirmation(
          context,
          s.editorDeleteField,
          s.editorRemoveHint,
          s.editorDeleteField,
        )) {
      return;
    }
    if (!mounted) return;
    _change(() {
      final remaining = _items.where((item) => item.id != id).toList();
      if (field != null) _draft.retire(id);
      _applyOrder(remaining);
    });
  }

  Future<void> _cancel() async {
    if (_saving || _leaving || _cancelling) return;
    _cancelling = true;
    final s = editorStrings(context);
    try {
      if (_dirty &&
          !await editorConfirmation(
            context,
            s.editorDiscard,
            s.editorUnsaved,
            s.editorDiscardAction,
          )) {
        return;
      }
      if (!mounted) return;
      setState(() => _saving = true);
      await widget.onCancel?.call();
      if (!mounted) return;
      setState(() => _leaving = true);
      Navigator.of(context).pop();
    } on Object {
      _showSaveError();
    } finally {
      _cancelling = false;
      if (mounted && !_leaving) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    if (_saving || _cancelling) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.save(
        _draft,
        Set.unmodifiable(_reportExclusions),
      );
      if (!mounted) return;
      setState(() => _leaving = true);
      Navigator.of(context).pop(saved);
    } on Exception {
      _showSaveError();
    } on StateError {
      _showSaveError();
    } on ArgumentError {
      _showSaveError();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSaveError() {
    if (mounted) {
      setState(() => _error = editorStrings(context).editorSaveError);
    }
  }

  void _change(VoidCallback change) {
    setState(() {
      change();
      _dirty = true;
      _error = null;
    });
    final autosave = widget.onDraftChanged;
    if (autosave != null) {
      autosave(
        _draft,
        Set.unmodifiable(_reportExclusions),
      ).catchError((Object _) => _showSaveError());
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = editorStrings(context);
    final items = _items;
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_saving && (_leaving || !_dirty && widget.onCancel == null),
      onPopInvokedWithResult: (popped, _) {
        if (!popped) _cancel();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(s.editFields),
          actions: [
            if (widget.suppliedLayout != null)
              PopupMenuButton<_TemplateAction>(
                enabled: !_saving,
                onSelected: (action) => switch (action) {
                  _TemplateAction.reset => _resetTemplate(),
                  _TemplateAction.review => widget.onReviewTemplate?.call(
                    context,
                  ),
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: _TemplateAction.reset,
                    child: Text(s.p6RestoreDefaults),
                  ),
                  if (widget.onReviewTemplate != null)
                    PopupMenuItem(
                      value: _TemplateAction.review,
                      child: Text(s.p6TemplateUpdate),
                    ),
                ],
              ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Text(
                        widget.maxActiveFields == null
                            ? s.editorCount(_draft.activeFieldCount)
                            : s.editorFullCount(
                                _draft.activeFieldCount,
                                widget.maxActiveFields!,
                              ),
                      ),
                      if (!widget.arrangementOnly)
                        FilledButton.icon(
                          key: const Key('open-add-field'),
                          onPressed: _saving ? null : _add,
                          icon: const Icon(Icons.add),
                          label: Text(s.addField),
                        ),
                      if (widget.suppliedLayout != null)
                        OutlinedButton.icon(
                          onPressed:
                              _saving || _atCapacity || _missingSupplied.isEmpty
                              ? null
                              : _reinstate,
                          icon: const Icon(Icons.restore),
                          label: Text(s.p6RestoreField),
                        ),
                    ],
                  ),
                ),
                if (_atCapacity)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(s.editorLimit),
                  ),
                if (_announcement != null)
                  Semantics(
                    container: true,
                    liveRegion: true,
                    label: _announcement,
                    child: const SizedBox(height: 1),
                  ),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    buildDefaultDragHandles: false,
                    itemCount: items.length,
                    onReorder: (from, to) =>
                        _move(from, to > from ? to - 1 : to),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final field = item.field;
                      final heading = item.heading;
                      final locked = _protected(field);
                      final label =
                          field?.localizedLabel(
                            Localizations.localeOf(context).toLanguageTag(),
                          ) ??
                          heading!.label;
                      return Padding(
                        key: ValueKey(item.id),
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: locked
                                      ? Tooltip(
                                          message: s.editorProtectedReason,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.lock_outline,
                                                color: colors.primary,
                                                size: 18,
                                              ),
                                              const SizedBox(width: 6),
                                              Flexible(
                                                child: Text(s.editorProtected),
                                              ),
                                            ],
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                                Tooltip(
                                  message: s.editorDrag,
                                  triggerMode: TooltipTriggerMode.manual,
                                  child: ReorderableDragStartListener(
                                    enabled: !_saving,
                                    key: ValueKey('drag-${item.id}'),
                                    index: index,
                                    child: const ColoredBox(
                                      color: Colors.transparent,
                                      child: SizedBox(
                                        width: 48,
                                        height: 48,
                                        child: Icon(Icons.drag_handle),
                                      ),
                                    ),
                                  ),
                                ),
                                PopupMenuButton<_FieldAction>(
                                  key: ValueKey('menu-${item.id}'),
                                  tooltip: '${s.menuTooltip}: $label',
                                  enabled: !_saving,
                                  onSelected: (action) => switch (action) {
                                    _FieldAction.remove => _remove(
                                      item.id,
                                      field,
                                    ),
                                    _FieldAction.report => _change(() {
                                      if (!_reportExclusions.remove(item.id)) {
                                        _reportExclusions.add(item.id);
                                      }
                                    }),
                                    _FieldAction.settings => _edit(
                                      field,
                                      heading,
                                    ),
                                    _FieldAction.up => _move(index, index - 1),
                                    _FieldAction.down => _move(
                                      index,
                                      index + 1,
                                    ),
                                  },
                                  itemBuilder: (_) => [
                                    PopupMenuItem(
                                      value: _FieldAction.remove,
                                      enabled:
                                          !locked &&
                                          (!widget.arrangementOnly ||
                                              field != null),
                                      child: Text(
                                        field == null
                                            ? s.editorRemove
                                            : s.editorDeleteField,
                                      ),
                                    ),
                                    if (field != null &&
                                        widget.reportExclusions != null)
                                      PopupMenuItem(
                                        value: _FieldAction.report,
                                        enabled:
                                            _reportExclusions.contains(
                                              item.id,
                                            ) ||
                                            !widget.requiredReportDefinitions
                                                .contains(field.definition.id),
                                        child: Text(
                                          _reportExclusions.contains(item.id)
                                              ? s.editorIncludeInReports
                                              : s.editorRemoveFromReports,
                                        ),
                                      ),
                                    PopupMenuItem(
                                      value: _FieldAction.settings,
                                      enabled: !widget.arrangementOnly,
                                      child: Text(s.editorSettings),
                                    ),
                                    PopupMenuItem(
                                      value: _FieldAction.up,
                                      enabled: index > 0,
                                      child: Text(s.editorMoveUp),
                                    ),
                                    PopupMenuItem(
                                      value: _FieldAction.down,
                                      enabled: index + 1 < items.length,
                                      child: Text(s.editorMoveDown),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            if (field != null)
                              RecordingFieldTile(
                                field: field,
                                value: field.defaultValue,
                                requireValue: field.required,
                              )
                            else
                              Semantics(
                                header: true,
                                child: ListTile(
                                  tileColor: colors.surfaceContainerLow,
                                  leading: const Icon(Icons.title),
                                  title: Text(heading!.label),
                                  subtitle: Text(s.editorHeading),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                if (_saving) const LinearProgressIndicator(),
                if (_error case final error?)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(error, style: TextStyle(color: colors.error)),
                    ),
                  ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 6,
              children: [
                TextButton(
                  onPressed: _saving ? null : _cancel,
                  child: Text(s.cancel),
                ),
                OutlinedButton.icon(
                  onPressed: _saving
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => SandboxFormPage(
                              title: s.editorPreview,
                              fields: _draft.fields,
                              headings: _draft.headings,
                              example: initialFieldValues(_draft.fields),
                            ),
                          ),
                        ),
                  icon: const Icon(Icons.visibility_outlined),
                  label: Text(s.editorPreview),
                ),
                FilledButton(
                  onPressed: _dirty && !_saving ? _save : null,
                  child: Text(s.save),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
