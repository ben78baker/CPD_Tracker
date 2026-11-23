import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'device_in_place_rehearsal.dart';

/// ADB provisions the token and independently verified source ID in app-private
/// storage on the authorised rehearsal device before the first launch.
Future<void> main() async {
  const token = String.fromEnvironment('CPD_ANDROID_REHEARSAL_TOKEN');
  if (kReleaseMode || !Platform.isAndroid || token.isEmpty) {
    throw UnsupportedError('Use the authorised Android rehearsal.');
  }
  WidgetsFlutterBinding.ensureInitialized();
  final support = await getApplicationSupportDirectory();
  final seal = File(p.join(support.path, 'android-cpd-rehearsal.seal'));
  if (!await seal.exists() || await seal.length() > 128) {
    throw StateError('No local Android rehearsal authorisation.');
  }
  final lines = await seal.readAsLines();
  if (lines.length != 2 || lines.first != token || lines.last.isEmpty) {
    throw StateError('Invalid local Android rehearsal authorisation.');
  }
  await runDeviceRehearsal(
    sourceId: lines.last,
    label: 'OPPO',
    workspaceName: 'android-in-place-migration',
    logPrefix: 'CPD_ANDROID',
  );
}
