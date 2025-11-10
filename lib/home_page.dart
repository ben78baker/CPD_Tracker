import 'package:flutter/material.dart';
import 'settings_store.dart';
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
  List<String> _professions = <String>[];
  List<String> _deleted = <String>[];

  Map<String, (int minutes, String cycle)?> _targets = <String, (int, String)?>{};

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
  if (!mounted) return;
  if (result != null && result.isNotEmpty) {
  final saved = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => AddEntryPage(
        profession: profession,
        prefillDate: DateTime.now(),
        prefillAttachments: [result],
        prefillTitle: _suggestTitleFromScan(result),
      ),
    ),
  );
  if (!mounted) return;
  if (saved == true) {
    setState(() { _progressBump++; }); // only bump if an entry was actually saved
  }
}}

int _progressBump = 0; // increment to force _TargetProgress to refresh

  @override
void initState() {
  super.initState();
  WidgetsBinding.instance.addPostFrameCallback((_) => _load());
}

  Future<void> _load() async {
    final active = await SettingsStore.instance.loadActiveProfessions();
    final deleted = await SettingsStore.instance.loadDeletedProfessions();
    final targets = <String, (int, String)?>{};
  for (final p in active) {
    targets[p] = await SettingsStore.instance.getTarget(p);
  }

  if (!mounted) return;
  setState(() {
    _professions = List.of(active);
    _deleted = List.of(deleted);
    _targets = targets; // NEW
  });
}
  // --- Target helpers -------------------------------------------------------
  int _scaleMinutes(int minutes, String fromCycle, String toCycle) {
  if (fromCycle == toCycle) return minutes;

  const wPerY = 52.0;
  const mPerY = 12.0;
  const wPerM = wPerY / mPerY; // ~4.3333

  double mins = minutes.toDouble();
  double factor = 1.0;

  if (fromCycle == 'week' && toCycle == 'year') {
    factor = wPerY;
  } else if (fromCycle == 'year' && toCycle == 'week') {
    factor = 1 / wPerY;
  } else if (fromCycle == 'month' && toCycle == 'year') {
    factor = mPerY;
  } else if (fromCycle == 'year' && toCycle == 'month') {
    factor = 1 / mPerY;
  } else if (fromCycle == 'week' && toCycle == 'month') {
    factor = wPerM;
  } else if (fromCycle == 'month' && toCycle == 'week') {
    factor = 1 / wPerM;
  }

  return (mins * factor).round();
}

  Future<void> _editTarget(String profession) async {
    final current = _targets[profession];
    int minutes = current?.$1 ?? 60; // default 1h
    String cycle = current?.$2 ?? 'week';

    final hoursCtrl = TextEditingController(text: (minutes ~/ 60).toString());
    final minsCtrl = TextEditingController(text: (minutes % 60).toString());
    String selected = cycle;

    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text('Set Target for $profession'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selected,
                items: const [
                  DropdownMenuItem(value: 'week', child: Text('per week')),
                  DropdownMenuItem(value: 'month', child: Text('per month')),
                  DropdownMenuItem(value: 'year', child: Text('per year')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  final h = int.tryParse(hoursCtrl.text) ?? 0;
                  final m = int.tryParse(minsCtrl.text) ?? 0;
                  final total = h * 60 + m;
                  final scaled = _scaleMinutes(total, selected, v);
                  setSt(() {
                    selected = v;
                    hoursCtrl.text = (scaled ~/ 60).toString();
                    minsCtrl.text = (scaled % 60).toString();
                  });
                },
                decoration: const InputDecoration(labelText: 'Target period'),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: hoursCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Hours'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: minsCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Minutes'),
                  ),
                ),
              ]),
            ],
          ),
          actions: [
           TextButton(
           onPressed: () async {
            await SettingsStore.instance.clearTarget(profession);
            if (!mounted) return;
            setState(() {
            _targets = Map.of(_targets)..remove(profession);
            });
           if (context.mounted) Navigator.pop(ctx, false);
           },
           child: const Text('Disable'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
         ],
        ),
      ),
    );

    if (res == true) {
      final h = int.tryParse(hoursCtrl.text) ?? 0;
      final m = int.tryParse(minsCtrl.text) ?? 0;
      minutes = h * 60 + m;
      await SettingsStore.instance.setTarget(profession, minutes: minutes, cycle: selected);
      if (!mounted) return;
      setState(() {
        _targets = Map.of(_targets)..[profession] = (minutes, selected);
      });
    }
  }

  /// Edit the week start preference (locale/monday/saturday/sunday)
  Future<void> _editWeekStart() async {
    String current = 'locale';
    try {
      current = await SettingsStore.instance.getWeekStart();
    } catch (_) {}
    if (!mounted) return;
    String choice = current;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Week starts on'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: choice,
                items: const [
                  DropdownMenuItem(value: 'locale', child: Text('Use locale default')),
                  DropdownMenuItem(value: 'monday', child: Text('Monday')),
                  DropdownMenuItem(value: 'saturday', child: Text('Saturday')),
                  DropdownMenuItem(value: 'sunday', child: Text('Sunday')),
                ],
                onChanged: (v) {
                  if (v != null) setSt(() => choice = v);
                },
                decoration: const InputDecoration(labelText: 'Week starts on'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      if (choice == 'locale') {
        await SettingsStore.instance.clearWeekStart();
      } else {
        await SettingsStore.instance.setWeekStart(choice);
      }
      if (!mounted) return;
      setState(() {
        _progressBump++;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Week start updated')),
      );
    }
  }

  Future<int> _computeCompletedMinutes(String profession, String cycle) async {
    final now = DateTime.now();
    DateTime start, end;

    switch (cycle) {
      case 'week': {
      // BEFORE the await
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final firstDayIndexLocale =
      MaterialLocalizations.of(context).firstDayOfWeekIndex; // 0=Sun..6=Sat

        String pref = 'monday';
          try {
           pref = await SettingsStore.instance.getWeekStart();
          } catch (_) {
            // ignore and use default/locale
          }

        int firstWeekday;
          if (pref == 'sunday') {
           firstWeekday = DateTime.sunday;     // 7
          } else if (pref == 'saturday') {
            firstWeekday = DateTime.saturday;   // 6
           } else if (pref == 'monday') {
              firstWeekday = DateTime.monday;     // 1
        } else {
       // use the value we hoisted before the await
     final idx = firstDayIndexLocale;    // 0=Sun..6=Sat
    firstWeekday = (idx == 0) ? DateTime.sunday : idx + 1;
  }

  int diff = (now.weekday - firstWeekday) % 7;
  if (diff < 0) diff += 7;

  start = todayMidnight.subtract(Duration(days: diff));
  end   = start.add(const Duration(days: 7));
  break;
}
      case 'month':
        start = DateTime(now.year, now.month, 1);
        end = (now.month == 12)
            ? DateTime(now.year + 1, 1, 1)
            : DateTime(now.year, now.month + 1, 1);
        break;
      case 'year':
      default:
        start = DateTime(now.year, 1, 1);
        end = DateTime(now.year + 1, 1, 1);
        break;
    }

    // Delegates to SettingsStore (currently stubbed to 0 until DB wiring)
    return SettingsStore.instance.sumMinutesForRange(profession, start, end);
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
              if (_deleted.map((e) => e.toLowerCase()).contains(val.toLowerCase())) {
                return 'That name is in Deleted. Restore it instead.';
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
                Navigator.pop(ctx, controller.text);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (result != null && result.isNotEmpty) {
      // Persist using centralized normalize+dedupe+sort
      await SettingsStore.instance.addProfession(result);
      // Reload from store to reflect canonical formatting
      final refreshed = await SettingsStore.instance.loadActiveProfessions();
      final deleted = await SettingsStore.instance.loadDeletedProfessions();
      if (!mounted) return;
      setState(() {
        _professions = List.of(refreshed);
        _deleted = List.of(deleted);
      });
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
                Navigator.pop(ctx, controller.text);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (result != null && result.isNotEmpty) {
      // Update local list, then save via centralized save (which normalizes/dedupes/sorts)
      final next = List<String>.of(_professions);
      next[index] = result;
      await SettingsStore.instance.saveProfessions(next);
      final refreshed = await SettingsStore.instance.loadActiveProfessions();
      final deleted = await SettingsStore.instance.loadDeletedProfessions();
      if (!mounted) return;
      setState(() {
        _professions = List.of(refreshed);
        _deleted = List.of(deleted);
      });
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
    if (!mounted) return;
    if (confirmed == true) {
      final name = _professions[index];
      await SettingsStore.instance.softDeleteProfession(name);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Moved "$name" to Deleted')),
      );
    }
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
              final nav = Navigator.of(context);
              final scaffold = ScaffoldMessenger.of(context);
              if (value == 'add_profession') {
                await _addProfessionDialog();
              } else if (value == 'edit_details') {
                await nav.push(
                  MaterialPageRoute(builder: (_) => const EditDetailsPage()),
                );
                if (mounted) setState(() {});
              } else if (value == 'week_start') {
                await _editWeekStart();
              } else if (value == 'reset_tips') {
                await SettingsStore.instance.resetQrHint();
                if (!mounted) return;
                scaffold.showSnackBar(
                  const SnackBar(content: Text('Tips restored')),
                );
              } else if (value == 'view_deleted') {
                await nav.push(
                  MaterialPageRoute(builder: (_) => const DeletedProfessionsPage()),
                );
                await _load();
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: 'add_profession', child: Text('Add Profession')),
              PopupMenuItem(value: 'edit_details', child: Text('Edit Personal Details')),
              PopupMenuItem(value: 'week_start', child: Text('Set Week Start Day')),
              PopupMenuItem(value: 'reset_tips', child: Text('Reset Tips')),
              PopupMenuItem(value: 'view_deleted', child: Text('View Deleted Professions')),
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
                  target: _targets[name],
                  computeCompleted: (cycle) => _computeCompletedMinutes(name, cycle),
                  onSetTarget: () => _editTarget(name),
                  onAdd: () async {
                    final saved = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(builder: (_) => AddEntryPage(profession: name)),
                    );
                    if (mounted && saved == true) {
                      setState(() { _progressBump++; }); // force progress refresh only if saved
                    }
                  },
                  onScan: () => _scanQrAndPrefill(name),
                  onView: () => _openRecords(name),
                  onRename: () => _renameProfession(index),
                  onDelete: () => _deleteProfession(index),
                  refreshToken: _progressBump,
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
    required this.target,
    required this.computeCompleted,
    required this.onSetTarget,
    required this.refreshToken,
  });
  final int refreshToken;
  final String name;
  final VoidCallback onAdd;
  final VoidCallback onScan;
  final VoidCallback onView;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  final (int minutes, String cycle)? target;
  final Future<int> Function(String cycle) computeCompleted;
  final VoidCallback onSetTarget;

  @override
  Widget build(BuildContext context) {
    final pad = const EdgeInsets.all(16.0);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
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
                      if (value == 'set_target') onSetTarget();
                      if (value == 'rename') onRename();
                      if (value == 'delete') onDelete();
                    },
                    itemBuilder: (ctx) => const [
                      PopupMenuItem(value: 'set_target', child: Text('Set/Edit Target')),
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
              const SizedBox(height: 12),
              _TargetProgress(
                key: ValueKey('$name-$refreshToken'),
                target: target,
                computeCompleted: computeCompleted,
                onSetTarget: onSetTarget,
                refreshToken: refreshToken,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DeletedProfessionsPage extends StatefulWidget {
  const DeletedProfessionsPage({super.key});
  @override
  State<DeletedProfessionsPage> createState() => _DeletedProfessionsPageState();
}

class _DeletedProfessionsPageState extends State<DeletedProfessionsPage> {
  List<String> _deleted = <String>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await SettingsStore.instance.loadDeletedProfessions();
    if (!mounted) return;
    setState(() { _deleted = items; _loading = false; });
  }

  Future<void> _restore(String name) async {
    await SettingsStore.instance.restoreProfession(name);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Restored "$name"')),
    );
  }

  Future<void> _deleteForever(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Permanently delete?'),
        content: Text('Delete "$name" and all its records? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;

    // TODO: also delete DB records tied to this profession once DatabaseHelper support exists
    await SettingsStore.instance.removeProfession(name);
    await SettingsStore.instance.restoreProfession(name); // ensure it’s no longer marked deleted
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Deleted "$name" permanently (records not yet removed)')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Deleted Professions')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _deleted.isEmpty
              ? const Center(child: Text('No deleted professions'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _deleted.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final name = _deleted[index];
                    return Card(
                      elevation: 1,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: () => _restore(name),
                                    icon: const Icon(Icons.restore),
                                    label: const Text('Restore'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _deleteForever(name),
                                    icon: const Icon(Icons.delete_forever),
                                    label: const Text('Delete Permanently'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
class _TargetProgress extends StatefulWidget {
  const _TargetProgress({
    super.key,
    required this.target,
    required this.computeCompleted,
    required this.onSetTarget,
    required this.refreshToken,
  });
  

  final (int minutes, String cycle)? target;
  final Future<int> Function(String cycle) computeCompleted;
  final VoidCallback onSetTarget;
  final int refreshToken;

  @override
  State<_TargetProgress> createState() => _TargetProgressState();
}

class _TargetProgressState extends State<_TargetProgress> {
  (int minutes, String cycle)? _t;
  int _completed = 0;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _t = widget.target;
    _refresh();
  }

  @override
  void didUpdateWidget(covariant _TargetProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
     if (oldWidget.target != widget.target ||
      oldWidget.refreshToken != widget.refreshToken) {
      _t = widget.target;
     _refresh();
    }
  }

  Future<void> _refresh() async {
    final t = _t;
    if (t == null) return;
    setState(() => _loading = true);
    final mins = await widget.computeCompleted(t.$2);
    if (!mounted) return;
    setState(() {
      _completed = mins;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    if (_loading) {
  return const Padding(
    padding: EdgeInsets.symmetric(vertical: 8.0),
    child: LinearProgressIndicator(minHeight: 10),
  );
}
    if (t == null) {
    return OutlinedButton.icon(
      onPressed: widget.onSetTarget,
      icon: const Icon(Icons.flag_outlined),
      label: const Text('Set/Edit Target'),
    );
}

    final total = t.$1; // minutes
    final cycle = t.$2; // 'week' | 'month' | 'year'
    final ratio = total <= 0 ? 0.0 : (_completed / total).clamp(0.0, 1.0);

    final remaining = (total - _completed).clamp(0, total);
    final remainingH = remaining ~/ 60;
    final remainingM = remaining % 60;
    final cycleLabel = switch (cycle) {
      'week'  => 'this week',
      'month' => 'this month',
      _ => 'this year',
    };

    return Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(
      remaining == 0
          ? 'Target achieved $cycleLabel 🎉'
          : '$remainingH hrs, $remainingM mins remaining $cycleLabel',
    ),
    const SizedBox(height: 6),
    ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(
        minHeight: 10,
        value: ratio,
      ),
    ),
    FutureBuilder<String>(
      future: SettingsStore.instance.getWeekStart(),
      builder: (context, snapshot) {
        final val = snapshot.data ?? 'locale';
        String? label;
        switch (val) {
          case 'monday':
            label = 'Week starts on Monday';
            break;
          case 'sunday':
            label = 'Week starts on Sunday';
            break;
          case 'saturday':
            label = 'Week starts on Saturday';
            break;
          default:
            label = null; // hide when following device locale
        }
        if (label == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: (Theme.of(context).textTheme.bodyMedium?.fontSize ?? 14) - 2,
                  color: Colors.grey[600],
                ),
          ),
        );
      },
    ),
      ],
    );
  }
}
