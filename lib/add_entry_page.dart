import 'package:flutter/material.dart';
import 'l10n/app_localizations.dart';
// debugPrint
import 'entry_repository.dart';
import 'models.dart';
import 'settings_store.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'utils/attachment_io.dart';
import 'utils/date_utils.dart';
import 'widgets/attachment_tile.dart';
import 'widgets/branded_headers.dart';
import 'widgets/duration_fields.dart';
import 'widgets/form_section_tile.dart';
import 'widgets/tactile_button.dart';

class AddEntryPage extends StatefulWidget {
  const AddEntryPage({
    super.key,
    required this.profession,
    this.existingEntry,
    this.prefillTitle,
    this.prefillAttachments,
    this.prefillDate,
  });

  final String profession;
  final CpdEntry? existingEntry;
  final String? prefillTitle;
  final List<String>? prefillAttachments;
  final DateTime? prefillDate;

  @override
  State<AddEntryPage> createState() => _AddEntryPageState();
}

class _AddEntryPageState extends State<AddEntryPage> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _details = TextEditingController();
  final List<String> _attachments = <String>[];
  bool _pickingAttachment = false;

  int _hoursVal = 0;
  int _minutesVal = 0;

  DateTime _date = DateTime.now();
  String _dateFormat = 'dd/MM/yyyy';
  late final bool _editing;

  final _repo = EntryRepository();
  final _settings = SettingsStore.instance;

  @override
  void initState() {
    super.initState();
    _editing = widget.existingEntry != null;

    if (_editing) {
      final e = widget.existingEntry!;
      _title.text = e.title;
      _details.text = e.details;
      _attachments.addAll(e.attachments);
      _hoursVal = e.hours;
      _minutesVal = e.minutes;
      _date = e.date;
    } else {
      _title.text = widget.prefillTitle ?? '';
      _attachments.addAll(widget.prefillAttachments ?? const <String>[]);
      final now = DateTime.now();
      _date = dateOnly(widget.prefillDate ?? now);
      _hoursVal = 0;
      _minutesVal = 0;
    }

    _loadFormat();
  }

  Future<void> _loadFormat() async {
    final fmt = await _settings.getDateFormat();
    if (mounted) setState(() => _dateFormat = fmt);
  }

  @override
  void dispose() {
    _title.dispose();
    _details.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = dateOnly(DateTime.now());
    final initial = dateOnly(_date);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(today) ? today : initial,
      firstDate: DateTime(today.year - 10),
      lastDate: today, // ⛔️ do not allow future dates
    );
    if (!mounted) return;
    if (picked != null) {
      if (dateOnly(picked).isAfter(today)) {
        await _showFutureDateWarning();
        return;
      }
      setState(() => _date = dateOnly(picked));
    }
  }

  Future<void> _showFutureDateWarning() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx)!.futureDateNotAllowedTitle),
        content: Text(AppLocalizations.of(ctx)!.futureDateNotAllowedBody),
        actions: [
          TactileButton(
            onPressed: () => Navigator.pop(ctx),
            variant: TactileButtonVariant.primary,
            child: Text(AppLocalizations.of(ctx)!.ok),
          ),
        ],
      ),
    );
  }

  Future<void> _addAttachment() async {
    if (_pickingAttachment) return; // guard against double-taps
    _pickingAttachment = true;
    try {
      if (!mounted) return;
      // Dismiss keyboard to avoid visual overlap / blocked taps
      FocusScope.of(context).unfocus();
      await Future.delayed(const Duration(milliseconds: 50));
      if (!mounted) return; // guard after async gap before using context

      // Bottom sheet with common attachment sources
      final choice = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) {
          final loc = AppLocalizations.of(ctx)!;
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_camera),
                  title: Text(loc.takePhoto),
                  onTap: () => Navigator.pop(ctx, 'camera'),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: Text(loc.photoLibrary),
                  onTap: () => Navigator.pop(ctx, 'gallery'),
                ),
                ListTile(
                  leading: const Icon(Icons.attach_file),
                  title: Text(loc.chooseFile),
                  onTap: () => Navigator.pop(ctx, 'file'),
                ),
                ListTile(
                  leading: const Icon(Icons.qr_code_scanner),
                  title: Text(loc.scanQrCode),
                  onTap: () => Navigator.pop(ctx, 'qr'),
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      );
      if (!context.mounted) return;
      if (!mounted) return;

      if (choice == null) return;

      try {
        if (choice == 'camera') {
          final picker = ImagePicker();
          final shot = await picker.pickImage(
            source: ImageSource.camera,
            imageQuality: 85,
          );
          if (shot != null && mounted) {
            final saved = await importAttachmentToApp(
              context,
              shot.path,
              displayName: p.basename(shot.path),
            );
            if (saved != null && mounted) {
              setState(() => _attachments.add(saved));
              debugPrint('[AddEntry] added (app path): $saved');
            }
          }
        } else if (choice == 'gallery') {
          final picker = ImagePicker();
          final img = await picker.pickImage(
            source: ImageSource.gallery,
            imageQuality: 85,
          );
          if (img != null && mounted) {
            final saved = await importAttachmentToApp(
              context,
              img.path,
              displayName: p.basename(img.path),
            );
            if (saved != null && mounted) {
              setState(() => _attachments.add(saved));
              debugPrint('[AddEntry] added (app path): $saved');
            }
          }
        } else if (choice == 'file') {
          final res = await FilePicker.platform.pickFiles(allowMultiple: false);
          if (res != null && res.files.isNotEmpty) {
            final path = res.files.single.path;
            if (path != null && mounted) {
              final saved = await importAttachmentToApp(
                context,
                path,
                displayName: p.basename(path),
              );
              if (saved != null && mounted) {
                setState(() => _attachments.add(saved));
                debugPrint('[AddEntry] added (app path): $saved');
              }
            }
          }
        } else if (choice == 'qr') {
          // Navigate without a generic; accept whatever the route returns.
          final dynamic r = await Navigator.of(context).pushNamed('/scan');
          if (!mounted) return;

          final String? result = (r is String && r.trim().isNotEmpty)
              ? r.trim()
              : null;
          if (result != null) {
            // If it looks like a web URL, store as-is; otherwise try to import to app dir
            if (isUrl(result)) {
              setState(() => _attachments.add(result));
              debugPrint('[AddEntry] added (url): $result');
            } else {
              final saved = await importAttachmentToApp(context, result);
              if (saved != null && mounted) {
                setState(() => _attachments.add(saved));
                debugPrint('[AddEntry] added (app path): $saved');
              }
            }
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(AppLocalizations.of(context)!.noQrDataCaptured),
              ),
            );
          }
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${AppLocalizations.of(context)!.attachmentFailed}: $e',
            ),
          ),
        );
      }
    } finally {
      _pickingAttachment = false;
    }
  }

  void _removeAttachment(int i) => setState(() => _attachments.removeAt(i));

  Future<void> _save() async {
    debugPrint('[AddEntry] _save() pressed');
    debugPrint(
      '[AddEntry] title.len=${_title.text.trim().length} details.len=${_details.text.trim().length}',
    );

    // Ensure keyboard is dismissed before saving / navigating
    FocusScope.of(context).unfocus();
    await Future.delayed(const Duration(milliseconds: 50));

    final today = dateOnly(DateTime.now());
    final selected = dateOnly(_date);
    debugPrint('[AddEntry] date selected: $selected');
    if (selected.isAfter(today)) {
      debugPrint('[AddEntry] abort: future date');
      await _showFutureDateWarning();
      return;
    }

    final hours = _hoursVal;
    final minutes = _minutesVal;

    if (_title.text.trim().isEmpty && _details.text.trim().isEmpty) {
      debugPrint('[AddEntry] abort: empty title & details');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.enterTitleOrDetails),
        ),
      );
      return;
    }

    if (_editing) {
      final orig = widget.existingEntry!;
      final updated = CpdEntry(
        id: orig.id,
        profession: widget.profession,
        date: selected,
        title: _title.text.trim(),
        details: _details.text.trim(),
        hours: hours,
        minutes: minutes,
        attachments: List<String>.from(_attachments),
        deleted: orig.deleted,
      );
      debugPrint(
        '[AddEntry] saving UPDATE with ${updated.attachments.length} attachments',
      );
      for (final a in updated.attachments) {
        debugPrint('  • $a');
      }
      await _repo.updateEntry(updated);
    } else {
      final listToSave = List<String>.from(_attachments);
      debugPrint(
        '[AddEntry] saving CREATE with ${listToSave.length} attachments',
      );
      for (final a in listToSave) {
        debugPrint('  • $a');
      }
      await _repo.createAndSave(
        profession: widget.profession,
        date: selected,
        title: _title.text.trim(),
        details: _details.text.trim(),
        hours: hours,
        minutes: minutes,
        attachments: listToSave,
      );
    }

    debugPrint('[AddEntry] DB write complete');

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _editing
              ? AppLocalizations.of(context)!.entryUpdated
              : AppLocalizations.of(context)!.entrySaved,
        ),
      ),
    );
    debugPrint('[AddEntry] save complete → popping true');
    Navigator.pop(context, true);
    debugPrint('[AddEntry] pop complete');
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final dateLabel = formatDate(_date, _dateFormat);
    final titleText = _editing ? loc.editEntry : loc.newEntry;

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: EdgeInsets.zero,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              BrandedPageHeader(
                title: titleText,
                subtitle: widget.profession,
                icon: _editing
                    ? Icons.edit_note_rounded
                    : Icons.note_add_outlined,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FormSectionTile(
                      label: loc.professionLabel,
                      icon: Icons.work_outline_rounded,
                      child: Text(
                        widget.profession,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FormSectionTile(
                      label: loc.dateLabel,
                      icon: Icons.event_outlined,
                      child: SizedBox(
                        width: double.infinity,
                        child: TactileButton(
                          key: const ValueKey('entry-date-action'),
                          onPressed: _pickDate,
                          surfaceTreatment:
                              TactileButtonSurfaceTreatment.neutral,
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_month_outlined),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  dateLabel,
                                  textAlign: TextAlign.left,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FormSectionTile(
                      label: loc.titleLabel,
                      icon: Icons.title_rounded,
                      child: TextFormField(
                        controller: _title,
                        decoration: InputDecoration(hintText: loc.titleLabel),
                        maxLength: 150,
                        validator: (v) =>
                            (v ?? '').trim().isEmpty ? loc.enterTitle : null,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FormSectionTile(
                      label: loc.detailsLabel,
                      icon: Icons.notes_rounded,
                      child: TextFormField(
                        key: const ValueKey('entry-details-field'),
                        controller: _details,
                        decoration: InputDecoration(hintText: loc.detailsLabel),
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        minLines: 4,
                        maxLines: 10,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FormSectionTile(
                      label: loc.timeLabel,
                      icon: Icons.timer_outlined,
                      child: DurationFields(
                        hours: _hoursVal,
                        minutes: _minutesVal,
                        onChanged: (h, m) => setState(() {
                          _hoursVal = h;
                          _minutesVal = m;
                        }),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FormSectionTile(
                      label: loc.attachmentsEvidence,
                      icon: Icons.attach_file_rounded,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TactileButton.icon(
                            key: const ValueKey('entry-add-attachment-action'),
                            onPressed: _addAttachment,
                            icon: const Icon(
                              Icons.add_photo_alternate_outlined,
                            ),
                            label: Text(loc.add),
                            variant: TactileButtonVariant.primary,
                            surfaceTreatment:
                                TactileButtonSurfaceTreatment.neutral,
                          ),
                          const SizedBox(height: 12),
                          if (_attachments.isEmpty)
                            Text(
                              loc.noAttachmentsAdded,
                              style: Theme.of(context).textTheme.bodyMedium,
                            )
                          else
                            ..._attachments.asMap().entries.map((entry) {
                              final i = entry.key;
                              final value = entry.value;
                              return AttachmentTile(
                                value: value,
                                onRemove: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) {
                                      final loc = AppLocalizations.of(ctx)!;
                                      return AlertDialog(
                                        title: Text(loc.removeAttachmentTitle),
                                        content: Text(loc.removeAttachmentBody),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, false),
                                            child: Text(loc.cancel),
                                          ),
                                          TactileButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, true),
                                            variant: TactileButtonVariant
                                                .destructive,
                                            child: Text(loc.remove),
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                  if (!context.mounted) return;
                                  if (confirm != true) return;
                                  _removeAttachment(i);
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        AppLocalizations.of(
                                          context,
                                        )!.attachmentRemoved,
                                      ),
                                    ),
                                  );
                                },
                              );
                            }),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: TactileButton(
                        onPressed: _save,
                        minimumSize: const Size(64, 56),
                        variant: TactileButtonVariant.primary,
                        child: Text(_editing ? loc.saveChanges : loc.saveEntry),
                      ),
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
