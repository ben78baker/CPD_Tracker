import 'dart:convert';

import '../recording_engine_storage/sqlite_recording_repository.dart';

const templateRecordAllowance = 5;

class TemplateEvaluationStatus {
  const TemplateEvaluationStatus({this.owned = false, this.used});

  final bool owned;
  final int? used;
  bool get canCreate =>
      owned || (used != null && used! < templateRecordAllowance);
  bool get exhausted => used == templateRecordAllowance;
}

class TemplateAllowanceException implements Exception {
  const TemplateAllowanceException();
}

/// This CPD host state is part of the live transaction and excluded from
/// portable archives. The recording engine has no entitlement dependency.
class TemplateEvaluationLedger {
  const TemplateEvaluationLedger();

  static const namespace = 'cpd.template-evaluation.v1';
  static const _schema = 'schema';
  static const _version = '1';
  static const _full = 'full';

  String _key(String id) => 'template:$id';

  Future<TemplateEvaluationStatus> status(
    SqliteRecordingRepository tx,
    String templateId,
  ) async {
    final usage = _usage(await tx.loadHostState(namespace), templateId);
    return TemplateEvaluationStatus(used: usage?.used);
  }

  /// Only a known fresh rehearsal or its explicit upgrade can open authority.
  /// A missing marker on an existing profile never implies zero usage.
  Future<void> initialise(SqliteRecordingRepository repository) =>
      repository.transaction((tx) async {
        if ((await tx.loadHostState(namespace)).isNotEmpty) return;
        await tx.saveHostValue(namespace, _schema, _version);
        for (final collection in await tx.loadCollections()) {
          await accountImported(tx, collection.id);
        }
      });

  /// For a restored or upgraded graph use verified original identities.
  /// The receipt survives deleting or purging the tile that supplied it.
  Future<void> accountImported(
    SqliteRecordingRepository tx,
    String collectionId,
  ) async {
    final state = await tx.loadHostState(namespace);
    if (state[_schema] != _version) return;
    final usages = <String, Set<String>?>{};
    final changed = <String>{};
    await for (final record in tx.loadCollectionRecordOrigins(collectionId)) {
      final ids = usages.putIfAbsent(record.templateId, () {
        final usage = _usage(state, record.templateId);
        return usage?.used == templateRecordAllowance ? null : usage?.ids;
      });
      if (ids != null &&
          ids.length < templateRecordAllowance &&
          ids.add(record.origin)) {
        changed.add(record.templateId);
      }
    }
    for (final templateId in changed) {
      await _save(tx, templateId, usages[templateId]!);
    }
  }

  /// Call inside the transaction that inserted the record. If the allowance
  /// or the write cannot be verified, throwing rolls back the record too.
  Future<void> accountCreated(
    SqliteRecordingRepository tx,
    String templateId,
    String id, {
    required bool owned,
  }) async {
    final usage = _usage(await tx.loadHostState(namespace), templateId);
    if (!owned && (usage == null || usage.used == templateRecordAllowance)) {
      throw const TemplateAllowanceException();
    }
    if (usage != null && usage.used < templateRecordAllowance) {
      await _save(tx, templateId, usage.ids..add(id));
    }
  }

  ({int used, Set<String> ids})? _usage(
    Map<String, String> state,
    String templateId,
  ) {
    if (state[_schema] != _version) return null;
    final raw = state[_key(templateId)];
    if (raw == _full) return (used: templateRecordAllowance, ids: <String>{});
    if (raw == null) return (used: 0, ids: <String>{});
    try {
      final items = jsonDecode(raw);
      if (items is! List ||
          items.isEmpty ||
          items.length >= templateRecordAllowance ||
          items.any((item) => item is! String || item.isEmpty)) {
        return null;
      }
      final ids = items.cast<String>().toSet();
      if (ids.length != items.length) return null;
      return (used: ids.length, ids: ids);
    } on FormatException {
      return null;
    }
  }

  Future<void> _save(
    SqliteRecordingRepository tx,
    String templateId,
    Set<String> ids,
  ) => tx.saveHostValue(
    namespace,
    _key(templateId),
    ids.length >= templateRecordAllowance
        ? _full
        : jsonEncode(ids.toList()..sort()),
  );
}
