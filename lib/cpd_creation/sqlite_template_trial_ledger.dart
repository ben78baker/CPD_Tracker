import 'dart:io';

import 'package:sqflite/sqflite.dart';

import 'template_trials.dart';

/// Internal trial authority. Callers may provision a newly created, isolated
/// rehearsal profile. Existing profiles are never silently reinitialised.
class SqliteTemplateTrialLedger implements TemplateTrialLedger {
  SqliteTemplateTrialLedger(this.file, {DatabaseFactory? factory})
    : _factory = factory ?? databaseFactory;

  final File file;
  final DatabaseFactory _factory;

  Future<void> provision() async {
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw StateError('Trial history already exists.');
    }
    final db = await _open(create: true);
    await db.close();
  }

  Future<Database> _open({required bool create}) async {
    if (!create &&
        await FileSystemEntity.type(file.path, followLinks: false) !=
            FileSystemEntityType.file) {
      throw StateError('Trial history is missing.');
    }
    return _factory.openDatabase(
      file.path,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          final mode = await db.rawQuery('PRAGMA journal_mode = DELETE');
          await db.execute('PRAGMA synchronous = FULL');
          final sync = await db.rawQuery('PRAGMA synchronous');
          if (mode.single.values.single != 'delete' ||
              sync.single.values.single != 2) {
            throw StateError('Trial history could not enable durable writes.');
          }
        },
        onCreate: (db, _) async {
          if (!create) throw StateError('Trial history has no schema.');
          await db.execute(
            'CREATE TABLE observation (id INTEGER PRIMARY KEY '
            'CHECK (id = 1), utc_ms INTEGER NOT NULL CHECK (utc_ms >= 0))',
          );
          await db.insert('observation', {'id': 1, 'utc_ms': 0});
          await db.execute(
            'CREATE TABLE redemption (template TEXT PRIMARY KEY '
            'NOT NULL, started_ms INTEGER NOT NULL CHECK (started_ms >= 0), '
            'expires_ms INTEGER NOT NULL CHECK '
            '(expires_ms = started_ms + ${templateTrialDuration.inMilliseconds}))',
          );
        },
        onDowngrade: (_, _, _) =>
            throw StateError('Unknown trial history version.'),
      ),
    );
  }

  Database? _database;
  Future<Database>? _opening;

  @override
  Future<TemplateTrialStatus> check(
    String templateId, {
    required TrialClock clock,
    required bool start,
  }) async {
    if (templateId.isEmpty) throw ArgumentError.value(templateId, 'templateId');
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      await close();
      throw StateError('Trial history is missing.');
    }
    final db = _database ??= await (_opening ??= _open(create: false));
    return db.transaction((tx) async {
      final rows = await tx.query('observation', where: 'id = 1');
      final observed = rows.single['utc_ms'] as int;
      final redemptions = await tx.query(
        'redemption',
        where: 'template = ?',
        whereArgs: [templateId],
      );
      final redemption = redemptions.singleOrNull;
      final activation = redemption?['started_ms'] as int?;
      if (redemption != null &&
          (activation == null ||
              redemption['expires_ms'] !=
                  activation + templateTrialDuration.inMilliseconds)) {
        throw const FormatException('Invalid trial interval.');
      }
      final result = evaluateTrial(
        clock: clock,
        previousObservation: observed,
        activation: activation,
        start: start,
      );
      if (result.observed > observed) {
        await tx.update('observation', {
          'utc_ms': result.observed,
        }, where: 'id = 1');
      }
      if (result.activated case final activated? when activation == null) {
        await tx.insert('redemption', {
          'template': templateId,
          'started_ms': activated,
          'expires_ms': activated + templateTrialDuration.inMilliseconds,
        });
      }
      return result.status;
    });
  }

  Future<void> close() async {
    final db = _database;
    _database = null;
    _opening = null;
    await db?.close();
  }
}
