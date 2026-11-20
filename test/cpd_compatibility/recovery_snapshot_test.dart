import 'dart:convert';
import 'dart:io';

import 'package:cpd_tracker/cpd_migration/legacy_preferences_inventory.dart';
import 'package:cpd_tracker/cpd_migration/legacy_recovery_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory scratch;
  late Directory documents;
  late Directory backup;
  late File proof;
  final source = <String, Object>{
    'entries_json_list': [
      '{"known":1,"unknown":{"values":[true,null]}}',
      '{bad',
    ],
    'professions': ['Nurse'],
    'deleted_professions': [' NURSE '],
    'next_entry_id': 8,
    'targets_v1': '{"Nurse":{"minutes":60,"cycle":"month"}}',
    'profile_company': 'Synthetic example',
    'future_key': 'retained in an explicit map',
  };

  setUp(() async {
    scratch = await Directory.systemTemp.createTemp('cpd_recovery_test_');
    documents = await Directory(p.join(scratch.path, 'documents')).create();
    backup = Directory(p.join(scratch.path, 'independent-backup'));
    proof = File(p.join(documents.path, 'attachments', 'course.pdf'));
    await proof.parent.create();
    await proof.writeAsBytes([0, 1, 2, 3]);
  });
  tearDown(() async => scratch.delete(recursive: true));

  Future<LegacyRecoverySnapshot> capture({int available = 32 * 1024 * 1024}) =>
      LegacyRecoverySnapshot.capture(
        legacyValues: source,
        documents: documents,
        destination: backup,
        availableBytes: (_) async => available,
      );

  test(
    'raw inventory bypasses sanitising writes and leaves profile settings intact',
    () async {
      SharedPreferences.setMockInitialValues(source);
      final prefs = await SharedPreferences.getInstance();
      final actual = await readCpdLegacyPreferences(prefs);
      expect(actual['deleted_professions'], [' NURSE ']);
      expect(actual['entries_json_list'], source['entries_json_list']);
      expect(actual['profile_company'], source['profile_company']);
      expect(prefs.get('future_key'), source['future_key']);
      expect(prefs.get('deleted_professions'), [' NURSE ']);
    },
  );

  test(
    'preflight rejects insufficient space without publishing a partial copy',
    () async {
      await expectLater(
        capture(available: 4),
        throwsA(isA<InsufficientRecoveryStorage>()),
      );
      expect(await backup.exists(), isFalse);
      expect(await proof.readAsBytes(), [0, 1, 2, 3]);
      expect(await scratch.list().length, 1);
      final copied = await capture();
      expect(await copied.directory.exists(), isTrue);
    },
  );

  test(
    'separate copy restores exact raw rows and owned bytes after source loss',
    () async {
      final outside = await File(
        p.join(scratch.path, 'outside'),
      ).writeAsString('external');
      await Link(p.join(proof.parent.path, 'external')).create(outside.path);
      final snapshot = await capture();
      expect(await snapshot.excludedPaths(), ['attachments/external']);
      await documents.delete(recursive: true);
      final restored = Directory(p.join(scratch.path, 'recovered-documents'));
      final restoredSource = await snapshot.restoreTo(restored);
      expect(restoredSource.values, source);
      expect(restoredSource.previousDocumentsPath, documents.path);
      expect(
        await File(
          p.join(restored.path, 'attachments/course.pdf'),
        ).readAsBytes(),
        [0, 1, 2, 3],
      );
      expect(
        await File(p.join(restored.path, 'attachments/external')).exists(),
        isFalse,
      );
      await expectLater(snapshot.restoreTo(restored), throwsStateError);
      expect(await outside.readAsString(), 'external');
    },
  );

  test(
    'changed originals and altered manifests are rejected before restoring',
    () async {
      final snapshot = await capture();
      final dest = Directory(p.join(scratch.path, 'restore'));
      final copy = File(p.join(backup.path, 'attachments/course.pdf'));
      await copy.writeAsBytes([0, 1, 2, 4]);
      await expectLater(snapshot.restoreTo(dest), throwsStateError);
      expect(await dest.exists(), isFalse);
      await copy.writeAsBytes([0, 1, 2, 3]);
      final manifest = File(p.join(backup.path, 'manifest.json'));
      final values = jsonDecode(await manifest.readAsString()) as Map;
      (values['originals'] as Map).clear();
      await manifest.writeAsString(jsonEncode(values));
      await expectLater(snapshot.restoreTo(dest), throwsStateError);
      expect(await dest.exists(), isFalse);
    },
  );

  test('rejects nested and existing snapshot destinations', () async {
    final nested = Directory(p.join(documents.path, 'nested'));
    await expectLater(
      LegacyRecoverySnapshot.capture(
        legacyValues: source,
        documents: documents,
        destination: nested,
        availableBytes: (_) async => 1024 * 1024,
      ),
      throwsArgumentError,
    );
    await capture();
    await expectLater(capture(), throwsStateError);
  });
}
