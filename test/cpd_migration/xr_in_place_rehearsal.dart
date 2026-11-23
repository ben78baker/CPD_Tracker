import 'dart:io';

import 'device_in_place_rehearsal.dart';

/// Dedicated development entry point for the authorised XR installation.
Future<void> main() {
  if (!Platform.isIOS) throw UnsupportedError('Use the iOS rehearsal.');
  return runDeviceRehearsal(
    sourceId: const String.fromEnvironment('CPD_XR_EXPECTED_SOURCE'),
    label: 'XR',
    workspaceName: 'xr-in-place-migration',
    logPrefix: 'CPD_XR',
  );
}
