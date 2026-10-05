import 'package:cpd_tracker/models.dart';
import 'package:cpd_tracker/utils/export_selection.dart';
import 'package:cpd_tracker/utils/record_search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const profession = 'Nursing';

  CpdEntry entry({
    required int id,
    required DateTime date,
    required String title,
    String entryProfession = profession,
    bool deleted = false,
  }) {
    return CpdEntry(
      id: id,
      profession: entryProfession,
      date: date,
      title: title,
      details: '',
      hours: 1,
      minutes: 0,
      attachments: <String>[],
      deleted: deleted,
    );
  }

  CpdExportSelection select(
    Iterable<CpdEntry> visibleRecords, {
    DateTime? start,
    DateTime? end,
  }) {
    return CpdExportSelection.fromVisibleRecords(
      profession: profession,
      range: DateTimeRange(
        start: start ?? DateTime(2026, 1, 10),
        end: end ?? DateTime(2026, 1, 20),
      ),
      visibleRecords: visibleRecords,
    );
  }

  group('CpdExportSelection', () {
    test('includes records on both inclusive date boundaries', () {
      final selection = select([
        entry(id: 1, date: DateTime(2026, 1, 10, 23, 59), title: 'Start'),
        entry(id: 2, date: DateTime(2026, 1, 20, 0, 1), title: 'End'),
      ]);

      expect(selection.records.map((record) => record.id), [1, 2]);
    });

    test('excludes records before and after the selected range', () {
      final selection = select([
        entry(id: 1, date: DateTime(2026, 1, 9), title: 'Before'),
        entry(id: 2, date: DateTime(2026, 1, 15), title: 'Inside'),
        entry(id: 3, date: DateTime(2026, 1, 21), title: 'After'),
      ]);

      expect(selection.records.map((record) => record.id), [2]);
    });

    test('exports only the currently search-filtered visible records', () {
      final records = [
        entry(id: 1, date: DateTime(2026, 1, 12), title: 'Airway course'),
        entry(id: 2, date: DateTime(2026, 1, 13), title: 'Safeguarding'),
        entry(
          id: 3,
          date: DateTime(2026, 1, 14),
          title: 'Airway course',
          entryProfession: 'Teaching',
        ),
      ];
      final visible = RecordSearch.filter(records, 'airway');

      final selection = select(visible);

      expect(selection.records.map((record) => record.id), [1]);
    });

    test('intersects search results with the inclusive date range', () {
      final records = [
        entry(id: 1, date: DateTime(2026, 1, 8), title: 'Airway before'),
        entry(id: 2, date: DateTime(2026, 1, 16), title: 'Airway inside'),
        entry(id: 3, date: DateTime(2026, 1, 17), title: 'Unrelated'),
        entry(id: 4, date: DateTime(2026, 1, 22), title: 'Airway after'),
      ];
      final visible = RecordSearch.filter(records, 'airway');

      final selection = select(visible);

      expect(selection.records.map((record) => record.id), [2]);
    });

    test('orders deterministically by date and then record id', () {
      final selection = select([
        entry(id: 5, date: DateTime(2026, 1, 15, 8), title: 'Later id'),
        entry(id: 9, date: DateTime(2026, 1, 12), title: 'Earlier date'),
        entry(id: 2, date: DateTime(2026, 1, 15, 18), title: 'Earlier id'),
      ]);

      expect(selection.records.map((record) => record.id), [9, 2, 5]);
    });

    test('provides the shared prefiltered input used by PDF and ZIP', () {
      final selection = select([
        entry(id: 1, date: DateTime(2026, 1, 5), title: 'Outside'),
        entry(id: 2, date: DateTime(2026, 1, 15), title: 'Visible'),
        entry(id: 3, date: DateTime(2026, 1, 25), title: 'Outside'),
      ]);

      // PDF and ZIP APIs accept this selection object rather than raw records,
      // so both receive exactly this already-filtered list.
      expect(selection.records.map((record) => record.title), ['Visible']);
    });
  });
}
