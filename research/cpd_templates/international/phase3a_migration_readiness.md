# Phase 3A controlled migration rehearsal

Normal startup still constructs the SharedPreferences-backed record and settings stores. The SQLite coordinator and receipt consumer have no normal-launch entry point. The production activation guard is a hard-coded false value. The native change adds an on-demand volume capacity query on each platform.

## Coordinator and recovery

1. The caller supplies an app-private attempt directory outside Documents and the read-only legacy inventory. An in-process attempt reservation and an advisory file lock exclude competing attempts in that directory. The legacy write gate drains admitted work in the main Dart isolate and rejects new preference, record and owned-evidence writes. Composite operations already admitted can finish their nested writes.
2. The coordinator checks space for both the recovery copy and SQLite before copying evidence. It checks again after the copy and before opening SQLite. iOS queries the destination volume through FileManager. Android uses StatFs available bytes. SQLite's allocation reserve includes the raw source, record projection, journal and a margin. A capacity estimate can still be overtaken by another writer on the volume.
3. The coordinator copies raw records, targets and owned evidence to a separate recovery directory and validates its manifest and file fingerprints. The source and copy are checked against each other before continuing and again after read-back verification. Interrupted temporary copies are distinct from published recovery snapshots.
4. The generic repository stages the graph in a transaction. It verifies the records, field values, tombstones, relationships, attachment order and metadata, SQLite integrity, and owned evidence fingerprints. The CPD adapter then compares projected entries, original dates and strings, ordered references, targets and profession settings with the frozen legacy source.
5. The journal records named checkpoints, safe issue codes and row/attachment positions. A durable SQLite receipt could be written only after the final checks. The rehearsal path exercises that transaction with a receipt explicitly marked as rehearsal. Verification-only attempts stop at Ready and have no receipt.
6. Before a receipt, failure releases the freeze and leaves the legacy source available. A restart can resume the same attempt after checking its source and independent snapshot. A changed source requires a fresh attempt directory. The earlier source copy and diagnostics remain addressable. A receipt committed just before interruption is authoritative over the preceding Ready journal for that attempt.

The write gate protects the existing main-isolate writer surface. Before future cutover, any additional background writers, processes, native imports or externally editable evidence roots must join the same exclusivity contract. The file lock protects the attempt directory. The gate protects the legacy writers in the application process.

## Review and retention

The review API exposes the original raw row from the independently verified manifest. Raw values can still be read when separate evidence is damaged. Full restoration and activation continue to require evidence verification. It reports invalid or ambiguous dates, fractional durations, duplicate legacy identifiers and unsupported evidence references. It also accounts for unknown extensions and missing originals. Ambiguous identities and unsupported provider references require review before activation. Known missing evidence can remain an explicit unresolved reference in a verified graph, and it keeps the recovery snapshot pinned. No guessed conversions or duplicate-ID remapping take place.

The receipt records verification and activation timestamps separately. The minimum 30-day retention runs from activation UTC. An incomplete, failed or unresolved migration or uncertain integrity holds the snapshot. After 30 days, verified eligibility means manual review only. No process in this stage deletes a completed recovery snapshot or a legacy original.

## Activation and rollback plan

[Phase 3B](phase3b_migration_readiness.md#startup-authority) refines the handoff rules below. The independent marker is written before the receipt. From that point, legacy writes stay sealed even if receipt publication is interrupted.

- A separately approved release must explicitly authorise the cutover code change and wire one startup authority resolver before any writer or screen is constructed. Production uses an app-private destination, production-scoped receipt and coordinator health checks. Rehearsal receipts never select production storage.
- Before committing the receipt, confirm the independent recovery manifest, frozen source, SQLite constraints, projected records and targets, evidence integrity, review state, minimum supported platforms and established parity gates. Persist the authority marker before handing off to SQLite. Reopen and verify that marker during startup to recover a process terminated at the handoff.
- Before the marker, legacy retains authority. On failure, keep the independent copy, destination and safe diagnostic report. Resume against an unchanged source or start a separate attempt following review. User-facing recovery and correction policy require separate approval.
- After the marker, SQLite has authority. If startup or validation fails, stop writes and retain both stores and the originals. A controlled return to legacy requires independently proving that SQLite has accepted zero new writes and that the legacy source still matches the snapshot. Otherwise preserve the authoritative SQLite store and use verified restore, reconciliation or forward repair. A restart must never silently resume a stale legacy writer.
- Retire legacy storage only after a separate sign-off and recovery rehearsal with a verified active store, an elapsed retention period and resolution of outstanding evidence. Any future cleanup uses an explicit inventory, reference checks, separate approval and retryable operations. Device-loss recovery needs a backup outside the affected device.

## Reproducing the native checks

Create a disposable mobile app using the [Phase 2 harness setup](phase2_compatibility_validation.md#running-and-verifying). In that app only, add the same locked `file_picker` dependency and copy the iOS and Android storage-channel implementations. Copy the production `lib/` tree and the two Dart native targets in `test/cpd_migration/`. Use the same installed Flutter and SQLite driver versions as the tracker. The app identifier must remain dedicated to the rehearsal.

Run `test/cpd_migration/native_migration_rehearsal.dart` to seed synthetic SharedPreferences, build all three datasets and report progress and timings. It also exercises historical template versions, review and low-storage retry, retention and oversized snapshot compatibility. For the separate termination probe use `--dart-define=CPD_PHASE3_MODE=crash`, stop the disposable binary on `CPD_PHASE3_KILL_READY` and relaunch it with the sandbox intact. Select a checkpoint with `--dart-define=CPD_PHASE3_EXIT_AT=verifying` or `ready`. Use a new disposable sandbox for a fresh two-launch probe.

For iOS, the committed Swift fixture runs in a UI-test bundle attached only to the disposable app. Enable local Documents visibility in its scratch plist so Files can select the two fixtures. Run the native target with `--dart-define=CPD_PHASE3_MODE=actions`. On Android put the harness's synthetic PDF and PNG in the emulator Downloads provider. Open the native share sheet and dismiss it, then choose both documents and verify the re-imported bytes. Production app plist and Android target settings are unchanged.

## Measurements on 20 November 2026

The synthetic hosts ran in Flutter debug mode on an arm64 macOS host with Flutter 3.41.6, Dart 3.11.4, Xcode 27.2 and the app’s locked sqflite 2.4.2. Devices were the iPhone 16 Pro simulator on iOS 18.5 and the Pixel 6 emulator on Android 14 (API 34). Each size had six professions and included deleted records, targets, repeated evidence references, links and missing originals. The large fixture had approximately 86 MiB of source files and JSON. Separate fixtures covered invalid data, historical template choices and an oversized Unicode payload from a v2 database.

| Runtime and records | Owned originals | Migration to Ready | Peak extra disk | Peak process RSS (increase) | SQLite size |
| --- | ---: | ---: | ---: | ---: | ---: |
| iOS · 32 | 6 | 0.77 s | 3.72 MiB | 558.0 MiB (+37.1) | 0.17 MiB |
| iOS · 420 | 48 | 4.89 s | 29.46 MiB | 626.9 MiB (+74.3) | 1.04 MiB |
| iOS · 3,600 | 144 | 18.22 s | 94.61 MiB | 702.3 MiB (+84.8) | 8.03 MiB |
| Android · 32 | 6 | 1.83 s | 3.73 MiB | 440.3 MiB (+65.3) | 0.18 MiB |
| Android · 420 | 48 | 8.10 s | 29.47 MiB | 417.0 MiB (+35.6) | 1.04 MiB |
| Android · 3,600 | 144 | 39.35 s | 94.61 MiB | 469.8 MiB (+58.1) | 8.04 MiB |

| Runtime and records | Legacy reload and decode | Open staged store | Profession load and search | CSV construction | Text PDF |
| --- | ---: | ---: | ---: | ---: | ---: |
| iOS · 32 | 7.1 ms | 1.2 ms | 4.2 ms | 3.7 ms | 46 ms |
| iOS · 420 | 23.8 ms | 1.2 ms | 31.5 ms | 27.1 ms | 32 ms |
| iOS · 3,600 | 170.5 ms | 3.7 ms | 226.9 ms | 423.6 ms | 35 ms |
| Android · 32 | 24.4 ms | 4.7 ms | 8.9 ms | 3.4 ms | 71 ms |
| Android · 420 | 6.4 ms | 5.5 ms | 38.8 ms | 1.7 ms | 34 ms |
| Android · 3,600 | 30.0 ms | 9.4 ms | 121.9 ms | 8.4 ms | 29 ms |

Disk and RSS are sampled every 50 ms and at checkpoints. Additional disk excludes the source. RSS includes the debug Flutter process and simulator overhead. The increase is relative to the loaded fixture just before migration. Each row is a single rehearsal. Simulated timing can vary with GC, host load and filesystem behaviour.

The initial scratch-app frame took 240 ms on iOS and 319 ms on Android. The staged-store opening measurement excludes the first search. Production startup performs no coordinator work in this phase. The measured search includes loading the SQLite projection and applying the existing CPD filter. CSV covers all results for one profession. The text PDF uses up to 20 records. These figures are simulator observations and provide no startup, latency or memory guarantee on physical hardware.

The first Android large run failed because CursorWindow could not return the inline migration snapshot row. Schema v3 keeps raw source and planner metadata in 64 KiB UTF-8 chunks. Both platforms passed the corrected large fixture and recovered an older 2.4 MB inline Unicode source without reading the whole row. The same change preserves existing v1/v2 staging data on upgrade.

## Native results and remaining gates

- iOS 18.5 and Android 14 both measured real destination capacity through their native APIs. An injected drop in capacity after snapshot publication blocked database creation, and retry reused the copy. The five Phase 2 parity scenarios also passed again on both platforms with schema v3, including a genuine SQLite full error, connection reopening and transactional retry.
- Android terminated after staged SQL commit and before verification. Relaunch verified the existing attempt, wrote one rehearsal receipt and kept its original activation time on retry. iOS terminated at Ready after verification and before the authority commit. Read-back confirmed no receipt before restart and exactly one record with a rehearsal receipt afterward.
- The iOS XCUITest opened and dismissed the native share sheet and selected PDF and PNG fixtures in the local Files provider. A separate comparison matched both imported files byte for byte. The Android Sharesheet displayed the PDF preview. Downloads returned the PDF and PNG, and the app verified their CRCs after copying.
- English, German, French and Portuguese evidence PDFs embedded Noto Sans on both platforms, including the photograph and both pages of the source PDF. Evidence report builds took 123–170 ms on iOS and 143–219 ms on Android. Sharing tests covered presentation and cancellation, with delivery and cloud providers left for the release matrix.
- The full Flutter suite passed all 119 tests. Full-project analysis reported the same 16 existing findings as Phase 2 and zero new findings.
- iOS 15.6 and Android API 24 runtimes and suitable connected devices were unavailable. The older paired iPhone was unavailable. iOS 18.5 and Android API 34 were the closest installed environments. The actual minimum releases and signed upgrade behaviour still need verification.

**Cutover assessment.** Ready for an internal pre-cutover review. Production activation should remain disabled. Obtain approval for the recovery-review and duplicate-resolution policy, the startup authority resolver and rollback rules, and a physical device matrix covering the exact minimums, high memory pressure, lower storage, large individual records and realistic evidence volumes.
