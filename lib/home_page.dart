import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'add_entry_page.dart';
import 'edit_details_page.dart';
import 'qr_scan_page.dart';
import 'cpd_records_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<String> _professions = const <String>[];

  String _suggestTitleFromScan(String s) {
  final uri = Uri.tryParse(s);
  if (uri != null && (uri.hasScheme || s.startsWith('www.'))) {
    final host = uri.host.isNotEmpty ? uri.host : s;
    return 'Evidence: $host';
  }
  return s.length <= 40 ? s : s.substring(0, 40);
}

void _openRecords(String profession) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => CpdRecordsPage(profession: profession)),
  );
}

Future<void> _scanQrAndPrefill(String profession) async {
  final result = await Navigator.of(context).push<String>(
    MaterialPageRoute(builder: (_) => QrScanPage(profession: profession)),
  );
  if (result != null && result.isNotEmpty) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddEntryPage(
          profession: profession,
          prefillDate: DateTime.now(),
          prefillAttachments: [result],
          prefillTitle: _suggestTitleFromScan(result),
        ),
      ),
    );
  }
}

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _professions = prefs.getStringList('professions') ?? <String>[]);
  }

  String _cap(String s) {
    final t = s.trim();
    return t.isEmpty ? '' : t[0].toUpperCase() + t.substring(1).toLowerCase();
  }

  Future<void> _saveProfessions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('professions', _professions);
  }

  Future<void> _addProfessionDialog() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add profession'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'Enter profession'),
            validator: (v) {
              final val = v?.trim() ?? '';
              if (val.isEmpty) return 'Please enter a profession';
              if (_professions.map((e) => e.toLowerCase()).contains(val.toLowerCase())) {
                return 'That profession already exists';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, _cap(controller.text));
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      setState(() => _professions.add(result));
      await _saveProfessions();
    }
  }

  Future<void> _renameProfession(int index) async {
    final controller = TextEditingController(text: _professions[index]);
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename profession'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            validator: (v) {
              final val = v?.trim() ?? '';
              if (val.isEmpty) return 'Please enter a name';
              if (_professions.asMap().entries.any(
                    (e) => e.key != index && e.value.toLowerCase() == val.toLowerCase(),
                  )) {
                return 'That profession already exists';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, _cap(controller.text));
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      setState(() => _professions[index] = result);
      await _saveProfessions();
    }
  }

  Future<void> _deleteProfession(int index) async {
    final name = _professions[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete profession?'),
        content: Text('Remove "$name"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) {
      setState(() => _professions.removeAt(index));
      await _saveProfessions();
    }
  }

  void _openAddEntry(String profession) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AddEntryPage(profession: profession)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CPD Tracker'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Menu',
            onSelected: (value) async {
              if (value == 'add_profession') {
                await _addProfessionDialog();
              } else if (value == 'edit_details') {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const EditDetailsPage()),
                );
                if (mounted) setState(() {});
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: 'add_profession', child: Text('Add Profession')),
              PopupMenuItem(value: 'edit_details', child: Text('Edit Personal Details')),
            ],
          ),
        ],
      ),
      body: _professions.isEmpty
          ? const Center(child: Text('No professions yet. Use menu → Add Profession.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _professions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final name = _professions[index];
                return _ProfessionCard(
                  name: name,
                  onAdd: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => AddEntryPage(profession: name)),
                  ),
                  onScan: () => _scanQrAndPrefill(name),
                  onView: () => _openRecords(name),
                  onRename: () => _renameProfession(index),
                  onDelete: () => _deleteProfession(index),
                );
              },
            ),
    );
  }
}

class _ProfessionCard extends StatelessWidget {
  const _ProfessionCard({
    required this.name,
    required this.onAdd,
    required this.onScan,
    required this.onView,
    required this.onRename,
    required this.onDelete,
  });

  final String name;
  final VoidCallback onAdd;
  final VoidCallback onScan;
  final VoidCallback onView;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final pad = const EdgeInsets.all(16.0);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onView, // tap card → view records
        child: Padding(
          padding: pad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min, // important for ListView items
            children: [
              // Header: name + kebab menu
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'rename') onRename();
                      if (value == 'delete') onDelete();
                    },
                    itemBuilder: (ctx) => const [
                      PopupMenuItem(value: 'rename', child: Text('Rename Profession')),
                      PopupMenuItem(value: 'delete', child: Text('Delete Profession')),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Action row
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onAdd,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Entry'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onScan,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Scan QR'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // View records full-width
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onView,
                  icon: const Icon(Icons.list),
                  label: const Text('View Records'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}