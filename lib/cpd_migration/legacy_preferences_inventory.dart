import 'package:shared_preferences/shared_preferences.dart';

/// Capture the known CPD storage keys without invoking the normalising or
/// mutating SettingsStore helpers. A future orchestrator must freeze all
/// writers before calling this. Rehearsals supply mock or disposable prefs.
Future<Map<String, Object?>> readCpdLegacyPreferences(
  SharedPreferences preferences,
) async {
  await preferences.reload();
  return {
    for (final key in const [
      'entries_json_list',
      'next_entry_id',
      'professions',
      'deleted_professions',
      'targets_v1',
      'date_format',
      'week_start',
      'locale_code',
      'report_locale_code',
      'app_accent',
      'profile_name',
      'profile_company',
      'profile_address',
      'profile_email',
      'onboarding_complete',
      'qr_hint_dismissed',
    ])
      key: ?preferences.get(key),
  };
}
