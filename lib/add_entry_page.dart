import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'entry_repository.dart';
import 'models.dart';
import 'settings_store.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'utils/date_utils.dart';
import 'widgets/attachment_tile.dart';
import 'utils/attachment_io.dart';
import 'widgets/duration_fields.dart';


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
    // ignore: use_build_context_synchronously
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
        title: const Text('Future date not allowed'),
        content: const Text('You can only add CPD entries dated today or earlier.'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
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

      // Bottom sheet with common attachment sources
      final choice = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Take photo'),
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Photo library'),
                onTap: () => Navigator.pop(ctx, 'gallery'),
              ),
              ListTile(
                leading: const Icon(Icons.attach_file),
                title: const Text('Choose file'),
                onTap: () => Navigator.pop(ctx, 'file'),
              ),
              ListTile(
                leading: const Icon(Icons.qr_code_scanner),
                title: const Text('Scan QR code'),
                onTap: () => Navigator.pop(ctx, 'qr'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
      if (!mounted) return;

      if (choice == null) return;

      try {
        if (choice == 'camera') {
          final picker = ImagePicker();
          final shot = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
          if (shot != null && mounted) {
            setState(() => _attachments.add(shot.path));
          }
        } else if (choice == 'gallery') {
          final picker = ImagePicker();
          final img = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
          if (img != null && mounted) {
            setState(() => _attachments.add(img.path));
          }
        } else if (choice == 'file') {
          final res = await FilePicker.platform.pickFiles(allowMultiple: false);
          if (res != null && res.files.isNotEmpty) {
            final path = res.files.single.path;
            if (path != null && mounted) {
              setState(() => _attachments.add(path));
            }
          }
        } else if (choice == 'qr') {
          // Navigate without a generic; accept whatever the route returns.
          final dynamic r = await Navigator.of(context).pushNamed('/scan');
          if (!mounted) return;

          final String? result = (r is String && r.trim().isNotEmpty) ? r.trim() : null;
          if (result != null) {
            setState(() => _attachments.add(result));
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No QR data captured.')),
            );
          }
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Attachment failed: $e')),
        );
      }
    } finally {
      _pickingAttachment = false;
    }
  }

  void _removeAttachment(int i) => setState(() => _attachments.removeAt(i));

  Future<void> _save() async {
    // Ensure keyboard is dismissed before saving / navigating
    FocusScope.of(context).unfocus();
    await Future.delayed(const Duration(milliseconds: 50));

    final today = dateOnly(DateTime.now());
    final selected = dateOnly(_date);
    if (selected.isAfter(today)) {
      await _showFutureDateWarning();
      return;
    }

    final hours = _hoursVal;
    final minutes = _minutesVal;

    if (_title.text.trim().isEmpty && _details.text.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a title or details.')),
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
      await _repo.updateEntry(updated);
    } else {
      await _repo.createAndSave(
        profession: widget.profession,
        date: selected,
        title: _title.text.trim(),
        details: _details.text.trim(),
        hours: hours,
        minutes: minutes,
        attachments: List<String>.from(_attachments),
      );
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_editing ? 'Entry updated' : 'Entry saved')),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = formatDate(_date, _dateFormat);
    final titleText = _editing ? 'Edit Entry' : 'New Entry – ${widget.profession}';

    return Scaffold(
      appBar: AppBar(title: Text(titleText)),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              // Profession (read-only)
              Text('Profession', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 4),
              Text(widget.profession, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),

              // Date
              Text('Date', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 4),
              OutlinedButton(
                onPressed: _pickDate,
                child: Align(alignment: Alignment.centerLeft, child: Text(dateLabel)),
              ),
              const SizedBox(height: 16),

              // Title
              TextFormField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Title'),
                maxLength: 150,
                validator: (v) => (v ?? '').trim().isEmpty ? 'Please enter a title' : null,
              ),
              const SizedBox(height: 8),

              // Details
              TextFormField(
                controller: _details,
                decoration: const InputDecoration(labelText: 'Details'),
                maxLines: 4,
              ),
              const SizedBox(height: 16),

              // Time
              Text('Time', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 4),
              DurationFields(
                hours: _hoursVal,
                minutes: _minutesVal,
                onChanged: (h, m) => setState(() {
                  _hoursVal = h;
                  _minutesVal = m;
                }),
              ),

              const SizedBox(height: 16),

              // Attachments
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Attachments (evidence)', style: Theme.of(context).textTheme.labelMedium),
                  TextButton.icon(onPressed: _addAttachment, icon: const Icon(Icons.add), label: const Text('Add')),
                ],
              ),
              if (_attachments.isEmpty)
                const Text('No attachments added.')
              else
                ..._attachments.asMap().entries.map((entry) {
                  final i = entry.key;
                  final value = entry.value;
                  return AttachmentTile(
                    value: value,
                    onRemove: () => _removeAttachment(i),
                  );
                }),

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(onPressed: _save, child: Text(_editing ? 'Save Changes' : 'Save Entry')),
              ),
              const SizedBox(height: 8),
              const Text(
                'Note: Attachments won’t be shown in shared reports; a note will indicate evidence is available on request.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}