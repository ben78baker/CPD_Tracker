import 'package:shared_preferences/shared_preferences.dart';

class SettingsStore {
  static const _kDateFormat = 'date_format'; // 'dd/MM/yyyy' default

  Future<String> getDateFormat() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kDateFormat) ?? 'dd/MM/yyyy';
  }

  Future<void> setDateFormat(String fmt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDateFormat, fmt);
  }
}