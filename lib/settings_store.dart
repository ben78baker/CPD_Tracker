import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

class SettingsStore {
  SettingsStore._();
  static final SettingsStore instance = SettingsStore._();

  // Always returns a non-null SharedPreferences instance, with simple backoff retries
Future<SharedPreferences> _prefsWithRetry({int attempts = 6}) async {
  Object? lastError;
  for (var i = 0; i < attempts; i++) {
    try {
      // On iOS there can be a brief method-channel race just after app start
      return await SharedPreferences.getInstance();
    } catch (e) {
      lastError = e;
      await Future.delayed(Duration(milliseconds: 150 * (i + 1)));
    }
  }
  // Final attempt – if this throws, surface it to the caller for visibility
  return await SharedPreferences.getInstance();
}

  /// Pre-warm the SharedPreferences channel early in app startup
  Future<void> prewarm() async {
    try {
      await _prefsWithRetry();
    } catch (_) {
      // Ignore – UI flows will still retry lazily when needed
    }
  }

  static const _kDateFormat = 'date_format';
  Future<String> getDateFormat() async {
    final prefs = await _prefsWithRetry();
    return prefs.getString(_kDateFormat) ?? 'dd/MM/yyyy';
  }
  Future<void> setDateFormat(String fmt) async {
    final prefs = await _prefsWithRetry();
    await prefs.setString(_kDateFormat, fmt);
  }
    static const _kProfessions = 'professions';
  static const _kDeletedProfessions = 'deleted_professions';

  // Normalise a profession: trim, single-capitalise first letter, lower the rest
  String _normalize(String s) {
    final t = s.trim();
    if (t.isEmpty) return '';
    if (t.length == 1) return t.toUpperCase();
    return t[0].toUpperCase() + t.substring(1).toLowerCase();
  }

  Future<List<String>> loadProfessions() async {
    final prefs = await _prefsWithRetry();
    return prefs.getStringList(_kProfessions) ?? <String>[];
  }

  Future<List<String>> loadDeletedProfessions() async {
    final prefs = await _prefsWithRetry();
    final items = prefs.getStringList(_kDeletedProfessions) ?? <String>[];
    // Normalize, de-duplicate, sort, and persist sanitized list
    final Map<String, String> canonical = {};
    for (final raw in items) {
      final norm = _normalize(raw);
      if (norm.isEmpty) continue;
      canonical.putIfAbsent(norm.toLowerCase(), () => norm);
    }
    final list = canonical.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    await prefs.setStringList(_kDeletedProfessions, list);
    return list;
  }

  Future<void> saveDeletedProfessions(List<String> items) async {
    final prefs = await _prefsWithRetry();
    final Map<String, String> canonical = {};
    for (final raw in items) {
      final norm = _normalize(raw);
      if (norm.isEmpty) continue;
      canonical.putIfAbsent(norm.toLowerCase(), () => norm);
    }
    final list = canonical.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    await prefs.setStringList(_kDeletedProfessions, list);
  }

  Future<void> saveProfessions(List<String> items) async {
    final prefs = await _prefsWithRetry();
    // Case-insensitive de-duplication with canonical (normalized) values
    final Map<String, String> canonical = {};
    for (final raw in items) {
      final norm = _normalize(raw);
      if (norm.isEmpty) continue;
      final key = norm.toLowerCase();
      canonical.putIfAbsent(key, () => norm);
    }
    final list = canonical.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    await prefs.setStringList(_kProfessions, list);
  }

  /// Check if a profession exists (case-insensitive)
  Future<bool> hasProfession(String value) async {
    final list = await loadProfessions();
    final target = value.trim().toLowerCase();
    return list.any((p) => p.toLowerCase() == target);
  }

  /// Add a profession with normalization, de-duplication and sorted persistence
  Future<void> addProfession(String value) async {
    final current = await loadProfessions();
    final norm = _normalize(value);
    if (norm.isEmpty) return;
    if (current.any((p) => p.toLowerCase() == norm.toLowerCase())) return;
    current.add(norm);
    await saveProfessions(current);
  }

  /// Mark a profession as deleted (soft delete)
  Future<void> softDeleteProfession(String value) async {
    final name = _normalize(value);
    if (name.isEmpty) return;
    // Ensure profession exists in master list
    final all = await loadProfessions();
    if (!all.any((p) => p.toLowerCase() == name.toLowerCase())) {
      all.add(name);
      await saveProfessions(all);
    }
    // Add to deleted set
    final deleted = await loadDeletedProfessions();
    if (!deleted.any((p) => p.toLowerCase() == name.toLowerCase())) {
      deleted.add(name);
      await saveDeletedProfessions(deleted);
    }
  }

  /// Restore (un-delete) a profession
  Future<void> restoreProfession(String value) async {
    final name = _normalize(value);
    if (name.isEmpty) return;
    final deleted = await loadDeletedProfessions();
    final next = deleted.where((p) => p.toLowerCase() != name.toLowerCase()).toList();
    await saveDeletedProfessions(next);
  }

  /// Return only professions not soft-deleted
  Future<List<String>> loadActiveProfessions() async {
    final all = await loadProfessions();
    final deleted = await loadDeletedProfessions();
    final deletedSet = deleted.map((e) => e.toLowerCase()).toSet();
    final active = all.where((p) => !deletedSet.contains(p.toLowerCase())).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return active;
  }

  /// Remove a profession by name (case-insensitive)
  Future<void> removeProfession(String value) async {
    final current = await loadProfessions();
    final target = value.trim().toLowerCase();
    final next = current.where((p) => p.toLowerCase() != target).toList();
    if (next.length != current.length) {
      await saveProfessions(next);
    }
  }

  // For testing/debugging
  Future<void> clearProfessions() async {
    final prefs = await _prefsWithRetry();
    await prefs.remove(_kProfessions);
  }
  // -------------------------------
  // Onboarding completion flag
  // -------------------------------
  static const _kOnboardingComplete = 'onboarding_complete';

  Future<void> setOnboardingComplete(bool value) async {
    final prefs = await _prefsWithRetry();
    await prefs.setBool(_kOnboardingComplete, value);
  }

  Future<bool> isOnboardingComplete() async {
    final prefs = await _prefsWithRetry();
    return prefs.getBool(_kOnboardingComplete) ?? false;
  }

  // -------------------------------
  // Basic profile fields (optional)
  // -------------------------------
  static const _kProfileName = 'profile_name';
  static const _kProfileCompany = 'profile_company';
  static const _kProfileAddress = 'profile_address';
  static const _kProfileEmail = 'profile_email';

  Future<void> saveProfile({
    String? name,
    String? company,
    String? address,
    String? email,
  }) async {
    final prefs = await _prefsWithRetry();
    if (name != null) await prefs.setString(_kProfileName, name);
    if (company != null) await prefs.setString(_kProfileCompany, company);
    if (address != null) await prefs.setString(_kProfileAddress, address);
    if (email != null) await prefs.setString(_kProfileEmail, email);
  }

  Future<Map<String, String>> loadProfile() async {
    final prefs = await _prefsWithRetry();
    return <String, String>{
      'name': prefs.getString(_kProfileName) ?? '',
      'company': prefs.getString(_kProfileCompany) ?? '',
      'address': prefs.getString(_kProfileAddress) ?? '',
      'email': prefs.getString(_kProfileEmail) ?? '',
    };
  }
}