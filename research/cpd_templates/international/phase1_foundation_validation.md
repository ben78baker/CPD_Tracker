# Phase 1 recording engine foundation

This milestone implements the isolated foundation and a synthetic migration rehearsal described in the [architecture review](architecture_implications.md) and [feasibility report](phase1_decisions_and_feasibility.md). App startup, record screens, exports, and the existing SharedPreferences storage and recovery paths continue to use the shipped code.

## Recording engine

- [Dart models](../../../lib/recording_engine/models.dart) define collections, stable field instances, versioned reusable definitions and template recipes, ordered layout revisions, typed values, and attachment references. They have no Flutter, storage, or CPD imports.
- [SQLite adapter](../../../lib/recording_engine_storage/sqlite_recording_repository.dart) opens an explicit path and enables foreign keys. It saves recipe versions, applies a recipe independently to multiple collections, validates layout changes against the expected revision, and updates values, record tombstones, and ordered links transactionally. New attachment metadata can be saved in the same transaction as the record referencing it.
- Types cover short and multiline text, calendar dates, integer-minute durations, single and multiple controlled choices, and ordered evidence references. The host supplies any active-field cap. The engine resolves historical labels and choice vocabulary against the record's creation revision plus explicitly retrospective additions. Replacement fields get their own IDs. The existing data survives layout edits and template reapplication.
- [Managed originals](../../../lib/recording_engine_storage/managed_attachment_files.dart) stage copies in a private directory using a temporary file and a rename. SQL stores metadata and links. Original bytes and other referenced files stay in place when a transaction fails, a record is deleted, or a field is retired. Reclamation is deferred.

## Synthetic migration and recovery

The [CPD adapter](../../../lib/cpd_migration/legacy_migration.dart) accepts an explicit map and a synthetic Documents directory. It captures the raw source before processing and uses deterministic IDs for the source, collections, record positions and attachment positions. The source map includes preference keys, record JSON, legacy targets, and unknown extensions. The original record strings remain available in the snapshot.

| State | Meaning |
| --- | --- |
| Captured | The raw snapshot exists. A parse or SQL interruption can be retried from the same input. |
| Blocked | Ambiguous records or targets remain in the original snapshot with diagnostics. The migration writes no partial record graph. |
| Staged | The mapped graph and staging marker committed together. Read-back verifies the graph and relationships. |
| Verified | An explicit second pass matched the input, graph, SQLite integrity and local evidence fingerprints. There is no activation transition. |

Preferences, files and outside links are read only from supplied fixture inputs. Local evidence is resolved only under the synthetic app's `attachments/` directory. Managed paths, valid older Documents paths and URLs retain their order. Missing or unsafe paths retain their raw locators as unresolved references. Duplicate legacy IDs remain separate rows, and orphan professions remain recoverable as hidden collections. Unknown record fields remain in the source snapshot for recovery. They are available as raw data rather than editable typed fields.

A failed verification leaves the destination staged. The original legacy data remains the recovery source. A future production migration needs a coordinated source freeze, writable-space and separate recovery-copy checks, a single-writer activation gate, and a documented procedure for any post-cutover repair. The synthetic rehearsal does not open the live preferences store or install the new database into the app.

## Test entry points

- `flutter test --no-pub` runs the existing regression suite and new [model](../../../test/recording_engine/models_test.dart) and [file handling](../../../test/recording_engine/managed_attachment_files_test.dart) tests.
- `flutter analyze --no-pub lib/recording_engine lib/recording_engine_storage lib/cpd_migration test/recording_engine` checks the new sources and fixtures.
- The [native smoke target](../../../test/recording_engine/native_recording_smoke.dart) runs four scenarios with [synthetic equipment data](../../../test/recording_engine/equipment_fixture.dart), transaction rollback with close/reopen and retry, CPD staging/verification with evidence changes, and a blocked import. The rollback fault is an injected foreign-key failure. It exercises the same transaction boundary as interruption without simulating power loss.

### Results on 20 November 2026

| Check | Result |
| --- | --- |
| Flutter regression suite | 101 passed, including 7 new host tests. |
| Static analysis | New modules and fixtures pass. Full-project analysis reports 16 findings in existing app code, feasibility probes and a local marketing script. |
| Host SQLite feasibility probe | 2 passed on SQLite 3.51.0, including a process exit before commit. |
| iPhone 17 simulator | All 4 native smoke scenarios passed on iOS 27.2, SQLite 3.54.0. |
| Pixel 6 emulator | All 4 native smoke scenarios passed on Android 14 (API 34), SQLite 3.39.2. |

The test apps use the same locked sqflite package as the tracker. The simulator results cover the tested runtimes. iOS 15.6 and Android API 24 remain minimum-version runtime checks.

### Running the native smoke in isolation

Create a disposable Flutter mobile project outside the repository and use a dedicated bundle or application ID. Set its Dart package name to `cpd_tracker` for the test imports and include the same locked versions of `sqflite`, `path` and `uuid` as the main project. Copy the three implementation directories from `lib/` and `native_recording_smoke.dart` and `equipment_fixture.dart` into the same relative locations. Configure the disposable Xcode and pod targets to match the app's existing minimum of iOS 15.6. Resolve packages and run the dedicated target on the device:

```sh
flutter run -d <device-id> -t test/recording_engine/native_recording_smoke.dart
```

Look for `RECORDING_SMOKE_PASS` and the OS SQLite version in the session log. The harness creates its own temporary databases and attachments.

## Gates before activation

1. Verify plugin operation, file access, and interruption/retry on Android and the oldest supported iOS and Android configurations. Rehearse process termination, low storage, and recovery with separate snapshots.
2. Add the production read-only inventory, writer freeze and recovery controls. Validate legacy path edge cases and distinguish an actionable recovery review from a blocking migration error.
3. Put legacy projections and every record mutation behind the new repository. Compare search, target calculations, deleted-state restoration, report selection, exported PDF/CSV semantics, and evidence handling against the shipped workflow.
4. Review scaling on realistic record and evidence volumes. Authorise cutover separately after the parity and recovery checks pass. Keep editor rollout, store entitlements, branded and scheme-specific exports, and shared-package extraction on their respective roadmaps.
