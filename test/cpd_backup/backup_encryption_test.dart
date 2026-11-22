import 'dart:io';
import 'dart:typed_data';

import 'package:cpd_tracker/recording_engine_storage/backup_encryption.dart';
import 'package:cpd_tracker/recording_engine_storage/portable_archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'encrypted multi-block archive authenticates the header, order and EOF',
    () async {
      final root = await Directory.systemTemp.createTemp('profession_crypto_');
      addTearDown(() => root.delete(recursive: true));
      File item(String name) => File(p.join(root.path, name));
      Future<int> available(Directory _) async => 8 * 1024 * 1024;
      const encryption = BackupEncryption();
      const password = 'A reliable passphrase – अ';
      final payload = Uint8List.fromList(
        List<int>.generate(196611, (i) => i % 251),
      );
      final clear = await item('clear').writeAsBytes(payload);
      final box = await encryption.encrypt(
        clear,
        item('box'),
        password,
        available: available,
      );
      expect(await encryption.isEncrypted(box), isTrue);
      expect(await encryption.isEncrypted(clear), isFalse);
      final recovered = await encryption.decrypt(
        box,
        item('out'),
        password,
        available: available,
      );
      expect(await recovered.readAsBytes(), payload);
      final second = await encryption.encrypt(
        clear,
        item('second'),
        password,
        available: available,
      );
      final original = await box.readAsBytes();
      expect(await second.readAsBytes(), isNot(original));
      final failure = isA<BackupException>().having(
        (e) => e.problem,
        'problem',
        BackupProblem.authentication,
      );
      await expectLater(
        encryption.decrypt(
          box,
          item('wrong'),
          'wrong password',
          available: available,
        ),
        throwsA(failure),
      );
      expect(await item('wrong').exists(), isFalse);
      final frame = 65536 + 16;
      for (final broken in [
        Uint8List.fromList(original)..[10] ^= 1,
        Uint8List.fromList(original)..[original.length - 1] ^= 1,
        original.sublist(0, original.length - 1),
        [
          ...original.sublist(0, 32),
          ...original.sublist(32 + frame, 32 + 2 * frame),
          ...original.sublist(32, 32 + frame),
          ...original.sublist(32 + 2 * frame),
        ],
      ]) {
        await item('bad').writeAsBytes(broken);
        await expectLater(
          encryption.decrypt(
            item('bad'),
            item('failure'),
            password,
            available: available,
          ),
          throwsA(failure),
        );
        expect(await item('failure').exists(), isFalse);
      }
      expect(await box.readAsBytes(), original);
    },
  );
}
