import 'dart:io';

import 'package:cpd_tracker/recording_engine/models.dart';
import 'package:cpd_tracker/recording_engine_storage/managed_attachment_files.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory scratch;

  setUp(() async {
    scratch = await Directory.systemTemp.createTemp('managed_originals_test_');
  });
  tearDown(() async => scratch.delete(recursive: true));

  test('managed file copy preserves exact bytes and source', () async {
    final source = File(p.join(scratch.path, 'original.png'));
    await source.writeAsBytes([0, 255, 1, 9]);
    final files = ManagedAttachmentFiles(
      Directory(p.join(scratch.path, 'owned')),
    );
    final copied = await files.copyOriginal(source);
    expect(copied.name, 'original.png');
    expect(copied.locator, endsWith('.png'));
    expect(await (await files.resolveOriginal(copied))!.readAsBytes(), [
      0,
      255,
      1,
      9,
    ]);
    expect(await source.readAsBytes(), [0, 255, 1, 9]);
    expect(
      await files.root
          .list(recursive: true)
          .where((entry) => entry.path.endsWith('.part'))
          .isEmpty,
      isTrue,
    );
  });

  test('an app-relative symlink cannot expose outside files', () async {
    final source = await File(p.join(scratch.path, 'outside')).create();
    final root = await Directory(p.join(scratch.path, 'owned')).create();
    await Link(p.join(root.path, 'escape')).create(source.path);
    final files = ManagedAttachmentFiles(root);
    expect(
      await files.resolveOriginal(
        RecordingAttachment(
          id: 'id',
          kind: AttachmentKind.managed,
          locator: 'escape',
          name: 'Evidence',
        ),
      ),
      isNull,
    );
  });
}
