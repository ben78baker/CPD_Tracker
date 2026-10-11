import 'package:cpd_tracker/settings_store.dart';
import 'package:cpd_tracker/theme/app_accent.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SettingsStore.instance.appAccent.value = AppAccent.purple;
  });

  test('purple is the default app colour', () async {
    expect(await SettingsStore.instance.getAppAccent(), AppAccent.purple);
    expect(SettingsStore.instance.appAccent.value, AppAccent.purple);
  });

  test('app colour is persisted and restored during prewarm', () async {
    await SettingsStore.instance.setAppAccent(AppAccent.teal);

    expect(SettingsStore.instance.appAccent.value, AppAccent.teal);
    expect(await SettingsStore.instance.getAppAccent(), AppAccent.teal);

    SettingsStore.instance.appAccent.value = AppAccent.purple;
    await SettingsStore.instance.prewarm();

    expect(SettingsStore.instance.appAccent.value, AppAccent.teal);
  });
}
