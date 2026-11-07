import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'entry_repository.dart';
import 'theme/app_accent.dart';

class SettingsStore {
  SettingsStore._();
  static final SettingsStore instance = SettingsStore._();

  final ValueNotifier<Locale?> locale = ValueNotifier<Locale?>(null);
  final ValueNotifier<AppAccent> appAccent = ValueNotifier<AppAccent>(
    AppAccent.purple,
  );

  // Always returns a non-null SharedPreferences instance, with simple backoff retries
  Future<SharedPreferences> _prefsWithRetry({int attempts = 6}) async {
    for (var i = 0; i < attempts; i++) {
      try {
        // On iOS there can be a brief method-channel race just after app start
        return await SharedPreferences.getInstance();
      } catch (e) {
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
    // Also load saved appearance and language overrides (if any).
    await Future.wait(<Future<void>>[_loadSavedLocale(), _loadSavedAccent()]);
  }

  static const _kDateFormat = 'date_format';
  static const _kLocaleCode = 'locale_code';
  static const _kAppAccent = 'app_accent';

  Future<void> _loadSavedAccent() async {
    try {
      final prefs = await _prefsWithRetry();
      appAccent.value = AppAccent.fromStorage(prefs.getString(_kAppAccent));
    } catch (_) {
      appAccent.value = AppAccent.purple;
    }
  }

  Future<AppAccent> getAppAccent() async {
    final prefs = await _prefsWithRetry();
    return AppAccent.fromStorage(prefs.getString(_kAppAccent));
  }

  Future<void> setAppAccent(AppAccent accent) async {
    appAccent.value = accent;
    final prefs = await _prefsWithRetry();
    await prefs.setString(_kAppAccent, accent.storageValue);
  }

  Future<void> _loadSavedLocale() async {
    try {
      final prefs = await _prefsWithRetry();
      final code = prefs.getString(_kLocaleCode);
      if (code == null || code.trim().isEmpty) {
        locale.value = null; // follow device language
      } else {
        locale.value = Locale(code.trim());
      }
    } catch (_) {
      // If prefs unavailable briefly, keep null (follow device) and allow retry later.
      locale.value = null;
    }
  }

  Future<String> getDateFormat() async {
    final prefs = await _prefsWithRetry();
    return prefs.getString(_kDateFormat) ?? 'dd/MM/yyyy';
  }

  Future<void> setDateFormat(String fmt) async {
    final prefs = await _prefsWithRetry();
    await prefs.setString(_kDateFormat, fmt);
  }

  // -------------------------------
  // Week start preference
  // Values: 'monday' | 'sunday' | 'saturday' | 'locale'
  // -------------------------------
  static const _kWeekStart = 'week_start';

  /// Returns saved preference or 'locale' if unset
  Future<String> getWeekStart() async {
    final prefs = await _prefsWithRetry();
    return prefs.getString(_kWeekStart) ?? 'locale';
  }

  /// Persist week start preference
  Future<void> setWeekStart(String value) async {
    // Expect one of: 'monday' | 'sunday' | 'saturday' | 'locale'
    final prefs = await _prefsWithRetry();
    await prefs.setString(_kWeekStart, value);
  }

  /// Clear week start preference so locale default is used
  Future<void> clearWeekStart() async {
    final prefs = await _prefsWithRetry();
    await prefs.remove(_kWeekStart);
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
    if (!await prefs.setStringList(_kDeletedProfessions, list)) {
      throw StateError('Could not save deleted professions.');
    }
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
    if (!await prefs.setStringList(_kDeletedProfessions, list)) {
      throw StateError('Could not save deleted professions.');
    }
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
    if (!await prefs.setStringList(_kProfessions, list)) {
      throw StateError('Could not save professions.');
    }
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

  /// Rename the profession and its references without merging existing data.
  /// The destination is made visible before references move; the old name is
  /// removed last so an interrupted write cannot hide the moved records.
  Future<void> renameProfession(String oldValue, String newValue) async {
    final oldKey = oldValue.trim().toLowerCase();
    final name = _normalize(newValue);
    if (name.isEmpty) throw StateError('Please enter a profession name.');
    final newKey = name.toLowerCase();
    final prefs = await _prefsWithRetry();
    final all = List<String>.of(await loadProfessions());
    final deleted = await loadDeletedProfessions();
    if (!all.any((p) => p.trim().toLowerCase() == oldKey)) {
      throw StateError('This profession no longer exists. Please refresh.');
    }
    final originalEntries = prefs.getStringList('entries_json_list');
    final entries = (originalEntries ?? <String>[])
        .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
        .toList();
    // Unlike the display helper, do not treat malformed saved targets as empty:
    // a rename must never overwrite data it cannot understand.
    final oldTargets = prefs.getString(_kTargetsKey);
    Map<String, Map<String, dynamic>> targets;
    try {
      final decoded = oldTargets == null
          ? <String, dynamic>{}
          : jsonDecode(oldTargets) as Map<String, dynamic>;
      targets = decoded.map(
        (key, value) => MapEntry(key, (value as Map).cast<String, dynamic>()),
      );
    } catch (_) {
      throw StateError(
        'Saved targets could not be read. Rename cancelled to preserve them.',
      );
    }
    bool destination(String value) => value.trim().toLowerCase() == newKey;
    if (newKey != oldKey &&
        (all.any(destination) ||
            deleted.any(destination) ||
            entries.any((e) => destination(e['profession'] as String)) ||
            targets.keys.any(destination))) {
      throw StateError(
        'That profession name already has saved data. Choose another name.',
      );
    }
    final sourceTargets = targets.keys
        .where((key) => key.trim().toLowerCase() == oldKey)
        .toList();
    if (sourceTargets.length > 1) {
      throw StateError(
        'This profession has conflicting saved targets. Rename cancelled to preserve them.',
      );
    }
    final movedTargets = Map<String, Map<String, dynamic>>.of(targets);
    if (sourceTargets.isNotEmpty) {
      movedTargets[name] = movedTargets.remove(sourceTargets.single)!;
    }
    final movedEntries = entries.map((entry) {
      if ((entry['profession'] as String).trim().toLowerCase() == oldKey) {
        return jsonEncode({...entry, 'profession': name});
      }
      return jsonEncode(entry);
    }).toList();
    final finalNames = all
        .map((p) => p.trim().toLowerCase() == oldKey ? name : p)
        .toList();
    final finalDeleted = deleted
        .map((p) => p.trim().toLowerCase() == oldKey ? name : p)
        .toList();
    try {
      await saveProfessions([...all, name]);
      if (!await prefs.setStringList('entries_json_list', movedEntries) ||
          !await prefs.setString(_kTargetsKey, jsonEncode(movedTargets))) {
        throw StateError('Could not save the rename.');
      }
      await saveDeletedProfessions(finalDeleted);
      await saveProfessions(finalNames);
    } catch (_) {
      // Best-effort rollback on storage failure, without removing any records.
      if (originalEntries != null) {
        final restored = await prefs.setStringList(
          'entries_json_list',
          originalEntries,
        );
        if (!restored) rethrow; // Keep both names accessible if rollback fails.
      }
      if (oldTargets != null) await prefs.setString(_kTargetsKey, oldTargets);
      await saveProfessions(all);
      await saveDeletedProfessions(deleted);
      rethrow;
    }
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
    await addProfession(name);
    final deleted = await loadDeletedProfessions();
    final next = deleted
        .where((p) => p.toLowerCase() != name.toLowerCase())
        .toList();
    await saveDeletedProfessions(next);
  }

  /// Recovery is explicit: callers must obtain consent before reactivating or
  /// recreating a profession, which may also reveal its other saved records.
  Future<void> restoreRecord(int id, {bool recoverProfession = false}) async {
    final repo = EntryRepository();
    final records = await repo.loadAll();
    final matches = records.where((entry) => entry.id == id).toList();
    if (matches.length != 1) {
      throw StateError('The saved record could not be identified safely.');
    }
    final entry = matches.single;
    final active = await loadActiveProfessions();
    final exists = active.any(
      (p) => p.trim().toLowerCase() == entry.profession.trim().toLowerCase(),
    );
    if (!exists) {
      if (!recoverProfession) {
        throw StateError('Restore this profession first.');
      }
      if (entry.profession.trim().isEmpty) {
        throw StateError('This record has no profession name.');
      }
      await restoreProfession(entry.profession);
    }
    await repo.setDeleted(id, false);
  }

  /// Return only professions not soft-deleted
  Future<List<String>> loadActiveProfessions() async {
    final all = await loadProfessions();
    final deleted = await loadDeletedProfessions();
    final deletedSet = deleted.map((e) => e.toLowerCase()).toSet();
    final active =
        all.where((p) => !deletedSet.contains(p.toLowerCase())).toList()
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
  // QR scan tip: "Don’t show again" flag
  // -------------------------------
  static const _kQrHintDismissed = 'qr_hint_dismissed';

  /// Has the user opted out of seeing the QR reminder tip?
  Future<bool> isQrHintDismissed() async {
    final prefs = await _prefsWithRetry();
    return prefs.getBool(_kQrHintDismissed) ?? false;
  }

  /// Persist the user's choice for the QR reminder tip
  Future<void> setQrHintDismissed(bool value) async {
    final prefs = await _prefsWithRetry();
    await prefs.setBool(_kQrHintDismissed, value);
  }

  /// Optional helper to re-enable the tip from a settings screen
  Future<void> resetQrHint() async {
    final prefs = await _prefsWithRetry();
    await prefs.remove(_kQrHintDismissed);
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

  static const _kTargetsKey = 'targets_v1';

  /// Cycle options
  static const targetCycles = ['week', 'month', 'year'];

  /// Load map: profession -> { minutes: int, cycle: 'week'|'month'|'year' }
  Future<Map<String, Map<String, dynamic>>> loadTargets() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kTargetsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = json.decode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded.map(
          (k, v) => MapEntry(k, (v as Map).cast<String, dynamic>()),
        );
      }
    } catch (_) {}
    return {};
  }

  /// Return (minutes, cycle) or null if not set.
  Future<(int minutes, String cycle)?> getTarget(String profession) async {
    final map = await loadTargets();
    final item = map[profession];
    if (item == null) return null;
    final mins = (item['minutes'] ?? 0) as int;
    final cycle = (item['cycle'] ?? 'week') as String;
    return (mins, cycle);
  }

  /// Save/overwrite target for a profession.
  Future<void> setTarget(
    String profession, {
    required int minutes,
    required String cycle,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final map = await loadTargets();
    map[profession] = {'minutes': minutes, 'cycle': cycle};
    await prefs.setString(_kTargetsKey, json.encode(map));
  }

  /// Remove target for a profession.
  Future<void> clearTarget(String profession) async {
    final prefs = await SharedPreferences.getInstance();
    final map = await loadTargets();
    map.remove(profession);
    await prefs.setString(_kTargetsKey, json.encode(map));
  }

  Future<int> sumMinutesForRange(
    String profession,
    DateTime start,
    DateTime end,
  ) async {
    final repo = EntryRepository();
    return repo.sumMinutesForRange(profession, start, end);
  }

  /// Persist an in-app language override.
  /// Pass '' or null to follow system language.
  Future<void> setLocaleCode(String? code) async {
    final prefs = await _prefsWithRetry();
    final c = (code ?? '').trim();
    if (c.isEmpty) {
      await prefs.remove(_kLocaleCode);
      locale.value = null;
    } else {
      await prefs.setString(_kLocaleCode, c);
      locale.value = Locale(c);
    }
  }

  /// Read the saved override code (null/'' means follow system language).
  Future<String?> getLocaleCode() async {
    final prefs = await _prefsWithRetry();
    return prefs.getString(_kLocaleCode);
  }
}
