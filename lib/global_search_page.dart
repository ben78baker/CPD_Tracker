import 'package:flutter/material.dart';

import '../cpd_records_page.dart';
import '../entry_repository.dart';
import '../models.dart';
import '../settings_store.dart';
import '../utils/record_search.dart';

class GlobalSearchPage extends StatefulWidget {
  const GlobalSearchPage({super.key});

  @override
  State<GlobalSearchPage> createState() => _GlobalSearchPageState();
}

class _GlobalSearchPageState extends State<GlobalSearchPage> {
  final EntryRepository _repo = EntryRepository();
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  String _query = '';
  List<String> _professions = <String>[];
  List<CpdEntry> _allEntries = <CpdEntry>[];

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
    final professions = await SettingsStore.instance.loadActiveProfessions();
    final allEntries = <CpdEntry>[];

    for (final profession in professions) {
      final entries = await _repo.loadForProfession(profession);
      allEntries.addAll(entries.where((e) => !e.deleted));
    }

    if (!mounted) return;
    setState(() {
      _professions = List<String>.from(professions);
      _allEntries = allEntries;
      _loading = false;
    });
  }

  bool _professionNameMatches(String profession, String query) {
    return profession.toLowerCase().contains(query.toLowerCase().trim());
  }

  List<String> get _matchingProfessions {
    final query = _query.trim();
    if (query.isEmpty) return _professions;

    final grouped = RecordSearch.groupByProfession(_allEntries, query);
    final results = <String>{...grouped.keys};

    for (final profession in _professions) {
      if (_professionNameMatches(profession, query)) {
        results.add(profession);
      }
    }

    final list = results.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  int _matchCountForProfession(String profession) {
    final query = _query.trim();
    if (query.isEmpty) return 0;
    return RecordSearch.filterByProfession(
      _allEntries,
      profession,
      query,
    ).length;
  }

  String _recordsPageQueryForProfession(String profession) {
    final query = _query.trim();
    if (query.isEmpty) return '';

    final hasRecordMatches = RecordSearch.filterByProfession(
      _allEntries,
      profession,
      query,
    ).isNotEmpty;

    // If the profession name matched but no record content matched,
    // open the profession normally and show all its records.
    if (!hasRecordMatches && _professionNameMatches(profession, query)) {
      return '';
    }

    return query;
  }

  Future<void> _openFilteredRecords(String profession) async {
    final recordsPageQuery = _recordsPageQueryForProfession(profession);

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CpdRecordsPage(
          profession: profession,
          startInSearchMode: recordsPageQuery.isNotEmpty,
          initialSearchQuery: recordsPageQuery,
        ),
      ),
    );
    if (!mounted) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Search All Records')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
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
                          child: Text('Type to search across all professions'),
                        )
                      : _matchingProfessions.isEmpty
                      ? const Center(child: Text('No matching records found'))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: _matchingProfessions.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final profession = _matchingProfessions[index];
                            final count = _matchCountForProfession(profession);
                            final isProfessionMatch = _professionNameMatches(
                              profession,
                              _query,
                            );
                            final opensFilteredRecords = count > 0;

                            return Card(
                              elevation: 1,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      profession,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      count == 0
                                          ? (isProfessionMatch
                                                ? 'Profession name match'
                                                : 'No matching records')
                                          : '$count matching record${count == 1 ? '' : 's'}',
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        onPressed: () =>
                                            _openFilteredRecords(profession),
                                        icon: const Icon(Icons.search),
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
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
