# Phase 2 legacy compatibility and validation

The shipping app still constructs its SharedPreferences record and settings stores. The new adapter is available through an explicit staged-store injection. Tests and disposable mobile builds use synthetic preferences, databases and evidence files.

## Compatibility boundary

- [CPD data interfaces](../../../lib/cpd_compatibility/cpd_data_store.dart) define the record and profession operations shared by the legacy and staged stores. Record selection and duration arithmetic live on the CPD side. [Target periods and scaling](../../../lib/cpd_compatibility/cpd_targets.dart) are shared by the home screen and parity tests.
- [SQLite CPD adapter](../../../lib/cpd_compatibility/sqlite_cpd_store.dart) opens only a verified migration. The generic repository persists host metadata and record changes in one transaction. Its additive v2 schema stores namespaced host metadata while keeping CPD concepts outside the engine.
- The adapter projects calendar dates, integer minutes and ordered attachment IDs into the existing CPD entry model. It preserves original profession labels and attachment strings, exact-case target lookups, source order, legacy numeric IDs, and record and profession tombstones. Existing records and their original files remain available after edits.
- Record forms, the profession dashboard, global search and deleted-record recovery can receive a staged store together. Appearance, profile, date format and week-start preferences continue through the existing settings store. Reports use the existing selection and rendering pipeline. CSV content generation has a pure entry point shared by the original share path and tests.
- Duplicate legacy IDs remain distinct in storage. The compatibility layer refuses numeric-ID writes where the intended record is ambiguous and advances new IDs past existing IDs if the legacy counter overlaps. Unknown fields survive in the original recovery snapshot. Invalid dates, time-zone ambiguity, fractional durations and malformed rows block migration with the source preserved.

## Export comparison

The native harness builds outputs independently from SharedPreferences records and the SQLite projection. It checks the following:

| Export | Comparison |
| --- | --- |
| Text-only PDF | Record presentation, date range, totals, attachment indicators, page count and rendered page dimensions and CRCs at 48 dpi. |
| PDF with evidence | The same presentation and rendered-page checks, one synthetic photograph, both pages of a native-rasterised source PDF, and a missing-file indicator. |
| Clickable links | HTTPS, mail and telephone destinations in the presentation plus link annotations in the generated PDF. |
| CSV | Exact CSV content, with a host test for legacy quoting, Unicode, date headers, totals and multiline handling. |
| Conditional ZIP | ZIP present only when a local original cannot be embedded, matched manifest and archive structure, and byte-identical originals. The enclosed report is compared by the same PDF page signature. |

PDF creation timestamps and the time-stamped archive report filename are excluded from equivalence. The native comparison pins the standard-font fallback and uses a synthetic icon for reproducibility. The downloadable font path, other locales, native share sheets and external link destinations remain end-to-end release checks.

## Migration and independent recovery

The [read-only inventory](../../../lib/cpd_migration/legacy_preferences_inventory.dart) bypasses legacy helpers that normalise on read. The [recovery copy](../../../lib/cpd_migration/legacy_recovery_snapshot.dart) captures raw values and verifies a manifest and owned files in a separate private directory before publishing it. Tests restore into a fresh Documents directory after deleting the synthetic source, including rebasing owned absolute references against the captured source directory. Unsafe or unsupported items stay accounted for, and originals outside the managed tree are never copied.

The native test constrains SQLite's page count to provoke a genuine `SQLITE_FULL` during a staged write. SQLite rolls back the transaction and the native driver can retain a stale transaction ID. The repository closes the failed handle, then the test reopens, checks the captured source and empty record graph, and retries. A separate capacity check rejects an insufficient recovery destination before publishing anything.

For the termination test the harness captures the source separately, writes the graph inside an uncommitted transaction, then emits `CPD_PARITY_KILL_READY`. An external launcher stops the disposable process. Relaunch checks that the capture survives, no partial graph is visible, and retry and verification complete once.

## Results on 20 November 2026

| Check | Result |
| --- | --- |
| Flutter host suite | 110 passed, including nine new tests. |
| Static analysis | Full-project analysis has the same 16 findings as Phase 1. New compatibility, migration and test code adds no findings. |
| iPhone 16 Pro simulator, iOS 18.5 | All five native scenarios passed, including native PDF/ZIP generation and SQLite full rollback. External termination at the open transaction checkpoint was followed by a verified database containing exactly one record. |
| Pixel 6 emulator, Android 14 (API 34) | All five native scenarios passed. Force-stop at the open transaction checkpoint and relaunch in a new process emitted the recovery pass marker. |
| General recording engine regression | All four Phase 1 native scenarios passed again on both devices, including the equipment-maintenance fixture. |
| iOS 15.6 and Android API 24 | The exact runtimes and suitable connected devices were unavailable. Minimum-version runtime compatibility remains unverified. |

## Running and verifying

- `flutter test --no-pub` runs the complete host regression suite including the new route, date/CSV and recovery tests.
- Set up a disposable mobile app using the [Phase 1 harness instructions](phase1_foundation_validation.md#running-the-native-smoke-in-isolation), keeping its own application ID and the Dart package name `cpd_tracker`. Copy `lib/` and [the native parity target](../../../test/cpd_compatibility/native_cpd_parity.dart) into that app. Resolve the app's pinned `sqflite`, `path`, `uuid`, `shared_preferences`, `archive`, `http`, `image`, `pdf`, `printing`, `path_provider`, `share_plus`, `open_filex`, `url_launcher`, `intl` and Flutter localisations packages. The normal harness marker is `CPD_PARITY_PASS`.
- Run the same target with `--dart-define=CPD_PARITY_EXIT=true` for the termination rehearsal. After `CPD_PARITY_KILL_READY`, terminate only the disposable app and launch the installed binary again without clearing its sandbox. The recovery marker is `CPD_PARITY_EXIT_PASS`. Use a fresh disposable app sandbox for another two-launch rehearsal.

## Remaining gates

1. Test with iOS 15.6 and Android API 24 hardware or supported runtimes. Production signing and application minimums were kept in place throughout.
2. Rehearse with production-shaped synthetic volumes, oldest legacy attachment path shapes, and large reports. The current compatibility projection favours correctness, with per-record metadata and SQLite reads to profile before adoption.
3. Add the production writer freeze, real available-space measurement, recovery review workflow and one-writer activation gate. Define the operator decision for unresolved evidence, conflicting records and stale absolute paths. A recovery copy on the same filesystem protects against a failed migration, while device-loss recovery needs separate backup coverage.
4. Exercise native share sheets, foreground/background interruption and on-device attachment viewing in a controlled parity preview before authorising a production cutover.
