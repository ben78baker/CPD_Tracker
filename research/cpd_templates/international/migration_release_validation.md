# Migration release-readiness validation

## Phase 10 recovery and release checks

**23 November 2026 · Baseline `958a7fa`.** The recovery and progress experience is accessible through the isolated rehearsal. The normal app still starts on its existing storage.

### Recovery procedure

Before publishing the authority fence, the coordinator records a pending binding in SQLite using a durable journal. That binding names the verified source and independent recovery snapshot. A new startup holds the same migration lock and legacy write freeze while it checks the journal, source, snapshot, SQLite graph, CPD projection and evidence. It will complete only an empty or partial fence that matches the pending binding byte for byte, or a complete matching fence with an uncommitted receipt. The receipt transaction consumes the pending binding. An independent release marker is flushed before an application writer can open so a stale staged database cannot prove that the handoff is still pending.

If the pending proof is absent, the bindings differ, a release marker already exists without a verified receipt, or the data does not verify, the app leaves both writers closed. The recovery screen asks the user to keep the app installed and contact support. **Copy recovery details** supplies only the startup reason and recovery-copy status. Staff should preserve the current database with any journals and the independent recovery copy, verify the artifacts separately, and use the snapshot only in a separate review directory. Replacing the active store or deleting the fence to force a retry is outside this procedure. If independent review cannot establish one authority, keep both stores closed and preserve the copies.

The new screen uses the selected app colour and the six existing locales. During recovery it shows the reported stages with an indeterminate indicator and explains that a subsequent launch rechecks the records. **Continue** appears only after the guarded SQLite authority is established.

| Recovery condition | Exact Android API 24 | Physical OPPO, Android 13 |
| --- | --- | --- |
| Fence created and empty | Revalidated the pending handoff and adopted SQLite once | Same result after force-stop |
| Complete fence without a receipt | Revalidated and adopted SQLite once | Same result after force-stop |
| Receipt written inside an uncommitted transaction | Rolled back the incomplete receipt and adopted SQLite once. Also passed after an emulator OS reboot and two additional launches. | Same result after force-stop and repeat launch |
| Missing pending proof or a stale staged database with a release marker | Both writers stayed closed. The native UI showed the assisted route without Continue. | Assisted branch covered by API 24 |
| Before the fence, after receipt commit and before the first active write | All four additional boundaries reopened the correct authority | Covered by API 24 |
| During a later SQLite write | Preserved the committed row and rolled back the unfinished write | Same result after force-stop |

Every case retained exactly one import and passed SQLite integrity and foreign-key checks. The fixtures included an owned attachment, a deleted record, an archived profession and a target. Each completed recovery confirmed the original row projection, preference values, attachment fingerprint and receipt across rechecks. This qualifies process termination and an emulator reboot. It does not qualify abrupt power loss or damaged flash storage.

### Performance changes

The coordinator previously compared the snapshot and live originals twice before SQLite staging. It now checks the manifest when publishing the snapshot-ready phase, then independently checks the complete snapshot and live source before any staged SQLite writes and again before activation. Each freshly copied file is flushed and its digest compared with the source before the snapshot is published. This removes redundant hashing without removing the checks at either write boundary. Digest format and historical snapshot compatibility are preserved.

The OPPO ran a non-debuggable AOT release-mode APK with the unchanged minimum API 24. It used a separate package ID and local development signing. The normal CPD package kept its existing package metadata and data.

| Physical OPPO, optimised AOT | 1,200 records | 3,600 records |
| --- | ---: | ---: |
| Managed originals | 48 | 144 |
| Migration through authority receipt | 23.910 s | 64.093 s |
| Recovery copy ready | 5.557 s | 13.545 s |
| SQLite database | 2,883,584 bytes | 8,433,664 bytes |
| Sampled peak process RSS | 254 MiB | 369 MiB |
| Largest gap in the 50 ms Dart timer | 211 ms | 409 ms |
| SQLite profession load and search | 199 ms | 427 ms |
| CSV generation | 8 ms | 22 ms |
| Text PDF generation, up to 20 records | 94 ms | 78 ms |

Both clean datasets achieved parity and rehearsal authority. The separate mixed dataset returned explicit review in 1.998 s and preserved all 1,205 raw rows and the evidence in a separate recovery directory. RSS describes the whole process and timer gaps are a scheduling proxy. They do not establish allocation costs or visual frame-rate guarantees.

In a second run on the same OPPO and AOT toolchain, the control APK restored only the two redundant verification passes. The 1,200-record control took 30.488 s and the 3,600-record control took 81.375 s. Removing the scans saved 6.578 s and 17.282 s respectively, or about 21% in both cases. The larger run reached the snapshot-ready checkpoint 16.913 s sooner. This isolates a material part of the migration overhead to the extra hashing. The comparison with the previous debug emulator also changes hardware and compiler mode, so it does not isolate debug overhead.

The 3,600-record control sampled 375 MiB peak RSS and a 353 ms maximum timer gap, versus 369 MiB and 409 ms in the optimised run. The optimisation establishes a time improvement in this comparison. The sampled memory and responsiveness vary, and the SQLite stage and verification after snapshot readiness still took about 50.5 s. Use a device allocation trace and repeated runs before choosing further memory or responsiveness optimisation.

For reproduction, build the native rehearsal entry point from a disposable copy with application ID `com.ingeneralapps.cpdtracker.phase10` and the release compiler, using a development signer for that package. The scratch Android activity supplies the launch intent's `cpdRehearsalCommand` through the `cpd_tracker/release_rehearsal` method channel. The Dart entry point accepts the command on Android release builds only for this separate package. The benchmark command is `scale`. The recovery tests use `arm <checkpoint>`, then `resume <checkpoint>` after stopping the process, and `repeat <checkpoint>` once authority is established. Inspect the target device, APK package, minimum API and AOT library before installing.

### iOS 15.6 compilation and native dependencies

Xcode 27.2 compiled the unsigned production Release target and the migration and recovery Profile entry point in a disposable checkout. The two Runner binaries and their packaged application manifests report a 15.6 deployment target. The production App and Flutter frameworks report 13.0. The packaged SQLite, SharedPreferences, file picker, image picker, PDF printing and sharing frameworks report 15.6. No embedded framework examined requires a higher OS. The Profile build used an xcconfig forwarding file confined to the disposable checkout. This is compilation and binary metadata evidence. Exact iOS 15.6 runtime migration, interrupted recovery, evidence providers and export sharing remain unverified. Use a device still running 15.6, or an exact supported runtime if one becomes available. [Apple native testing guidance](https://developer.apple.com/documentation/Xcode/running-your-app-on-simulated-or-physical-devices)

### Play-signed in-place upgrade procedure

1. Obtain approval for the precise test artifact, version code, tester accounts and Google Play **Internal testing** track before uploading. Use the current application ID and upload signer. The candidate must permit migration only for a verified rehearsal source. Review the candidate and check that normal users still follow the current startup path.
2. In Play Console, open App integrity and record the public app-signing certificate and any rotated lineage separately from the upload certificate. On a dedicated Play-certified Android device, install the current legacy app from Play before opting into the internal track. Confirm the installer, version code and signing fingerprints of the delivered APKs.
3. Seed the Play-delivered legacy app through its normal UI with disposable records, targets, deleted records and original files. Inventory those items and independently copy or hash the original evidence. If the release app cannot export diagnostic data, use its visible screens and exports to record the baseline.
4. After approval, upload the reviewed candidate with a higher unused version code to **Internal testing**, restricted to the approved test accounts. Use the tester opt-in link and update through Play without uninstalling or clearing data. Internal App Sharing uses its own test signing certificate and cannot qualify the production signing lineage. [Internal testing](https://support.google.com/googleplay/android-developer/answer/9845334) · [Internal App Sharing signing](https://support.google.com/googleplay/android-developer/answer/9844679) · [Play App Signing](https://developer.android.com/studio/publish/app-signing)
5. Check that Play kept the application ID and installed a compatible signing lineage. Compare all records, targets, settings and evidence before and after migration. Repeat force-stop recovery and one committed SQLite write across restart. Record the results privately and end the restricted test under the agreed tester plan.

No Play upload, native signing change or publication was performed in Phase 10. A local Android APK still cannot qualify this gate.

### Acceptance and cutover decision

The exact API 24 AOT integration passed Standard CPD, custom layout revisions and historical values, template versions, the five-record allowance, simulated entitlements, backup and restore, and native PDF evidence in four languages. Large migration fixtures also checked standard PDF and CSV. The recovery screen passed large-text, indeterminate progress, guarded Continue and clipboard tests. The full Flutter suite passed **266 tests**. Static analysis retained the existing 13 findings.

**Keep production activation disabled.** The pending-proof recovery work closes the known safe-repeat handoff cases. Release still requires exact iOS 15.6 runtime evidence and a Play-delivered in-place upgrade. Before cutover, qualify the support-assisted handling of a genuinely damaged store and agree acceptable progress and memory behaviour on lower-resource devices. Even the optimised large OPPO run required about a minute, so visible progress and safe restart remain part of the cutover design.

## Baseline evidence from `958a7fa`

**23 November 2026.** Validation used the feature branch and a disposable application ID on the Android API 24 emulator. The production app did not acquire a SQLite startup path.

## Platform and signing evidence

| Environment | Evidence | Release position |
| --- | --- | --- |
| Android 7.0 (API 24), arm64 emulator | Exact minimum OS. The separate debug application exercised native SharedPreferences, sqflite and the coordinator. | This validates the Android minimum in the emulator. Physical low-memory and low-storage behaviour still needs release-build measurement. |
| OPPO CPH2371, Android 13 (API 33) | Build 15 → build 16 using the same development certificate and app identity. All original records, settings and evidence verified. Interrupted during staging, then retried. | Passed for the development-signed upgrade. [OPPO rehearsal](android_in_place_migration.md) |
| iPhone XR, iOS 18.7.10 | Development-signed in-place upgrade, per-record parity, evidence hashes, interrupted staging in a separate workspace and native exports. | Passed on this OS and signing path. [XR rehearsal](xr_in_place_migration.md) |
| iOS 15.6 | The installed simulators start at 18.5. Attached iPhones reported 18.7.10 and 27.2.1. Xcode 27.2 returned “iOS 15.6 is not available for download” for the exact runtime. The project still targets 15.6. | **Unverified.** Use a device actually running iOS 15.6 or an exact compatible simulator runtime. No newer OS was substituted in this phase. [Apple simulator runtime guidance](https://developer.apple.com/documentation/safari-developer-tools/adding-additional-simulators) |
| Google Play App Signing | The public listing and local AAB use `com.ingeneralapps.cpdtracker`. The two local AAB files had identical SHA-256 digests. Their manifest reports version 1.4.1 (15), minimum API 24 and target API 36. `jarsigner` verified the bundle signature. | **Unverified for Play upgrades.** Verification covers the local bundle's signer. The connected CPD installation was the ADB rehearsal, neither emulator supplied a Play-installed CPD app, and no Play-signed migration build was available. No upload or publication occurred. [Play listing](https://play.google.com/store/apps/details?id=com.ingeneralapps.cpdtracker) · [Play App Signing](https://developer.android.com/studio/publish/app-signing) |

The existing Gradle release configuration reads the local signing properties and uses the configured release signer. The AAB certificate fingerprint begins `23972A13` and differs from the development APK certificate, which begins `5878C87F`. The Play delivery certificate remains unverified. Record the Play App Signing certificate or lineage from Play Console or a Play-delivered base APK. When authorised, install the legacy version from Play, inventory the source, and apply a candidate delivered through the same app-signing lineage and with a higher version code. Compare the app container and data before opening the updated app. [Android update compatibility rules](https://developer.android.com/google/play/app-updates)

## Dataset and instrumentation

The scale fixture uses native SharedPreferences for the record list, six professions, targets and deleted profession state. It includes individually deleted rows, earlier leap-day dates, non-ASCII reflection text, varied durations, photographs, PDFs, HTTPS links and missing references. The full projection is compared with the legacy data before and after rehearsal handoff. The review fixture adds duplicate IDs, an impossible date, fractional duration, a truncated JSON entry modelling a partially written legacy record, and unsupported historical evidence metadata. Its acceptance test checks the recovery snapshot against every original raw row and restores a separate copy of the evidence.

The arm64 Android 7.0 emulator ran a Flutter 3.41.6 debug build on an Apple Silicon Mac. Migration time runs from coordinator entry through the rehearsal authority receipt. Additional disk use and process RSS are sampled during migration. A 50 ms Dart timer records the largest gap during migration as a responsiveness proxy. Reported first frame is the rehearsal shell. Search time includes loading the SQLite profession projection. These metrics cover debug emulator behaviour.

| API 24 measurement | 1,200 records | 3,600 records |
| --- | ---: | ---: |
| Managed originals | 48 | 144 |
| Legacy source including evidence | 30,185,854 bytes | 90,562,642 bytes |
| Migration and authority receipt | 32.406 s | 94.317 s |
| Recovery copy ready | 13.682 s | 38.939 s |
| Peak additional workspace | 33,238,732 bytes | 99,289,755 bytes |
| SQLite database | 2,887,680 bytes | 8,413,184 bytes |
| Baseline / sampled peak process RSS | 397 / 397 MiB | 391 / 445 MiB |
| Largest gap in the 50 ms timer | 416 ms | 611 ms |
| SQLite profession load and search | 241 ms | 667 ms |
| CSV generation | 32 ms | 31 ms |
| Text PDF generation, up to 20 records | 333 ms | 182 ms |

The rehearsal shell's first frame took 1.287 s. Both datasets achieved rehearsal authority and all projected rows matched exactly. Evidence fingerprints were verified against the frozen source. The 3,600-record process took over 90 seconds in this environment, and the timer gaps show visible responsiveness risk. Measure and agree launch, interruption, memory and progress-feedback budgets on slower physical devices with release binaries before enabling cutover.

The review run found 65 missing references across 1,205 raw rows. It also recorded one duplicate legacy ID, one invalid activity date, one fractional duration, one invalid JSON row, one retained unknown field and one unsupported provider reference. After 2.254 s it returned `reviewRequired`, left the authority fence and receipt absent, and restored an independent copy containing all 1,205 exact raw rows, including all 1,200 valid rows, and the original evidence bytes. This shows that blocked inputs are recoverable. A production resolution workflow still needs qualification.

## Late-handoff interruption on API 24

Each test started a fresh workspace, stopped the actual app process at a flushed checkpoint using `adb shell am force-stop`, confirmed the old PID had exited, and restarted into native SQLite. All cases retained exactly one import and passed native `integrity_check` and `foreign_key_check`. A test-harness retry initially attempted to freeze the already sealed write gate. The final checks use a fresh retry coordinator, which matches the cold-start lifecycle.

| Termination boundary | Startup authority and result |
| --- | --- |
| After staged SQLite commit, before verification | Legacy / `interruptedStaging`. Retry verified and activated once, with four exact original rows. |
| After verification, before publishing the fence | Legacy / `verifiedStaging`. Retry activated once, with four exact original rows. |
| Fence exclusively created, before its contents were written | Recovery / `invalidFence`. Both writers stayed closed. The four staged rows and independently verified source survived. |
| Fence written, before receipt transaction | Recovery / `interruptedHandoff`. The same four staged rows and source survived. |
| Receipt inserted, before its SQLite transaction committed | Recovery / `interruptedHandoff`. The incomplete receipt rolled back. The staged rows and source survived. |
| Immediately after receipt commit | Recording / `activated`. Reopened four original rows with the same receipt. |
| After resolving SQLite authority, before the first post-activation recording write | Recording / `activated`. Reopened with one import and four records. |
| During a subsequent SQLite transaction | Recording / `activated`. A fifth committed record survived. Its uncommitted deletion and a second write in the same transaction both rolled back. |

These results establish process-termination integrity on API 24. Three boundaries intentionally require recovery and preserve the staged database and legacy copy. They still need a validated user-facing or support-assisted procedure to regain access. A process stop and relaunch gives no evidence about sudden device power loss.

## Integrated recording features

The API 24 native feature probe saved a free Standard record without consuming template allowance. It checked that custom layout creation required a grant, then configured, reordered and retired a field using the simulated original-customer grant. The earlier record retained its historical field value. Profession templates across two versions and multiple tiles shared the five-record allowance. A failed write and a simultaneous sixth attempt left the allowance and the record store consistent. Backup and additive restore preserved evidence and historical report semantics without granting ownership or replenishing usage. Pending purchase left the cap in effect, and simulated verified ownership unlocked the correct template versions.

The migration and feature probes together exercised the standard CSV and PDF exporters, historical scheme PDF generation and evidence rendering. The native Android renderer embedded a photograph and both pages of the original PDF in English, German, French and Brazilian Portuguese. The evidence run used the existing fallback fonts without network acquisition and did not qualify arbitrary Unicode rendering. Commercial checks used the simulated ledger and do not qualify Play Billing or StoreKit.

All **264 Flutter regression tests** passed. Static analysis reported **13 pre-existing findings** and no new findings. The tracked changes add the rehearsal entry paths and observation points plus this report. Production SQLite activation, entitlements and published configurations were unchanged.

## Release decision

**Keep production activation disabled.** Before authorising a controlled rollout, close the following gates.

1. Run in-place migration, native SQLite write/reopen and interruption validation on exact iOS 15.6.
2. Verify a Play-delivered in-place upgrade with the app-signing certificate or lineage used by the existing app.
3. Validate an assisted recovery procedure for the interrupted-fence and receipt states and for sources that need explicit review. Preserve both stores until recovery establishes a single verified authority.
4. Measure a release build on representative slower physical hardware. Set and test acceptable progress feedback, time, memory and available-space behaviour for large evidence collections.

## Running the native validation

Use a disposable application ID and an explicit emulator or device serial. The alternate entry point is `test/cpd_migration/native_migration_rehearsal.dart` with `--dart-define=CPD_PHASE3_MODE=release-validation`. It refuses release builds. Pass an app-private command as a one-line file named `files/release-command` in the Android package container.

- Use `scale` for the two clean datasets and mixed-source verification. Retain the `CPD_PHASE3_SCALE` and `CPD_RELEASE_LARGE_REVIEW` events.
- Use `arm <checkpoint>` in a fresh attempt and wait for `CPD_RELEASE_KILL_READY` from that process. Force-stop the package, confirm its PID is gone and restart with `resume <checkpoint>`. Compare the `CPD_RELEASE_RESTART_PASS` results. Commands and logs are limited to the disposable package.
- Use `integration` for the recording, template, evaluation, backup and native export checks. It uses separate SQLite workspaces and simulated entitlements.

The coordinator gained rehearsal-only observation points at exclusive fence creation, an uncommitted receipt and a committed receipt. The hooks are outside the persisted journal format. The ordinary app and release signing configuration were left intact.
