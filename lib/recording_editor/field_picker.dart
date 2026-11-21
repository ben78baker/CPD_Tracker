import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../recording_engine/field_library.dart';
import '../recording_engine/models.dart';
import 'field_settings.dart';
import 'record_form.dart';
import 'strings.dart';
import 'template_preview.dart';

Future<FieldSettingsResult?> showFieldPicker(
  BuildContext context, {
  required FieldLibrary library,
  required Set<String> usedLibraryIds,
  bool atCapacity = false,
}) async {
  final s = editorStrings(context);
  final useLibrary = await showModalBottomSheet<bool>(
    context: context,
    builder: (context) => SafeArea(
      child: Wrap(
        children: [
          ListTile(
            title: Text(s.customField),
            leading: const Icon(Icons.edit_note),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pop(context, false),
          ),
          ListTile(
            title: Text(s.fieldLibrary),
            leading: const Icon(Icons.library_books_outlined),
            trailing: const Icon(Icons.chevron_right),
            onTap: atCapacity ? null : () => Navigator.pop(context, true),
          ),
        ],
      ),
    ),
  );
  if (useLibrary == null || !context.mounted) return null;
  return Navigator.of(context).push(
    MaterialPageRoute<FieldSettingsResult>(
      builder: (_) => useLibrary
          ? _LibraryPage(library: library, usedIds: usedLibraryIds)
          : _TypePage(headingOnly: atCapacity),
    ),
  );
}

class _TypePage extends StatelessWidget {
  const _TypePage({required this.headingOnly});
  final bool headingOnly;

  @override
  Widget build(BuildContext context) {
    final s = editorStrings(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.chooseField)),
      body: BoundedList(
        children: [
          for (final type
              in headingOnly
                  ? [EditorFieldType.heading]
                  : EditorFieldType.values)
            ListTile(
              title: Text(type.label(s)),
              leading: Icon(type.icon),
              subtitle: Text(_typeExample(type, context)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final field = _prototype(type, type.label(s));
                final result = await Navigator.of(context).push(
                  MaterialPageRoute<FieldSettingsResult>(
                    builder: (_) => FieldSettingsPage(
                      field: field,
                      inserting: true,
                      needsName: true,
                      heading: type == EditorFieldType.heading,
                    ),
                  ),
                );
                if (context.mounted && result != null) {
                  Navigator.pop(context, result);
                }
              },
            ),
        ],
      ),
    );
  }

  LayoutField _prototype(EditorFieldType type, String name) {
    final id = const Uuid().v4();
    return LayoutField(
      id: id,
      format: type.format,
      definition: FieldDefinition(
        id: id,
        version: 1,
        label: name,
        kind: type == EditorFieldType.heading ? FieldKind.text : type.kind,
        multiline: type == EditorFieldType.longText,
        decimalPlaces: type == EditorFieldType.decimal ? 2 : null,
        choices:
            type == EditorFieldType.single || type == EditorFieldType.multiple
            ? {'1': name}
            : const {},
      ),
    );
  }

  String _typeExample(EditorFieldType type, BuildContext context) {
    final s = editorStrings(context);
    return switch (type) {
      EditorFieldType.shortText => s.editorName,
      EditorFieldType.longText => s.editorHelp,
      EditorFieldType.integer => '42',
      EditorFieldType.decimal => '4.20',
      EditorFieldType.date => MaterialLocalizations.of(
        context,
      ).formatMediumDate(DateTime(2026, 11, 20)),
      EditorFieldType.duration => '90 ${s.editorMinutes}',
      EditorFieldType.single ||
      EditorFieldType.multiple => '${s.editorChoice} A / ${s.editorChoice} B',
      EditorFieldType.yesNo ||
      EditorFieldType.checkbox => '${s.editorYes} / ${s.editorNo}',
      EditorFieldType.link => 'https://example.com',
      EditorFieldType.file || EditorFieldType.photograph => s.editorSampleFile,
      EditorFieldType.heading => s.editorHeading,
    };
  }
}

class _LibraryPage extends StatefulWidget {
  const _LibraryPage({required this.library, required this.usedIds});
  final FieldLibrary library;
  final Set<String> usedIds;

  @override
  State<_LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<_LibraryPage> {
  String _query = '';
  String _category = '';

  @override
  Widget build(BuildContext context) {
    final s = editorStrings(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final visible = widget.library.search(
      _query,
      locale: locale,
      category: _category.isEmpty ? null : _category,
    );
    return Scaffold(
      appBar: AppBar(title: Text(s.fieldLibrary)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: TextField(
                  onChanged: (value) => setState(() => _query = value),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    labelText: s.editorSearch,
                    prefixIcon: const Icon(Icons.search),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: DropdownButtonFormField<String>(
                  initialValue: _category,
                  isExpanded: true,
                  items: [
                    DropdownMenuItem(value: '', child: Text(s.editorAll)),
                    for (final id in widget.library.categoryIds)
                      DropdownMenuItem(
                        value: id,
                        child: Text(
                          widget.library.categoryLabel(id, locale: locale),
                        ),
                      ),
                  ],
                  onChanged: (value) => setState(() => _category = value!),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    if (visible.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(s.editorNoResults),
                      ),
                    for (final item in visible)
                      ListTile(
                        leading: Icon(EditorFieldType.of(item.prototype).icon),
                        title: Text(item.prototype.localizedLabel(locale)),
                        subtitle: Text(
                          [
                            EditorFieldType.of(item.prototype).label(s),
                            item.localizedDescription(locale),
                            if (item.tags.isNotEmpty) item.tags.join(' · '),
                            if (widget.usedIds.contains(item.source.id))
                              s.editorAlreadyAdded,
                          ].join('\n'),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          if (widget.usedIds.contains(item.source.id) &&
                              !await editorConfirmation(
                                context,
                                s.editorAlreadyAdded,
                                item.prototype.localizedLabel(locale),
                                s.editorCreateCopy,
                              )) {
                            return;
                          }
                          if (!context.mounted) return;
                          final result = await Navigator.of(context).push(
                            MaterialPageRoute<FieldSettingsResult>(
                              builder: (_) => FieldSettingsPage(
                                field: item.instantiate(const Uuid().v4()),
                                inserting: true,
                                libraryDescription: item.localizedDescription(
                                  locale,
                                ),
                              ),
                            ),
                          );
                          if (context.mounted && result != null) {
                            Navigator.pop(context, result);
                          }
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
