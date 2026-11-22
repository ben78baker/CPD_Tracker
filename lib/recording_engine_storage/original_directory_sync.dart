import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Persist the name of a newly flushed original before its SQLite reference.
/// A platform or filesystem that rejects this operation fails the save.
Future<void> syncOriginalDirectory(Directory directory) async {
  if (!(Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {
    throw UnsupportedError(
      'Directory synchronisation is unqualified on this platform.',
    );
  }
  final library = Platform.isAndroid
      ? DynamicLibrary.open('libc.so')
      : DynamicLibrary.process();
  final open = library
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Int32),
        int Function(Pointer<Utf8>, int)
      >('open');
  final sync = library.lookupFunction<Int32 Function(Int32), int Function(int)>(
    'fsync',
  );
  final close = library
      .lookupFunction<Int32 Function(Int32), int Function(int)>('close');
  final path = directory.path.toNativeUtf8();
  try {
    final fd = open(
      path,
      0,
    ); // O_RDONLY (.part was already flushed before rename).
    if (fd == -1) {
      throw FileSystemException(
        'Cannot open original directory.',
        directory.path,
      );
    }
    try {
      if (sync(fd) != 0) {
        throw FileSystemException(
          'Cannot persist original directory.',
          directory.path,
        );
      }
    } finally {
      close(fd);
    }
  } finally {
    malloc.free(path);
  }
}
