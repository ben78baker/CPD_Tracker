import '../models.dart';

class RecordSearch {
  /// Normalize text for case-insensitive search
  static String _normalize(String input) {
    return input.toLowerCase().trim();
  }

  /// Check if a single entry matches the query
  static bool matches(CpdEntry entry, String query) {
    if (query.trim().isEmpty) return true;

    final q = _normalize(query);

    bool contains(String? field) {
      if (field == null) return false;
      return _normalize(field).contains(q);
    }

    // Search across key fields
    if (contains(entry.title)) return true;
    if (contains(entry.details)) return true;

    // Attachments (file paths or names)
    for (final a in entry.attachments) {
      if (contains(a)) return true;
    }

    return false;
  }

  /// Filter a list of entries by query
  static List<CpdEntry> filter(List<CpdEntry> entries, String query) {
    if (query.trim().isEmpty) return entries;

    return entries.where((e) => matches(e, query)).toList();
  }

  /// Filter entries by profession AND query (useful for global search later)
  static List<CpdEntry> filterByProfession(
    List<CpdEntry> entries,
    String profession,
    String query,
  ) {
    return entries
        .where((e) => e.profession == profession)
        .where((e) => matches(e, query))
        .toList();
  }

  /// Group results by profession (useful for future home/global search UI)
  static Map<String, List<CpdEntry>> groupByProfession(
    List<CpdEntry> entries,
    String query,
  ) {
    final Map<String, List<CpdEntry>> grouped = {};

    for (final e in entries) {
      if (!matches(e, query)) continue;

      grouped.putIfAbsent(e.profession, () => []);
      grouped[e.profession]!.add(e);
    }

    return grouped;
  }
}
