import '../models.dart';

/// The existing CPD-facing record contract. Selection and duration arithmetic
/// stay here so either persistence path feeds the same screens and exports.
abstract class CpdRecordStore {
  Future<List<CpdEntry>> loadAll();
  Future<void> saveEntry(CpdEntry entry);
  Future<void> updateEntry(CpdEntry updated);
  Future<void> setDeleted(int id, bool deleted);
  Future<CpdEntry> createAndSave({
    required String profession,
    required DateTime date,
    required String title,
    required String details,
    required int hours,
    required int minutes,
    required List<String> attachments,
  });

  Future<List<CpdEntry>> loadDeleted() async {
    final entries = (await loadAll()).where((entry) => entry.deleted).toList();
    entries.sort((a, b) => b.date.compareTo(a.date));
    return entries;
  }

  Future<List<CpdEntry>> loadForProfession(String profession) async {
    final all = await loadAll();
    return all
        .where(
          (e) =>
              cpdProfessionKey(e.profession) == cpdProfessionKey(profession) &&
              !e.deleted,
        )
        .toList();
  }

  /// Sum of minutes for [profession] where entry date is in [start, end)
  /// and entry is not deleted.
  Future<int> sumMinutesForRange(
    String profession,
    DateTime start,
    DateTime end,
  ) async {
    final all = await loadAll();
    final p = cpdProfessionKey(profession);

    int total = 0;
    for (final e in all) {
      if (e.deleted) continue;
      if (cpdProfessionKey(e.profession) != p) continue;

      final d = e.date;
      final inRange = !d.isBefore(start) && d.isBefore(end); // [start, end)
      if (!inRange) continue;

      total += e.hours * 60 + e.minutes;
    }
    return total;
  }
}

abstract interface class CpdProfessionStore {
  Future<List<String>> loadProfessions();
  Future<List<String>> loadActiveProfessions();
  Future<List<String>> loadDeletedProfessions();
  Future<void> addProfession(String value);
  Future<void> renameProfession(String oldValue, String newValue);
  Future<void> softDeleteProfession(String value);
  Future<void> restoreProfession(String value);
  Future<void> restoreRecord(int id, {bool recoverProfession = false});

  Future<(int minutes, String cycle)?> getTarget(String profession);
  Future<void> setTarget(
    String profession, {
    required int minutes,
    required String cycle,
  });
  Future<void> clearTarget(String profession);
  Future<int> sumMinutesForRange(
    String profession,
    DateTime start,
    DateTime end,
  );
}

/// Hosts can supply both stores together so a staged workflow has one writer.
abstract class CpdDataStore extends CpdRecordStore
    implements CpdProfessionStore {}

String cpdProfessionKey(String value) => value.trim().toLowerCase();

String cpdProfessionLabel(String value) {
  final label = value.trim();
  if (label.isEmpty) return '';
  if (label.length == 1) return label.toUpperCase();
  return label[0].toUpperCase() + label.substring(1).toLowerCase();
}

const cpdTargetCycles = ['week', 'month', 'year'];
