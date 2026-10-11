import 'package:flutter/material.dart';
import 'settings_store.dart';
import 'settings_page.dart';
import 'add_entry_page.dart';
import 'edit_details_page.dart';
import 'qr_scan_page.dart';
import 'cpd_records_page.dart';
import 'l10n/app_localizations.dart';
import 'global_search_page.dart';
import 'theme/app_theme.dart';
import 'widgets/branded_headers.dart';
import 'widgets/profession_card.dart';
import 'widgets/tactile_button.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
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
                  final scaled = _scaleMinutes(total, selected, v);
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
                await SettingsStore.instance.clearTarget(profession);
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
      await SettingsStore.instance.setTarget(
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
    DateTime start, end;

    switch (cycle) {
      case 'week':
        {
          // BEFORE the await
          final todayMidnight = DateTime(now.year, now.month, now.day);
          final firstDayIndexLocale = MaterialLocalizations.of(
            context,
          ).firstDayOfWeekIndex; // 0=Sun..6=Sat

          String pref = 'monday';
          try {
            pref = await SettingsStore.instance.getWeekStart();
          } catch (_) {
            // ignore and use default/locale
          }

          int firstWeekday;
          if (pref == 'sunday') {
            firstWeekday = DateTime.sunday; // 7
          } else if (pref == 'saturday') {
            firstWeekday = DateTime.saturday; // 6
          } else if (pref == 'monday') {
            firstWeekday = DateTime.monday; // 1
          } else {
            // use the value we hoisted before the await
            final idx = firstDayIndexLocale; // 0=Sun..6=Sat
            firstWeekday = (idx == 0) ? DateTime.sunday : idx + 1;
          }

          int diff = (now.weekday - firstWeekday) % 7;
          if (diff < 0) diff += 7;

          start = todayMidnight.subtract(Duration(days: diff));
          end = start.add(const Duration(days: 7));
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
      await SettingsStore.instance.softDeleteProfession(name);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.movedToDeleted(name)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brandColors;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 16,
        backgroundColor: AppColors.canvas,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: brand.outlineVariant),
        ),
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Image.asset(
                'assets/icon/1024x1024_app_icon.png',
                key: const ValueKey('home-brand-logo'),
                width: 34,
                height: 34,
                fit: BoxFit.cover,
                excludeFromSemantics: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  AppLocalizations.of(context)!.appTitle,
                  key: const ValueKey('home-app-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: brand.onAccentLight,
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const ValueKey('home-search-action'),
            tooltip: 'Search all records',
            style: _homeHeaderActionStyle(context),
            icon: const Icon(Icons.search_rounded),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const GlobalSearchPage()),
              );
            },
          ),
          PopupMenuButton<String>(
            key: const ValueKey('home-menu-action'),
            tooltip: AppLocalizations.of(context)!.menuTooltip,
            icon: const Icon(Icons.more_vert_rounded),
            style: _homeHeaderActionStyle(context),
            onSelected: (value) async {
              final nav = Navigator.of(context);
              if (value == 'add_profession') {
                await _addProfessionDialog();
              } else if (value == 'edit_details') {
                await nav.push(
                  MaterialPageRoute(builder: (_) => const EditDetailsPage()),
                );
                if (mounted) setState(() {});
              } else if (value == 'settings') {
                await nav.push(
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                );
                if (mounted) setState(() => _progressBump++);
              } else if (value == 'view_deleted') {
                await nav.push(
                  MaterialPageRoute(
                    builder: (_) => const DeletedProfessionsPage(),
                  ),
                );
                await _load();
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'add_profession',
                child: Text(AppLocalizations.of(ctx)!.addProfession),
              ),
              PopupMenuItem(
                value: 'edit_details',
                child: Text(AppLocalizations.of(ctx)!.editPersonalDetails),
              ),
              PopupMenuItem(
                value: 'settings',
                child: Text(AppLocalizations.of(ctx)!.settings),
              ),
              PopupMenuItem(
                value: 'view_deleted',
                child: Text(AppLocalizations.of(ctx)!.viewDeletedProfessions),
              ),
            ],
          ),
        ],
      ),
      body: _professions.isEmpty
          ? Center(child: Text(AppLocalizations.of(context)!.noProfessionsYet))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              itemCount: _professions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final name = _professions[index];
                return ProfessionCard(
                  name: name,
                  target: _targets[name],
                  computeCompleted: (cycle) =>
                      _computeCompletedMinutes(name, cycle),
                  onSetTarget: () => _editTarget(name),
                  onAdd: () async {
                    final saved = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => AddEntryPage(profession: name),
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
                  onSearch: () async =>
                      _openRecords(name, startInSearchMode: true),
                  onRename: () => _renameProfession(index),
                  onDelete: () => _deleteProfession(index),
                  refreshToken: _progressBump,
                );
              },
            ),
    );
  }
}

ButtonStyle _homeHeaderActionStyle(BuildContext context) {
  final brand = context.brandColors;
  return ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size.square(48)),
    maximumSize: const WidgetStatePropertyAll(Size.square(48)),
    padding: const WidgetStatePropertyAll(EdgeInsets.zero),
    foregroundColor: WidgetStatePropertyAll(brand.accentDark),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.pressed) ||
          states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return brand.accentLight;
      }
      return Colors.transparent;
    }),
    overlayColor: WidgetStatePropertyAll(brand.accent.withValues(alpha: 0.08)),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
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
    setState(() {
      _deleted = items;
      _loading = false;
    });
  }

  Future<void> _restore(String name) async {
    await SettingsStore.instance.restoreProfession(name);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.professionRestored)),
    );
  }

  Future<void> _deleteForever(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx)!.permanentlyDeleteTitle),
        content: Text(AppLocalizations.of(ctx)!.permanentlyDeleteBody(name)),
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
    if (confirmed != true) return;

    // TODO: also delete DB records tied to this profession once DatabaseHelper support exists
    await SettingsStore.instance.removeProfession(name);
    await SettingsStore.instance.restoreProfession(
      name,
    ); // ensure it’s no longer marked deleted
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(context)!.professionDeletedPermanently(name),
        ),
      ),
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
                                    onPressed: () => _deleteForever(name),
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
