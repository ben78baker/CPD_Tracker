# iPhone XR in-place migration rehearsal

**23 November 2026.** Authorised disposable-device test on `feature/recording-engine`. The production entry point and its SQLite activation flag remained unchanged.

## Device and baseline

| Check | Result |
| --- | --- |
| Device and tools | Physical iPhone XR, iOS 18.7.10 (22H374), Xcode 27.2 (27B52), Flutter 3.41.6 and Dart 3.11.4. CoreDevice connected via USB. |
| App identity | In-place replacement of developer-signed 1.4.1 (15) with profile build 1.4.1 (16), using the existing application ID and matching Apple Development provisioning. No uninstall or reset. Code signature and provisioning were checked before installation. |
| Container check | iOS changed the data-container directory path during the update. Independent file transfers before the first launch proved the preference plist and all four evidence originals survived the update byte for byte. |
| Baseline copy | Two independent preference exports matched byte for byte. The plist parsed successfully and all four attachment references resolved to readable originals. Originals comprised two PDFs, one JPEG and one PNG totalling 2,113,952 bytes. |
| Recording inventory | Two active professions, zero deleted professions, three total records including one deleted record, two CPD target entries and four available attachment originals referenced by two records. |
| Preferences | App accent, week start, onboarding and four profile fields were present. Report locale, app locale, date format and QR hint were absent and remained absent. |

The baseline contains private files. The repository contains aggregate counts and event excerpts. The Mac copies remained in a restricted temporary directory.

## First in-place migration

The alternate entry point in `test/cpd_migration/xr_in_place_rehearsal.dart` checks the frozen recording-source identity against the independently exported baseline. It refuses release builds and calls the existing coordinator with rehearsal scope. The coordinator freezes legacy writes, checks space, creates and verifies an independent recovery snapshot, stages SQLite, checks the recording projection and evidence fingerprints, writes the handoff fence, and records the activation receipt. The app resolves that receipt before opening the SQLite CPD adapter. It then renders the regular CPD Home and routes with that adapter.

| Device measurement | Result |
| --- | --- |
| Estimated required space at preflight | 36,756,892 bytes |
| Available space at preflight | 10,756,640,768 bytes |
| Coordinator elapsed time | 1,176 ms |
| First app frame after verified handoff | 1,449 ms after probe start |
| SQLite size and schema after migration | 102,400 bytes, schema 4 |
| SQLite integrity and foreign keys | `integrity_check = ok`, zero violations |
| Source and SQLite parity | 3 records, 1 deleted record, 2 active professions, 0 deleted professions. Record projections, target map, profession ordering, preferences and evidence fingerprints matched. |
| Recorded migration issues | Zero issues. Successful rehearsal receipt and recording authority. |

The timer begins inside Dart and excludes native process launch. The `home_first_frame` event measures the first frame after handing control to the normal app shell. Timings are single observations on this dataset.

## Physical interruption and missing-store recovery

The initial in-place attempt completed before an interruption could be injected because launch environment variables were unavailable inside the profile Dart process. After the migrated store had been verified, a separate workspace used the same XR legacy data and coordinator to exercise interruption. One-shot commands were delivered through Xcode CoreDevice into the private rehearsal directory. At the flushed staging checkpoint Xcode terminated the process with SIGKILL. The relaunch identified `interruptedStaging`, retained legacy authority for that attempt and retried to `rehearsalActivated`. The existing migrated store opened normally afterward.

A separate fault probe copied the activation fence and exercised missing and invalid destinations. It observed `missingDestination` and `invalidDatabase`, both under recovery authority. These fault checks used scratch directories and left the migrated database intact.

## SQLite authority and workflow results

Build 19 completed the final checks. Its write probe created a synthetic profession and record with a PNG, PDF and link through the native app and production CPD SQLite adapter, edited the description and duration, and set a monthly target. Search found the edited record and the range total was 90 minutes. The probe soft-deleted and restored the record and its profession. The original three records kept their exact CPD projections, including the deleted record. Both new file originals retained their fingerprints.

The actual app screens rendered on the XR. The screen probe invoked the existing control callbacks to navigate from Home to a profession, search across professions, open the edited SQLite record with its evidence, and reach the deleted-record recovery control. Record saves and restores were exercised through the adapter rather than by entering text or tapping buttons manually on the XR.

Two forced relaunches loaded the same record ID, edited duration, target and evidence. The legacy record writer rejected writes after handoff and no restart attempted a second import. In an independent Mac read of the closed device database, SQLite reported four records, three collections, seven evidence associations including the web link, a single source import, `integrity_check = ok` and zero foreign-key violations. The final live preference plist still matched its pre-install bytes. All four original evidence fingerprints agreed across the Mac baseline, live Documents and the separate recovery snapshot. The XR was reopened on the verified SQLite build after these checks.

| Export check | Result |
| --- | --- |
| Text-only PDF and PDF with evidence | Native iOS rasterisation opened both. The text-only PDF had one page and the evidence PDF had four. |
| Evidence details | Photo and PDF inputs, a link annotation and a missing-file marker passed. |
| CSV | 342 bytes. The SQLite record and edited description were present. |
| Full ZIP | 957,148 bytes and four files. CRC checks passed and both evidence files matched their stored originals. |
| Conditional ZIP | No companion ZIP for evidence the report could render. A separate available text file produced a companion ZIP that contained the original bytes. |
| Exports elapsed | About 4.0 seconds for the combined workflow and export probe, including native PDF rasterisation. |

The structured event excerpts below identify the first in-place run, the separate interrupted attempt, the final workflow and two forced relaunches. Timestamps are UTC and contain no record contents, source identifiers or attachment names.

```text
09:01:27  startup               legacy / legacyInstallation
09:01:28  migration_result      rehearsalActivated / 1176 ms / no failure
09:01:28  authority             recording / activated
09:01:29  initial_parity        records=3 deleted=1 activeProfessions=2
09:04:06  interruption_ready    staging, process terminated via CoreDevice
09:04:07  interruption_startup  legacy / interruptedStaging
09:04:08  interruption_result   rehearsalActivated / recording
09:04:09  recovery_copy_pass    missingDestination / invalidDatabase
09:08:03  ui_routes_pass        deleted recovery control rendered
09:08:35  exports_pass          PDF pages=1/4, companion ZIP checks passed
09:08:37  workflow_store_pass   recording relaunch, 4 records / 2 new originals
09:08:38  workflow_store_pass   recording relaunch, 4 records / 2 new originals
09:09:16  home_first_frame      normal XR rehearsal launch, 55 ms after Dart start
```

## Implementation and deployment notes

- The write gate distinguishes legacy recording writes from settings writes and additive attachment copies. Both classes remain frozen during migration. Only the verified recording-authority path can reopen shared settings and evidence writes in the XR rehearsal. The legacy record writer remains sealed.
- The build used a disposable source checkout and the existing signing identity. The Profile target referenced a missing root-level xcconfig, so Flutter's embed script received no `FLUTTER_BUILD_DIR`. The build used a forwarding xcconfig in the disposable checkout. The tracked Xcode project and existing signed artefacts were left as they were.
- A first export probe used the same directory and timestamp-based filename for two report variants. The ZIP preparation replaced the PDF this probe meant to compare. Separating the probe output paths fixed the comparison. The application exporter remained unchanged.
- Xcode CoreDevice installed the builds, relayed device command status, killed the app at the flushed checkpoint and exported the structured log and final database. Profile builds did not surface Dart prints through the attached console. The flushed app-private log provided the authoritative timeline for verification.

## Repeatability, coverage and next gate

The full Flutter regression suite passed all 264 tests. Static analysis reported the same 13 existing findings, with no new findings. The instrumented binary advertised iOS 15.6 as its minimum. Execution was verified on iOS 18.7.10. Exact-minimum iOS, Android, the native share sheet, external document-provider interaction, installation from an App Store-signed build, and recovery after a crash later in live handoff still need separate coverage. This device contained a small, unambiguous source. The deleted-profession path used a synthetic record because the baseline had zero deleted professions.

The XR result qualifies a development-only in-place migration on the tested source and OS. Before seeking production cutover authorisation, run the same checks on older iOS and Android builds, a larger and less tidy source, and the late handoff boundaries. Exercise native export sharing and evidence selection end to end. The normal app entry point, production SQLite activation, entitlements, signing configuration and existing signed rehearsal artefacts were unchanged.
