import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;

import 'portable_archive.dart';

/// Encrypted file framing is independent of the manifest and recording schema.
class BackupEncryption {
  const BackupEncryption();

  static const _magic = [82, 67, 69, 66, 65, 75, 48, 49]; // RCEBAK01
  static const _headerSize = 32;
  static const _chunkSize = 64 * 1024;
  static const _tagSize = 16;
  static const _maxInput = 65 * 1024 * 1024 * 1024;

  Future<bool> isEncrypted(File source) async {
    final reader = await source.open();
    try {
      return _matches(await reader.read(_magic.length));
    } finally {
      await reader.close();
    }
  }

  Future<File> encrypt(
    File source,
    File destination,
    String password, {
    required AvailableStorage available,
  }) async {
    final size = await source.length();
    await requireBackupCapacity(
      destination.parent,
      _encodedSize(size),
      available,
    );
    return _transform(source, destination, password, decrypt: false);
  }

  Future<File> decrypt(
    File source,
    File destination,
    String password, {
    required AvailableStorage available,
  }) async {
    // The authenticated file is always larger than its plaintext.
    await requireBackupCapacity(
      destination.parent,
      await source.length(),
      available,
    );
    return _transform(source, destination, password, decrypt: true);
  }

  Future<File> _transform(
    File source,
    File destination,
    String password, {
    required bool decrypt,
  }) async {
    if (password.isEmpty || password.length > 1024) {
      throw const BackupException(
        BackupProblem.authentication,
        'Invalid password.',
      );
    }
    if (await FileSystemEntity.type(destination.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const BackupException(
        BackupProblem.destination,
        'Destination already exists.',
      );
    }
    final temporary = await destination.parent.createTemp('.backup-crypto-');
    try {
      final input = source.path;
      final staged = p.join(temporary.path, 'payload');
      await Isolate.run(() => _process(input, staged, password, decrypt));
      if (await FileSystemEntity.type(destination.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw const BackupException(
          BackupProblem.destination,
          'Destination already exists.',
        );
      }
      return await File(staged).rename(destination.path);
    } finally {
      try {
        await temporary.delete(recursive: true);
      } on PathNotFoundException {
        // A disposable cache directory may already have been reclaimed.
      }
    }
  }

  static bool _matches(List<int> bytes) =>
      bytes.length == _magic.length &&
      Iterable<int>.generate(_magic.length).every((i) => bytes[i] == _magic[i]);

  static int _encodedSize(int length) =>
      _headerSize +
      length +
      _tagSize * ((length + _chunkSize - 1) ~/ _chunkSize + 1);

  static Future<void> _process(
    String input,
    String output,
    String password,
    bool decrypt,
  ) async {
    final reader = await File(input).open();
    try {
      final int length;
      final Uint8List header;
      if (decrypt) {
        header = await reader.read(_headerSize);
        if (header.length != _headerSize || !_matches(header.sublist(0, 8))) {
          _authentication();
        }
        length = ByteData.sublistView(header).getUint64(24);
        if (length < 0 ||
            length > _maxInput ||
            await reader.length() != _encodedSize(length)) {
          _authentication();
        }
      } else {
        final random = Random.secure();
        length = await reader.length();
        if (length > _maxInput) {
          throw const BackupException(
            BackupProblem.capacity,
            'Archive is too large.',
          );
        }
        header = Uint8List.fromList([
          ..._magic,
          for (var i = 0; i < 16; i++) random.nextInt(256),
          ...(ByteData(8)..setUint64(0, length)).buffer.asUint8List(),
        ]);
      }
      final secret = await Argon2id(
        parallelism: 1,
        memory: 19 * 1024,
        iterations: 2,
        hashLength: 32,
      ).deriveKeyFromPassword(password: password, nonce: header.sublist(8, 24));
      final cipher = AesGcm.with256bits();
      try {
        final writer = await File(output).open(mode: FileMode.writeOnly);
        try {
          if (!decrypt) await writer.writeFrom(header);
          var remaining = length;
          // The final zero-length block authenticates EOF, even for an empty archive.
          for (var index = 0; ; index++) {
            final size = min(_chunkSize, remaining);
            final nonce = (ByteData(
              12,
            )..setUint64(4, index)).buffer.asUint8List();
            final bytes = await reader.read(size + (decrypt ? _tagSize : 0));
            if (bytes.length != size + (decrypt ? _tagSize : 0)) {
              _authentication();
            }
            if (decrypt) {
              final box = SecretBox(
                Uint8List.sublistView(bytes, 0, size),
                nonce: nonce,
                mac: Mac(Uint8List.sublistView(bytes, size)),
              );
              await writer.writeFrom(
                await cipher.decrypt(box, secretKey: secret, aad: header),
              );
            } else {
              final box = await cipher.encrypt(
                bytes,
                secretKey: secret,
                nonce: nonce,
                aad: header,
              );
              await writer.writeFrom(box.cipherText);
              await writer.writeFrom(box.mac.bytes);
            }
            if (size == 0) break;
            remaining -= size;
          }
          if ((await reader.read(1)).isNotEmpty) _authentication();
          await writer.flush();
        } finally {
          await writer.close();
        }
      } on SecretBoxAuthenticationError {
        _authentication();
      } finally {
        secret.destroy();
      }
    } finally {
      await reader.close();
    }
  }

  static Never _authentication() => throw const BackupException(
    BackupProblem.authentication,
    'Incorrect password or damaged encrypted backup.',
  );
}
