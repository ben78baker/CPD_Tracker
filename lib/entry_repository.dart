
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

class EntryRepository {
  static const _kEntries = 'entries_json_list'; // list<String> (json per entry)
  static const _kNextId = 'next_entry_id';
  

    Future<void> _saveAll(List<CpdEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kEntries, entries.map((e) => e.toJson()).toList());
  }

  Future<void> updateEntry(CpdEntry updated) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kEntries) ?? <String>[];
    final entries = list.map((s) => CpdEntry.fromJson(s)).toList();
    final idx = entries.indexWhere((e) => e.id == updated.id);
    if (idx == -1) {
      entries.add(updated);
    } else {
      entries[idx] = updated;
    }
    await _saveAll(entries);
  }

  Future<void> setDeleted(int id, bool deleted) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kEntries) ?? <String>[];
    final entries = list.map((s) => CpdEntry.fromJson(s)).toList();
    final idx = entries.indexWhere((e) => e.id == id);
    if (idx != -1) {
      final e = entries[idx];
      entries[idx] = CpdEntry(
        id: e.id,
        profession: e.profession,
        date: e.date,
        title: e.title,
        details: e.details,
        hours: e.hours,
        minutes: e.minutes,
        attachments: e.attachments,
        deleted: deleted,
      );
      await _saveAll(entries);
    }
  }

  Future<int> _consumeNextId(SharedPreferences prefs) async {
    final next = (prefs.getInt(_kNextId) ?? 1);
    await prefs.setInt(_kNextId, next + 1);
    return next;
  }

  Future<List<CpdEntry>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kEntries) ?? const <String>[];
    return list.map((s) => CpdEntry.fromJson(s)).toList();
  }

  Future<void> saveEntry(CpdEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    final all = prefs.getStringList(_kEntries) ?? <String>[];
    all.add(entry.toJson());
    await prefs.setStringList(_kEntries, all);
  }

  Future<CpdEntry> createAndSave({
    required String profession,
    required DateTime date,
    required String title,
    required String details,
    required int hours,
    required int minutes,
    required List<String> attachments,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final id = await _consumeNextId(prefs);
    final entry = CpdEntry(
      id: id,
      profession: profession,
      date: date,
      title: title,
      details: details,
      hours: hours,
      minutes: minutes,
      attachments: attachments,
      deleted: false,
    );
    await saveEntry(entry);
    return entry;
  }

  Future<List<CpdEntry>> loadForProfession(String profession) async {
    final all = await loadAll();
    return all.where((e) => e.profession.toLowerCase() == profession.toLowerCase() && !e.deleted).toList();
  }
  /// Sum of minutes for [profession] where entry date is in [start, end)
/// and entry is not deleted.
Future<int> sumMinutesForRange(String profession, DateTime start, DateTime end) async {
  final all = await loadAll();
  final p = profession.toLowerCase();

  int total = 0;
  for (final e in all) {
    if (e.deleted) continue;
    if (e.profession.toLowerCase() != p) continue;

    final d = e.date;
final inRange = !d.isBefore(start) && d.isBefore(end); // [start, end)
if (!inRange) continue;

// Coalesce hours/minutes to ints even if null/strings
final h = e.hours;
final m = e.minutes;

total += (h * 60) + m;
  }
  return total;
}
}