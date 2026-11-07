import 'dart:convert';

import 'package:cpd_tracker/entry_repository.dart';
import 'package:cpd_tracker/models.dart';
import 'package:cpd_tracker/settings_store.dart';
import 'package:cpd_tracker/utils/export_selection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

CpdEntry record(int id, String profession, {bool deleted = false}) => CpdEntry(
  id: id,
  profession: profession,
  date: DateTime(2026, 1, 15),
  title: 'Course $id',
  details: 'Details',
  hours: 2,
  minutes: 15,
  attachments: ['/documents/evidence.pdf', 'https://example.com/photo.jpg'],
  deleted: deleted,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = SettingsStore.instance;
  final repo = EntryRepository();

  setUp(
    () => SharedPreferences.setMockInitialValues({
      'professions': ['Electrician', 'Nurse'],
      'deleted_professions': ['Nurse'],
      'entries_json_list': [
        record(1, 'Electrician').toJson(),
        record(2, 'Electrician', deleted: true).toJson(),
        record(3, 'Nurse').toJson(),
      ],
      'targets_v1': jsonEncode({
        'Electrician': {'minutes': 600, 'cycle': 'year'},
        'Nurse': {'minutes': 60, 'cycle': 'month'},
      }),
    }),
  );

  test(
    'rename preserves full records, attachment references, targets and deleted professions',
    () async {
      final before = await repo.loadAll();
      await store.renameProfession('Electrician', 'Engineer');
      final after = await repo.loadAll();
      for (var i = 0; i < 2; i++) {
        expect(after[i].toMap(), {
          ...before[i].toMap(),
          'profession': 'Engineer',
        });
      }
      expect(after[2].toMap(), before[2].toMap());
      expect(await store.loadProfessions(), ['Engineer', 'Nurse']);
      expect(await store.loadDeletedProfessions(), ['Nurse']);
      expect(await store.getTarget('Engineer'), (600, 'year'));
      expect(await store.getTarget('Electrician'), isNull);
      expect(await store.getTarget('Nurse'), (60, 'month'));
      await store.restoreProfession('Nurse');
      expect(await store.loadActiveProfessions(), ['Engineer', 'Nurse']);
    },
  );

  test(
    'delete and restore survive preference reload without changing records',
    () async {
      final before = (await repo.loadAll()).map((e) => e.toJson()).toList();
      await store.softDeleteProfession('electrician');
      await (await SharedPreferences.getInstance()).reload();
      expect(await store.loadActiveProfessions(), isEmpty);
      expect(await store.loadDeletedProfessions(), ['Electrician', 'Nurse']);
      await store.restoreProfession('ELECTRICIAN');
      await (await SharedPreferences.getInstance()).reload();
      expect(await store.loadActiveProfessions(), ['Electrician']);
      expect(
        (await EntryRepository().loadAll()).map((e) => e.toJson()),
        before,
      );
    },
  );

  test('restore repairs missing master name and deduplicates case', () async {
    await store.saveProfessions(['Electrician']);
    await store.restoreProfession('NURSE');
    await store.restoreProfession('nurse');
    expect(await store.loadActiveProfessions(), ['Electrician', 'Nurse']);
    expect(await store.loadDeletedProfessions(), isEmpty);
  });

  for (final destination in ['NURSE', ' nurse ']) {
    test('rename refuses deleted profession collision: $destination', () async {
      final before = (await repo.loadAll()).map((e) => e.toJson()).toList();
      await expectLater(
        store.renameProfession('Electrician', destination),
        throwsStateError,
      );
      expect((await repo.loadAll()).map((e) => e.toJson()), before);
      expect(await store.getTarget('Electrician'), (600, 'year'));
    });
  }

  test(
    'rename refuses active profession and orphan record/target collisions',
    () async {
      await store.restoreProfession('Nurse');
      await expectLater(
        store.renameProfession('Electrician', 'NURSE'),
        throwsStateError,
      );
      await repo.saveEntry(record(4, 'Orphan'));
      await expectLater(
        store.renameProfession('Electrician', 'ORPHAN'),
        throwsStateError,
      );
      await store.setTarget('Old target', minutes: 15, cycle: 'week');
      await expectLater(
        store.renameProfession('Electrician', 'old TARGET'),
        throwsStateError,
      );
      expect(await store.loadProfessions(), ['Electrician', 'Nurse']);
    },
  );

  test(
    'case-only rename retains records and target without duplicates',
    () async {
      await store.renameProfession('Electrician', ' ELECTRICIAN ');
      expect(await store.loadProfessions(), ['Electrician', 'Nurse']);
      expect(await store.getTarget('Electrician'), (600, 'year'));
      expect((await repo.loadAll()).length, 3);
    },
  );

  test('conflicting legacy targets are rejected without merging', () async {
    await store.setTarget('ELECTRICIAN', minutes: 1, cycle: 'week');
    await expectLater(
      store.renameProfession('Electrician', 'Engineer'),
      throwsStateError,
    );
    expect((await store.loadTargets()).length, 3);
  });

  test(
    'malformed targets prevent rename without overwriting saved data',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('targets_v1', 'invalid saved data');
      final before = prefs.getStringList('entries_json_list');
      await expectLater(
        store.renameProfession('Electrician', 'Engineer'),
        throwsStateError,
      );
      expect(prefs.getString('targets_v1'), 'invalid saved data');
      expect(prefs.getStringList('entries_json_list'), before);
      expect(await store.loadProfessions(), ['Electrician', 'Nurse']);
    },
  );

  test(
    'deleted listing and restoration preserve every field and attachment',
    () async {
      final deleted = await repo.loadDeleted();
      expect(deleted.map((e) => e.id), [2]);
      await store.restoreRecord(2);
      expect(await repo.loadDeleted(), isEmpty);
      expect((await repo.loadForProfession('Electrician')).map((e) => e.id), [
        1,
        2,
      ]);
      expect((await repo.loadAll())[1].toMap(), {
        ...deleted.single.toMap(),
        'deleted': false,
      });
    },
  );

  for (final missing in [true, false]) {
    test(
      'record recovery requires explicit consent for ${missing ? 'missing' : 'deleted'} profession',
      () async {
        await repo.saveEntry(record(4, 'Lost', deleted: true));
        if (!missing) await store.softDeleteProfession('Lost');
        await expectLater(store.restoreRecord(4), throwsStateError);
        expect((await repo.loadDeleted()).map((e) => e.id), contains(4));
        expect(await store.loadActiveProfessions(), isNot(contains('Lost')));
        await store.restoreRecord(4, recoverProfession: true);
        expect(await store.loadActiveProfessions(), contains('Lost'));
        expect((await repo.loadForProfession('Lost')).single.id, 4);
      },
    );
  }

  test(
    'normal records, progress and export selection exclude deleted records',
    () async {
      expect((await repo.loadForProfession('Electrician')).map((e) => e.id), [
        1,
      ]);
      expect(
        await repo.sumMinutesForRange(
          'Electrician',
          DateTime(2026),
          DateTime(2027),
        ),
        135,
      );
      final selection = CpdExportSelection.fromVisibleRecords(
        profession: 'Electrician',
        range: DateTimeRange(start: DateTime(2026), end: DateTime(2027)),
        visibleRecords: await repo.loadAll(),
      );
      expect(selection.records.map((e) => e.id), [1]);
      await store.restoreRecord(2);
      expect(
        await repo.sumMinutesForRange(
          'Electrician',
          DateTime(2026),
          DateTime(2027),
        ),
        270,
      );
    },
  );
}
