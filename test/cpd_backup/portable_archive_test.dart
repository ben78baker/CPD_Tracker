import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cpd_tracker/recording_engine_storage/portable_archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const archive = PortableArchive();
Future<int> space(Directory _) async => 1024 * 1024;

void main() {
  late Directory root;
  late File rows;
  late File backup;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('portable_archive_test_');
    rows = await File(p.join(root.path, 'test-input')).writeAsString('rows\n');
    backup = File(p.join(root.path, 'backup'));
  });

  tearDown(() => root.delete(recursive: true));

  test('future archive framing is distinguished from bad content', () async {
    await backup.writeAsString('RECBAK02');
    await expectLater(
      archive.inspect(backup),
      throwsA(
        isA<BackupException>().having(
          (error) => error.problem,
          'problem',
          BackupProblem.version,
        ),
      ),
    );
  });

  Future<BackupInspection> create() => archive.write(
    files: {PortableArchive.rows: rows, 'evidence/photo': rows},
    destination: backup,
    created: DateTime.utc(2026, 11, 21),
    schema: 4,
    available: space,
  );

  test(
    'round trip verifies bytes and requires an empty staging directory',
    () async {
      final inspection = await create();
      expect(inspection.created, DateTime.utc(2026, 11, 21));
      expect(inspection.originals, 1);
      final staging = await root.createTemp('staged');
      final extracted = await archive.extract(
        backup,
        staging,
        available: space,
        expectedSeal: inspection.seal,
      );
      expect(extracted.seal, inspection.seal);
      expect(
        await File(p.join(staging.path, 'evidence', 'photo')).readAsBytes(),
        await rows.readAsBytes(),
      );
      await expectLater(
        archive.extract(
          backup,
          staging,
          available: space,
          expectedSeal: inspection.seal,
        ),
        throwsA(problem(BackupProblem.destination)),
      );
    },
  );

  test('published file is never overwritten by another creation', () async {
    final first = await create();
    await rows.writeAsString('changed');
    await expectLater(create(), throwsA(problem(BackupProblem.destination)));
    expect((await archive.inspect(backup)).seal, first.seal);
  });

  test('writers cannot race to publish the same private destination', () async {
    final first = create();
    final racing = create();
    final outcomes = await Future.wait([
      first.then<Object>((value) => value, onError: (Object error) => error),
      racing.then<Object>((value) => value, onError: (Object error) => error),
    ]);
    expect(outcomes.whereType<BackupInspection>(), hasLength(1));
    expect(
      outcomes.whereType<BackupException>().single.problem,
      BackupProblem.destination,
    );
    expect(
      (await archive.inspect(backup)).seal,
      outcomes.whereType<BackupInspection>().single.seal,
    );
  });

  test('corrupt, truncated, and appended payloads are rejected', () async {
    await create();
    final bytes = await backup.readAsBytes();
    for (final invalid in [
      Uint8List.fromList(bytes)..[bytes.length - 2] ^= 1,
      bytes.sublist(0, bytes.length - 1),
      [...bytes, 0],
    ]) {
      await backup.writeAsBytes(invalid);
      await expectLater(
        archive.inspect(backup),
        throwsA(problem(BackupProblem.integrity)),
      );
    }
  });

  test('low capacity and a file swapped after review never extract', () async {
    final before = await create();
    final staging = await root.createTemp('staged');
    await expectLater(
      archive.extract(
        backup,
        staging,
        available: (_) async => 1,
        expectedSeal: before.seal,
      ),
      throwsA(problem(BackupProblem.capacity)),
    );
    expect(await staging.list().isEmpty, isTrue);

    await backup.delete();
    await rows.writeAsString('replacement');
    await create();
    await expectLater(
      archive.extract(
        backup,
        staging,
        available: space,
        expectedSeal: before.seal,
      ),
      throwsA(problem(BackupProblem.integrity)),
    );
    expect(await staging.list().isEmpty, isTrue);
  });

  test('creation capacity rejection leaves no published file', () async {
    await expectLater(
      archive.write(
        files: {PortableArchive.rows: rows},
        destination: backup,
        created: DateTime.utc(2026),
        schema: 4,
        available: (_) async => 0,
      ),
      throwsA(problem(BackupProblem.capacity)),
    );
    expect(await backup.exists(), isFalse);
  });

  for (final name in [
    '../escape',
    '/tmp/file',
    'evidence/../escape',
    r'evidence\escape',
    'Rows.ndjson',
  ]) {
    test('rejects unsafe archive entry $name', () async {
      await fake(backup, [entry(PortableArchive.rows), entry(name)]);
      await expectLater(
        archive.inspect(backup),
        throwsA(problem(BackupProblem.format)),
      );
    });
  }

  test('rejects case aliases, malicious lengths and future versions', () async {
    await fake(backup, [
      entry(PortableArchive.rows),
      entry('evidence/Item'),
      entry('evidence/item'),
    ]);
    await expectLater(
      archive.inspect(backup),
      throwsA(problem(BackupProblem.format)),
    );
    await fake(backup, [
      entry(PortableArchive.rows, size: 1024 * 1024 * 1024 * 1024),
    ]);
    await expectLater(
      archive.inspect(backup),
      throwsA(problem(BackupProblem.format)),
    );
    await fake(backup, [entry(PortableArchive.rows)], version: 2);
    await expectLater(
      archive.inspect(backup),
      throwsA(problem(BackupProblem.version)),
    );
  });
}

Matcher problem(BackupProblem reason) =>
    isA<BackupException>().having((error) => error.problem, 'problem', reason);

Map<String, Object> entry(String path, {int size = 0}) => {
  'path': path,
  'size': size,
  'sha256': sha256.convert([]).toString(),
};

Future<void> fake(File output, List<Object> entries, {int version = 1}) async {
  final bytes = utf8.encode(
    jsonEncode({
      'version': version,
      'schema': 4,
      'created': DateTime.utc(2026, 11, 21).toIso8601String(),
      'entries': entries,
    }),
  );
  await output.writeAsBytes([
    ...ascii.encode('RECBAK01'),
    ...(ByteData(4)..setUint32(0, bytes.length)).buffer.asUint8List(),
    ...bytes,
  ]);
}
