import 'package:flutter/material.dart';

import 'cpd_compatibility/cpd_data_store.dart';
import 'cpd_compatibility/cpd_records_source.dart';
import 'cpd_records_page.dart';
import 'entry_repository.dart';
import 'l10n/app_localizations.dart';
import 'settings_store.dart';
import 'widgets/branded_headers.dart';
import 'widgets/tactile_button.dart';

class GlobalSearchPage extends StatefulWidget {
  const GlobalSearchPage({
    super.key,
    this.dataStore,
    this.source,
    this.onOpenProfession,
    this.onOpenRecord,
  }) : assert(source == null || onOpenProfession != null);

  final CpdDataStore? dataStore;
  final CpdRecordsSource? source;
  final Future<void> Function(CpdProfessionItem, String)? onOpenProfession;
  final Future<void> Function(CpdRecordItem)? onOpenRecord;

  @override
  State<GlobalSearchPage> createState() => _GlobalSearchPageState();
}

class _GlobalSearchPageState extends State<GlobalSearchPage> {
  late final CpdRecordStore _repo = widget.dataStore ?? EntryRepository();
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  String _query = '';
  List<CpdProfessionItem> _professions = [];
  List<CpdRecordItem> _allEntries = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final source = widget.source;
    final List<CpdProfessionItem> professions;
    final List<CpdRecordItem> entries;
    if (source == null) {
      final store = widget.dataStore ?? SettingsStore.instance;
      professions = [
        for (final label in await store.loadActiveProfessions())
          (id: label, label: label, deleted: false),
      ];
      entries = [
        for (final profession in professions)
          for (final entry in await _repo.loadForProfession(profession.label))
            if (!entry.deleted)
              CpdRecordItem.legacy(entry, professionId: profession.id),
      ];
    } else {
      professions = (await source.professions())
          .where((profession) => !profession.deleted)
          .toList();
      entries = await source.records();
    }
    if (!mounted) return;
    setState(() {
      _professions = professions;
      _allEntries = entries;
      _loading = false;
    });
  }

  bool _professionNameMatches(String profession, String query) =>
      profession.toLowerCase().contains(query.toLowerCase().trim());

  List<CpdRecordItem> _matches(CpdProfessionItem profession) => _allEntries
      .where(
        (item) => item.professionId == profession.id && item.matches(_query),
      )
      .toList();

  List<CpdProfessionItem> get _matchingProfessions {
    final query = _query.trim();
    if (query.isEmpty) return _professions;
    final matches = {
      for (final item in _allEntries)
        if (item.matches(query)) item.professionId,
    };
    return _professions
        .where(
          (profession) =>
              matches.contains(profession.id) ||
              _professionNameMatches(profession.label, query),
        )
        .toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  }

  Future<void> _openFilteredRecords(CpdProfessionItem profession) async {
    final query = _matches(profession).isEmpty ? '' : _query.trim();
    if (widget.onOpenProfession case final open?) {
      await open(profession, query);
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CpdRecordsPage(
            recordStore: _repo,
            profession: profession.label,
            startInSearchMode: query.isNotEmpty,
            initialSearchQuery: query,
          ),
        ),
      );
    }
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final professions = _matchingProfessions;
    return Scaffold(
      appBar: AppBar(),
      body: Column(
        children: [
          const BrandedPageHeader(
            title: 'Search All Records',
            icon: Icons.manage_search_rounded,
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                        child: TextField(
                          controller: _searchController,
                          autofocus: true,
                          onChanged: (value) {
                            setState(() {
                              _query = value;
                            });
                          },
                          decoration: InputDecoration(
                            hintText: 'Search all professions and records',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _query.isEmpty
                                ? null
                                : IconButton(
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {
                                        _query = '';
                                      });
                                    },
                                    icon: const Icon(Icons.clear),
                                  ),
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      Expanded(
                        child: _query.trim().isEmpty
                            ? const Center(
                                child: Text(
                                  'Type to search across all professions',
                                ),
                              )
                            : professions.isEmpty
                            ? const Center(
                                child: Text('No matching records found'),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  16,
                                ),
                                itemCount: professions.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final profession = professions[index];
                                  final matches = _matches(profession);
                                  final count = matches.length;
                                  final isProfessionMatch =
                                      _professionNameMatches(
                                        profession.label,
                                        _query,
                                      );
                                  final opensFilteredRecords = count > 0;

                                  return Card(
                                    clipBehavior: Clip.antiAlias,
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        BrandedSectionHeader(
                                          title: profession.label,
                                          icon: Icons.work_outline_rounded,
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            16,
                                            8,
                                            16,
                                            16,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                count == 0
                                                    ? (isProfessionMatch
                                                          ? 'Profession name match'
                                                          : 'No matching records')
                                                    : '$count matching record${count == 1 ? '' : 's'}',
                                              ),
                                              if (widget.onOpenRecord
                                                  case final open?)
                                                for (final record in matches)
                                                  ListTile(
                                                    dense: true,
                                                    contentPadding:
                                                        EdgeInsets.zero,
                                                    title: Text(
                                                      record.entry.title.isEmpty
                                                          ? AppLocalizations.of(
                                                              context,
                                                            )!.noTitle
                                                          : record.entry.title,
                                                    ),
                                                    trailing: const Icon(
                                                      Icons.chevron_right,
                                                    ),
                                                    onTap: () async {
                                                      await open(record);
                                                      if (mounted) {
                                                        await _load();
                                                      }
                                                    },
                                                  ),
                                              const SizedBox(height: 12),
                                              SizedBox(
                                                width: double.infinity,
                                                child: TactileButton.icon(
                                                  onPressed: () =>
                                                      _openFilteredRecords(
                                                        profession,
                                                      ),
                                                  icon: const Icon(
                                                    Icons.search,
                                                  ),
                                                  label: Text(
                                                    opensFilteredRecords
                                                        ? 'Open filtered records'
                                                        : 'Open all records',
                                                  ),
                                                ),
                                              ),
                                            ],
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
          ),
        ],
      ),
    );
  }
}
