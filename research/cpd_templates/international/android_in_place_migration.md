# OPPO Android in-place migration rehearsal

**23 November 2026.** Physical OPPO CPH2371 running Android 13 (API 33), connected to ADB over USB. All device commands selected the OPPO explicitly. The Android package was `com.ingeneralapps.cpdtracker`. Find Catalogue and the connected iPhone XR were outside the test.

## Source and update compatibility

- Built source commit `425e6bb` as 1.4.1 (15) in an isolated directory. The legacy test entry point uses that commit's `EntryRepository`, `SettingsStore` and attachment writer to populate the app. It then launches the legacy app normally. CPD was absent before install.
- Built the current feature branch as debuggable 1.4.1 (16). Before installing either APK, `apksigner` verified that both used the same development certificate. Both APKs used the existing package ID, supported arm64 and advertised a minimum API level of 24. The production AAB and production keys were outside the test. [Android update requirements](https://developer.android.com/google/play/app-updates)
- Upgraded on the OPPO with `adb -s <oppo-serial> install -r`. The app retained its UID, first-install time and data directory. A fresh copy of preferences and evidence after the update matched the verified legacy baseline byte for byte, before the migrated app launched. [ADB install options](https://developer.android.com/tools/adb)
- The test entry point requires a matching build token and an independent source identity in an app-private file. The rehearsal launches the coordinator under rehearsal authority. The ordinary app entry point, production activation, signing configuration and published artefacts were unchanged.

## Baseline and first live migration

Two independent transfers from the stopped legacy app yielded matching files. SharedPreferences XML contained 12 records, including two individually deleted records, across three active professions and one deleted profession. The 12 records included non-ASCII reflection text and different dates and durations. The XML also contained four targets and the selected locale, date format, week start, accent, onboarding and QR preferences and test profile values. Three available file originals totalled 3,200 bytes: a photograph, two-page PDF and text file. The data included a web evidence link and a PDF referred to by two records. There was no recording database before the update.

The first instrumented launch refused to migrate on a source identity mismatch. The Mac verifier had included unset preference keys. After correcting it to match the app's omission of unset keys, the sealed source matched. I stopped the actual in-place migration with ADB at its persisted staging checkpoint and confirmed the process had exited. On relaunch the coordinator reported `interruptedStaging`, reused the verified snapshot and completed handoff. SQLite then exposed all 12 original records, both deleted records, all four professions, four targets and intact original evidence. The app reported zero migration review issues.

| Measurement | OPPO | iPhone XR |
| --- | --- | --- |
| OS and build | Android 13 / API 33, debuggable APK | iOS 18.7.10, development-signed Profile build |
| Legacy records / individually deleted | 12 / 2 | 3 / 1 |
| Active / deleted professions | 3 / 1 | 2 / 0 |
| Available evidence originals | 3 (3,200 bytes) | 4 (2,113,952 bytes) |
| Process interruption | Actual first migration stopped at staging, then resumed | Separate staging attempt stopped and resumed after the initial migration passed |
| Time in coordinator on successful attempt | 1,583 ms after staging restart | 1,176 ms on first attempt |
| Database after migration | 135,168 bytes, schema 4 | 102,400 bytes, schema 4 |
| Integrity / foreign-key violations | `ok` / 0 | `ok` / 0 |
| Combined write and export probe | 6,172 ms | 4,016 ms |

The builds, datasets and starting conditions differ, so the elapsed figures describe the two rehearsals individually. [iPhone XR rehearsal](xr_in_place_migration.md)

## SQLite workflow and recovery

The shared on-device probe created and edited a record with new photo and PDF evidence, tested search and the CPD time total, updated a target, and deleted and restored the test record and its profession. The legacy writer rejected writes after handoff. Each of two forced launches loaded the same SQLite record ID, edited fields, target and evidence hashes. The rendered app screens navigated through a profession, global search, edit and deleted-record recovery against the SQLite adapter. Missing and corrupt databases in separate test directories both selected recovery authority.

Android rendered a one-page summary PDF and a four-page evidence PDF. Link annotation, missing-evidence labelling, the CSV and the four-file ZIP passed. ZIP CRCs passed and original file bytes matched. The separate text-only evidence fixture triggered the conditional companion ZIP and round-tripped its bytes.

## Android native file workflows

ADB operated the app's actual Add Entry screen and launched the system document picker through **Choose file**. The Downloads provider returned the test PDF. CPD's managed copy matched the source byte for byte. Tapping the attachment opened Android's resolver and the selected PDF viewer displayed both pages. The test opened the file once without setting a default.

The record was saved through the CPD form with its picked attachment. The attachment's share action opened the Android share sheet, which displayed the correct file. I dismissed the sheet without selecting a recipient, removed the temporary Downloads fixture and confirmed the saved record and its attachment were still visible after forcing the app to stop and relaunching it. The device exercised the local Downloads provider and native viewer. External cloud providers and delivery to a share recipient were outside the test.

I then soft-deleted and restored that same synthetic record via the app's confirmation dialogs. Both original deleted records remained in Deleted Records. An independent read of the stopped device's database on the Mac confirmed the restored record retained its evidence link, the database had 14 records and five professions including the two synthetic additions and one deleted profession, and the original two deleted records remained deleted. The final database was 143,360 bytes with one import, `integrity_check = ok` and zero foreign-key violations. The original SharedPreferences XML still matched byte for byte. The three original evidence hashes agreed across the Mac baseline, the live Documents folder and the recovery snapshot.

## Repeating the rehearsal

1. Build `test/cpd_migration/android_legacy_seed.dart` as an alternate entry point against the isolated legacy source with `CPD_ANDROID_SEED_LEGACY=true`. The seeder is for an empty store and writes through the legacy application APIs.
2. Build the Android rehearsal entry point in an isolated copy of the feature branch with a unique `CPD_ANDROID_REHEARSAL_TOKEN`. Verify both signed APKs with `apksigner` and inspect the package and version codes with `aapt` before installing.
3. After the legacy app emits `CPD_ANDROID_LEGACY_READY`, force-stop only CPD. Export its `shared_prefs/FlutterSharedPreferences.xml` and `app_flutter/attachments` using device-specific ADB `run-as`. Decode the Flutter JSON list marker, retain present inventory keys and omit unset ones. Calculate the migration source ID using the same sorted JSON encoding and UUIDv5 namespace as `SyntheticCpdMigration.sourceIdentity`. Compare attachment SHA-256 hashes against a second transfer.
4. Use `install -r` on the same package. Compare the preferences and evidence before launch. Place the build token and source ID on separate lines in the package-private `files/android-cpd-rehearsal.seal`. A one-shot `command` file under `files/android-in-place-migration` selects `pause-in-place`, `workflows`, `restart`, `recovery` or `ui`. Without a command, a valid rehearsal opens its verified store.
5. Collect `events.jsonl` and ADB activity diagnostics. Stop CPD before taking a copy of the database. Recheck the legacy preferences and attachment fingerprints against the baseline and compare the database, authority fence and import receipt. Keep APKs, tokens and per-device inventories in private local storage.

## Structured evidence

Selected device events in UTC. The log excludes the authorisation token and source contents.

```text
09:26:38  source_mismatch      source check blocked the launch before staging
09:27:23  interruption_ready  live staging checkpoint, process force-stopped
09:27:25  startup             legacy / interruptedStaging
09:27:27  migration_result    rehearsalActivated / 1583 ms / no failure
09:27:27  initial_parity      records=12 deleted=2 activeProfessions=3 deletedProfessions=1
09:27:56  exports_pass        PDF pages=1/4, CSV and ZIP validated
09:28:00  workflow_store_pass first forced relaunch
09:28:03  workflow_store_pass second forced relaunch
09:28:07  recovery_copy_pass  missingDestination / invalidDatabase
09:28:13  ui_routes_pass      migrated deleted records visible
09:34:32  startup             verified SQLite authority after native picker, save, share and force-stop
```

## Verification and release gates

All 264 Flutter tests passed. Static analysis reported 13 existing findings and no new findings. The only rehearsal defect found was the initial Mac-side source seal calculation. The fail-closed check worked as intended and the corrected verifier matched the untouched source. No production app change was required.

This test establishes an in-place, debug-signed migration on a physical API 33 device alongside the completed XR rehearsal. Before authorising cutover, verify an upgrade from a Play-signed installed app, repeat on API 24 and iOS 15.6, and test late interruption around handoff with a large, less tidy dataset. Verify native iOS picker and share workflows separately. The OPPO was left on the migrated development build. Neither production SQLite activation nor store configurations were enabled or changed.
