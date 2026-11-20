import 'dart:io';

import 'package:flutter/services.dart';

/// Returns free bytes on the volume containing the app-private destination.
/// Missing or invalid platform responses deliberately fail preflight.
Future<int> availableDeviceStorage(Directory directory) async {
  const channel = MethodChannel('cpd_tracker/migration_storage');
  final bytes = await channel.invokeMethod<int>('availableBytes', {
    'path': directory.absolute.path,
  });
  if (bytes == null || bytes < 0) {
    throw StateError('The destination capacity could not be measured.');
  }
  return bytes;
}
