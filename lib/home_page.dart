import 'package:flutter/material.dart';

import 'cpd_compatibility/cpd_data_store.dart';
import 'cpd_compatibility/cpd_targets.dart';
import 'settings_store.dart';
import 'settings_page.dart';
import 'add_entry_page.dart';
import 'edit_details_page.dart';
import 'qr_scan_page.dart';
import 'cpd_records_page.dart';
import 'deleted_records_page.dart';
import 'l10n/app_localizations.dart';
import 'global_search_page.dart';
import 'widgets/branded_headers.dart';
import 'widgets/home_shell.dart';
import 'widgets/profession_card.dart';
import 'widgets/tactile_button.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.dataStore});

  final CpdDataStore? dataStore;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final CpdProfessionStore _professionStore =
      widget.dataStore ?? SettingsStore.instance;
  List<String> _professions = <String>[];
  List<String> _deleted = <String>[];

  Map<String, (int minutes, String cycle)?> _targets =
      <String, (int, String)?>{};

  String _suggestTitleFromScan(String s) {
    final uri = Uri.tryParse(s);
    if (uri != null && (uri.hasScheme || s.startsWith('www.'))) {
      final host = uri.host.isNotEmpty ? uri.host : s;
      return 'Evidence: $host';
    }
    return s.length <= 40 ? s : s.substring(0, 40);
  }

  Future<void> _openRecords(
    String profession, {
    bool startInSearchMode = false,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CpdRecordsPage(
          recordStore: widget.dataStore,
          profession: profession,
          startInSearchMode: startInSearchMode,
        ),
      ),
    );
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    setState(() {
      _progressBump++;
    });
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
            recordStore: widget.dataStore,
            profession: profession,
            prefillDate: DateTime.now(),
            prefillAttachments: [result],
            prefillTitle: _suggestTitleFromScan(result),
          ),
        ),
      );
      if (!mounted) return;
      if (saved == true) {
        setState(() {
          _progressBump++;
        }); // only bump if an entry was actually saved
      }
    }
  }

  int _progressBump = 0; // increment to force _TargetProgress to refresh

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final active = await _professionStore.loadActiveProfessions();
    final deleted = await _professionStore.loadDeletedProfessions();
    final targets = <String, (int, String)?>{};
    for (final p in active) {
      targets[p] = await _professionStore.getTarget(p);
    }

    if (!mounted) return;
    setState(() {
      _professions = List.of(active);
      _deleted = List.of(deleted);
      _targets = targets; // NEW
    });
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
          title: Text(
            AppLocalizations.of(ctx)!.setTargetForProfession(profession),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selected,
                items: [
                  DropdownMenuItem(
                    value: 'week',
                    child: Text(AppLocalizations.of(ctx)!.perWeek),
                  ),
                  DropdownMenuItem(
                    value: 'month',
                    child: Text(AppLocalizations.of(ctx)!.perMonth),
                  ),
                  DropdownMenuItem(
                    value: 'year',
                    child: Text(AppLocalizations.of(ctx)!.perYear),
                  ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  final h = int.tryParse(hoursCtrl.text) ?? 0;
                  final m = int.tryParse(minsCtrl.text) ?? 0;
                  final total = h * 60 + m;
                  final scaled = scaleCpdTargetMinutes(total, selected, v);
                  setSt(() {
                    selected = v;
                    hoursCtrl.text = (scaled ~/ 60).toString();
                    minsCtrl.text = (scaled % 60).toString();
                  });
                },
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(ctx)!.targetPeriod,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: hoursCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(ctx)!.hoursLabel,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: minsCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: AppLocalizations.of(ctx)!.minutesLabel,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await _professionStore.clearTarget(profession);
                if (!mounted) return;
                setState(() {
                  _targets = Map.of(_targets)..remove(profession);
                });
                if (context.mounted) Navigator.pop(ctx, false);
              },
              child: Text(AppLocalizations.of(ctx)!.disable),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(AppLocalizations.of(ctx)!.cancel),
            ),
            TactileButton(
              onPressed: () => Navigator.pop(ctx, true),
              variant: TactileButtonVariant.primary,
              child: Text(AppLocalizations.of(ctx)!.save),
            ),
          ],
        ),
      ),
    );

    if (res == true) {
      final h = int.tryParse(hoursCtrl.text) ?? 0;
      final m = int.tryParse(minsCtrl.text) ?? 0;
      minutes = h * 60 + m;
      await _professionStore.setTarget(
        profession,
        minutes: minutes,
        cycle: selected,
      );
      if (!mounted) return;
      setState(() {
        _targets = Map.of(_targets)..[profession] = (minutes, selected);
      });
    }
  }

  Future<int> _computeCompletedMinutes(String profession, String cycle) async {
    final now = DateTime.now();
    var firstWeekday = DateTime.monday;
    if (cycle == 'week') {
      final localeDay = MaterialLocalizations.of(context).firstDayOfWeekIndex;
      String pref = 'monday';
      try {
        pref = await SettingsStore.instance.getWeekStart();
      } catch (_) {
        // Keep the legacy default when preferences cannot be read.
      }
      firstWeekday = switch (pref) {
        'sunday' => DateTime.sunday,
        'saturday' => DateTime.saturday,
        'monday' => DateTime.monday,
        _ => localeDay == 0 ? DateTime.sunday : localeDay + 1,
      };
    }
    final (start, end) = cpdTargetPeriod(
      now,
      cycle,
      firstWeekday: firstWeekday,
    );
    return _professionStore.sumMinutesForRange(profession, start, end);
  }

  Future<void> _addProfessionDialog() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx)!.addProfessionDialogTitle),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: AppLocalizations.of(ctx)!.enterProfessionHint,
            ),
            validator: (v) {
              final val = v?.trim() ?? '';
              if (val.isEmpty)
                return AppLocalizations.of(ctx)!.pleaseEnterProfession;
              if (_professions
                  .map((e) => e.toLowerCase())
                  .contains(val.toLowerCase())) {
                return AppLocalizations.of(ctx)!.professionAlreadyExists;
              }
              if (_deleted
                  .map((e) => e.toLowerCase())
                  .contains(val.toLowerCase())) {
                return AppLocalizations.of(
                  ctx,
                )!.professionInDeletedRestoreInstead;
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(ctx)!.cancel),
          ),
          TactileButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, controller.text);
              }
            },
            variant: TactileButtonVariant.primary,
            child: Text(AppLocalizations.of(ctx)!.addNew),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (result != null && result.isNotEmpty) {
      // Persist using centralized normalize+dedupe+sort
      await _professionStore.addProfession(result);
      // Reload from store to reflect canonical formatting
      final refreshed = await _professionStore.loadActiveProfessions();
      final deleted = await _professionStore.loadDeletedProfessions();
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
        title: Text(AppLocalizations.of(ctx)!.renameProfessionTitle),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            validator: (v) {
              final val = v?.trim() ?? '';
              if (val.isEmpty) return AppLocalizations.of(ctx)!.pleaseEnterName;
              if (_professions.asMap().entries.any(
                (e) =>
                    e.key != index &&
                    e.value.toLowerCase() == val.toLowerCase(),
              )) {
                return AppLocalizations.of(ctx)!.professionAlreadyExists;
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(ctx)!.cancel),
          ),
          TactileButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, controller.text);
              }
            },
            variant: TactileButtonVariant.primary,
            child: Text(AppLocalizations.of(ctx)!.save),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (result != null && result.isNotEmpty) {
      try {
        await _professionStore.renameProfession(_professions[index], result);
        await _load();
        if (mounted) setState(() => _progressBump++);
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is StateError
                  ? error.message
                  : 'Could not rename the profession. Please try again.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _deleteProfession(int index) async {
    final name = _professions[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx)!.deleteProfessionTitle),
        content: Text(AppLocalizations.of(ctx)!.removeProfessionConfirm(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppLocalizations.of(ctx)!.cancel),
          ),
          TactileButton(
            onPressed: () => Navigator.pop(ctx, true),
            variant: TactileButtonVariant.destructive,
            child: Text(AppLocalizations.of(ctx)!.delete),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed == true) {
      final name = _professions[index];
      await _professionStore.softDeleteProfession(name);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.movedToDeleted(name)),
        ),
      );
    }
  }

  Future<void> _selectHomeAction(String value) async {
    final nav = Navigator.of(context);
    if (value == 'add_profession') {
      await _addProfessionDialog();
    } else if (value == 'edit_details') {
      await nav.push(
        MaterialPageRoute(builder: (_) => const EditDetailsPage()),
      );
      if (mounted) setState(() {});
    } else if (value == 'settings') {
      await nav.push(MaterialPageRoute(builder: (_) => const SettingsPage()));
      if (mounted) setState(() => _progressBump++);
    } else if (value == 'deleted_records') {
      await nav.push(
        MaterialPageRoute(
          builder: (_) => DeletedRecordsPage(dataStore: widget.dataStore),
        ),
      );
      await _load();
      if (mounted) setState(() => _progressBump++);
    } else if (value == 'view_deleted') {
      await nav.push(
        MaterialPageRoute(
          builder: (_) =>
              DeletedProfessionsPage(professionStore: _professionStore),
        ),
      );
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) => HomeShell(
    onSearch: () => Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GlobalSearchPage(dataStore: widget.dataStore),
      ),
    ),
    onMenuSelected: _selectHomeAction,
    body: HomeProfessionList(
      itemCount: _professions.length,
      itemBuilder: (context, index) {
        final name = _professions[index];
        return ProfessionCard(
          name: name,
          target: _targets[name],
          computeCompleted: (cycle) => _computeCompletedMinutes(name, cycle),
          onSetTarget: () => _editTarget(name),
          onAdd: () async {
            final saved = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => AddEntryPage(
                  profession: name,
                  recordStore: widget.dataStore,
                ),
              ),
            );
            if (mounted && saved == true) {
              setState(() {
                _progressBump++;
              }); // force progress refresh only if saved
            }
          },
          onScan: () => _scanQrAndPrefill(name),
          onView: () async => _openRecords(name),
          onSearch: () async => _openRecords(name, startInSearchMode: true),
          onRename: () => _renameProfession(index),
          onDelete: () => _deleteProfession(index),
          refreshToken: _progressBump,
        );
      },
    ),
  );
}

class DeletedProfessionsPage extends StatefulWidget {
  const DeletedProfessionsPage({super.key, this.professionStore});

  final CpdProfessionStore? professionStore;
  @override
  State<DeletedProfessionsPage> createState() => _DeletedProfessionsPageState();
}

class _DeletedProfessionsPageState extends State<DeletedProfessionsPage> {
  late final CpdProfessionStore _professionStore =
      widget.professionStore ?? SettingsStore.instance;
  List<String> _deleted = <String>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _professionStore.loadDeletedProfessions();
    if (!mounted) return;
    setState(() {
      _deleted = items;
      _loading = false;
    });
  }

  Future<void> _restore(String name) async {
    await _professionStore.restoreProfession(name);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.professionRestored)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Column(
        children: [
          BrandedPageHeader(
            title: AppLocalizations.of(context)!.deletedProfessionsTitle,
            icon: Icons.work_off_outlined,
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _deleted.isEmpty
                ? Center(
                    child: Text(
                      AppLocalizations.of(context)!.noDeletedProfessions,
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: _deleted.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final name = _deleted[index];
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            BrandedSectionHeader(
                              title: name,
                              icon: Icons.work_outline_rounded,
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final loc = AppLocalizations.of(context)!;
                                  final stackActions =
                                      tactileButtonsNeedStacking(
                                        context,
                                        constraints.maxWidth,
                                        [loc.restore, loc.deletePermanently],
                                      );
                                  final restoreButton = TactileButton.icon(
                                    onPressed: () => _restore(name),
                                    icon: const Icon(Icons.restore),
                                    label: Text(
                                      AppLocalizations.of(context)!.restore,
                                    ),
                                    variant: TactileButtonVariant.primary,
                                  );
                                  final deleteButton = TactileButton.icon(
                                    onPressed: null,
                                    icon: const Icon(Icons.delete_forever),
                                    label: Text(
                                      AppLocalizations.of(
                                        context,
                                      )!.deletePermanently,
                                    ),
                                    variant: TactileButtonVariant.destructive,
                                  );
                                  if (stackActions) {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        restoreButton,
                                        const SizedBox(height: 8),
                                        deleteButton,
                                      ],
                                    );
                                  }
                                  return Row(
                                    children: [
                                      Expanded(child: restoreButton),
                                      const SizedBox(width: 8),
                                      Expanded(child: deleteButton),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
