# Phase 9 revision · five-record profession template evaluation

**22 November 2026.** The isolated rehearsal now offers up to five successfully created records per template identity with no expiry. Public evaluation and production SQLite require separate approval. The prior timed rehearsal is retained in Git at `1500439`. The signed migration rehearsal retains its existing scope and identity.

## Accounting and entitlements

The CPD host keeps one installation authority and one usage state per stable template ID. The first four chargeable identities are retained for deduplication. The fifth sets a permanent exhaustion marker. The counter is capped at five because recording beyond the threshold has no effect on eligibility. Layout versions, professions and reporting periods share the same template ID. Different template IDs have independent quotas. The generic engine stores records and supports transactional host metadata without making an entitlement decision.

Validation, record and evidence-link creation, and recording the usage receipt commit in one SQLite transaction. Failed saves roll all of them back. A cancelled form carries no receipt. Simultaneous saves compete for the last slot in the live database. Deleting or purging a record or profession does not delete its receipt. Existing record edits, evidence changes, layout operations, period changes and reports do not consume records. Purchase provides unlimited recording for current, future, restored and versioned placements of that template. A verified purchase remains usable if local evaluation history is unavailable. Purchased records can contribute to the first five remembered IDs so later loss of purchase verification cannot create a fresh evaluation of the same history. Original paid-app customers keep their app-wide Custom Fields grant, which remains separate from template ownership.

Only the isolated launcher supplies the evaluation authority. Its prior timed rehearsal can initialise the new ledger from surviving original records without using activation dates. This is an internal upgrade only. Records purged before the revision are absent from that older version's history and cannot be reconstructed. An existing rehearsal marked as provisioned stays closed to new free recordings if its authority is missing. A corrupt template usage value cannot grant free records. Data access and Standard CPD remain available.

## Backup and import

Profession backups continue to carry records, attachments, immutable definitions and choices, layouts, reporting periods and pinned rules. They contain neither purchases nor quota receipts. The whole-store portable CPD codec also excludes quota receipts. A source file cannot roll back the destination authority.

A verified restore adds original IDs of previously unseen template records to the destination's usage, capped at five. This includes soft-deleted records and follows each record's stored template identity. Standard records use no slots. Counting distinct imported records limits the ability to reset usage by moving a backup to a fresh installation. It also means a valid old archive can use up all five free slots on that installation while remaining fully readable, editable and exportable. The source file and all its records remain intact. Existing duplicate recognition remains in place. If a profession was purged, importing the same originals again or importing a re-export does not count those originals twice. Usage and restore publication commit in the same SQL transaction.

An archive cannot establish omitted, unexported or already purged history from another installation. A whole-device rollback could roll back an intact live database with its old usage snapshot. The production migration design must preserve quota authority separately across any full data-store replacement and qualify that recovery before public enablement. The isolated Phase 9 recording flow only supports additive profession restore. [Backup wire compatibility](backup_format_compatibility.md)

## Standard CPD inside the same tile

The rehearsal offers Standard CPD through a separate free tile. A same-tile option is viable only with an explicitly selected free layout that produces records with their own stored provenance and preserves the current template layout and earlier revisions. Reporting would need to decide whether standard records are excluded from scheme totals or included as clearly unclassified activity. Existing scheme aggregation can currently derive totals from canonical fields across the collection. Displaying fewer fields in the same template layout would leave required-field and reporting meaning ambiguous. Qualify search, export, historical edits, subsequent purchase, backup portability and combined totals before approving the additional creation path or a wire-model change. This phase does not activate that fallback.

## Cross-installation enforcement and store checks

| Option | Evidence and decision |
| --- | --- |
| Installation-local authority | Implemented for offline rehearsal. It resists tile deletion, refinements, additive imports and app restart. Reinstall, clearing all app data, replacement without restoring records or restoring an older device or database snapshot can lose usage. Protecting a local copy with Keychain or Keystore improves local integrity and cannot guarantee a per-user ledger across devices. Confirm any backup or synchronisation mechanism, including the supported OS floors, before making claims. [Apple Keychain protection](https://developer.apple.com/documentation/security/ksecattraccessibleafterfirstunlockthisdeviceonly) · [Android Auto Backup](https://developer.android.com/identity/data/autobackup) |
| Store-verified proof | Use platform-verified non-consumables for unlimited recording. Apple's signed app transaction ID can identify the same account for one app on supported versions. A separate verified service would still need to maintain the count. Qualify API availability on iOS 15.6. Google Play purchase tokens identify purchases, and the app-supplied obfuscated account ID does not expose a stable Google Play account for unpurchased access. [Apple AppTransaction ID](https://developer.apple.com/documentation/storekit/apptransaction/apptransactionid) · [Play Billing lifecycle](https://developer.android.com/google/play/billing/lifecycle/one-time) |
| Device-backed signals | DeviceCheck provides two bits per device. Google Play Device Recall beta provides three. They do not carry a catalogue of per-template counters or establish a user identity on replacement hardware. Do not use these signals as allowance authority. [Apple DeviceCheck](https://developer.apple.com/documentation/devicecheck) · [Play Device Recall](https://developer.android.com/google/play/integrity/device-recall) |
| Approved online authority | A verified identity with an atomic remote counter could enforce per-account usage. Fully offline concurrent use on multiple devices would need preallocated signed slots, an online final authorisation, or an explicit grace policy. This introduces availability, privacy, cost and account recovery trade-offs. No backend, app account or identifier collection is authorised here. |

Present the five-record allowance as free recording functionality and the one-time paid product as the unlimited unlock with store-localised pricing. Apple's guidance specifically describes a zero-price mechanism for time-based trials, which does not establish approval of this model. Google Play requires its billing system for eligible paid digital functionality. Verify the free/paid boundary and explanatory store metadata under an authorised review configuration. Funds are never taken for a free record. [App Review Guidelines §3.1.1](https://developer.apple.com/app-store/review/guidelines/) · [Play payments policy](https://support.google.com/googleplay/android-developer/answer/9858738)

## Physical-device and store checklist

- After separate authorisation, qualify iOS 15.6, Android API 24 and current physical hardware under approved identities. Keep this separate from the SQLite migration rehearsal and use synthetic CPD data.
- Verify a fleet of professions with one stable template, another template and an updated version. Exercise the first and fifth saves, a simultaneous sixth, termination before commit, offline restart, failed original publication, app reinstall, OS backup restore, app-data clearing and device replacement.
- Restore active and soft-deleted records, photos, PDFs and a historical reporting period. Check repeated imports, re-exported archives, local ledger loss and policy for trusted whole-device recovery. Confirm all history can be opened, edited and exported independently of the allowance.
- Verify paid checkout and restoration with true store accounts, using localized prices, account changes, offline and pending states, refunds, existing app-wide Custom Fields and verified original paid-app grants. Verify native file-provider and export handoffs and accessibility across the six locales.
- Approve local-vs-account enforcement, legitimate recovery policy, storefront disclosures and the updated Terms and Privacy Policy. Keep the public feature disabled pending qualified results and approval. [UI states](../../../docs/custom_fields_ui.md#15-five-record-template-evaluation)

## Verification

The synthetic native entry point is `test/recording_engine/native_phase9_evaluation.dart`. The launchable rehearsal is `test/recording_engine/phase9_evaluation_rehearsal_app.dart`. The Flutter coverage is `test/recording_engine/phase9_evaluation_test.dart`.

- The full Flutter suite passed 263 tests. Static analysis reported the same 13 existing findings and none in the changed files. Widget tests exercised allowance copy in six locales and eight colours, checkout and restore, isolated sample entry, and editing after the fifth record.
- Native synthetic tests passed on iOS 18.5 and Android API 24 and 34. They exercised contended fifth and sixth saves, a ledger write failure after record insertion, cancelled and invalid requests, changed versions, separate templates, database reopen, deletion, ownership and original paid-customer access. Failed restore rolled back both history and usage. Re-import and re-export counted original IDs once, and restored photo and PDF digests matched. A whole-store portable archive excluded the ledger.
- The revised UI launched on iOS 18.5. The existing Android API 24 timed rehearsal profile with no saved records displayed five free records after upgrade and after a separate process restart.
- Physical-device UI testing was pending at this checkpoint. iOS 15.6, true store transactions, and OS recovery of usage remain unverified. Updated Terms and Privacy Policy copy is held locally for private review.

## Isolated Android test application

Build the existing Phase 9 entry point in debug mode. Gradle assigns it package `com.ingeneralapps.cpdtracker.phase9test` and the launcher label **CPD Tracker Test**. It keeps the app icon and colour selector, starts with its own SQLite workspace and uses the simulated store. The normal Flutter entry point retains its existing Android identifier and label. The Phase 9 target is excluded from Android profile and release variants.

```sh
flutter build apk --debug --target test/recording_engine/phase9_evaluation_rehearsal_app.dart
```

Before installation, inspect the APK with `aapt dump badging` and confirm the `.phase9test` package. Select the intended device with `adb -s <serial>`. The original package and the test package use distinct private data directories. Use synthetic records and evidence in the test app. Keep production SQLite activation disabled.

### Physical OPPO smoke test

On 23 November 2026, the debug APK installed on the OPPO CPH2371 running Android 13 (API 33). The existing CPD package retained its version, code and data directories, and install and update timestamps. A separate inspection of the normal debug APK confirmed its original package, launcher label and API 24 minimum.

| Journey | Observed result |
| --- | --- |
| Welcome and Standard CPD | Selected Teal, continued to profession creation and saved a record with a synthetic PDF selected from Android Downloads. The managed original matched the fixture byte for byte. |
| Custom CPD and historical values | Used the simulated original-customer grant, added a text field and saved a record. Removing the field published a second layout and the original value remained visible under Historical fields. |
| Template preview and evaluation | Entered temporary input, selected a controlled option and saw the example PDF render. The new NMC profession started with five free records. The fifth save removed the add action. Simulated checkout enabled a sixth save. The isolated database contained no saved preview value. |
| Reports and sharing | Standard CSV contained the expected synthetic activity. A one-page text-only PDF and a two-page PDF with evidence parsed successfully. Both PDFs and the CSV opened the Android share sheet. The share sheets were dismissed before selecting a destination. |
| Profession backup and restore | Created a verified backup of the Standard profession, including its original PDF, and opened the share sheet. Selected a separate prior synthetic backup through Downloads, checked the unavailable-evidence warnings and restored it as a new tile with five records, including one deleted record. The source file retained its checksum. |
| Cold restart | Reopened the test app after a force-stop. The SQLite copy held four professions and 13 records, including six in the NMC evaluation tile. Integrity and foreign-key checks passed. |

The UI still labels saved-entry flows “New sample record” and “Example entry.” Returning from the field editor can reopen the phone keyboard over the creation buttons. Dismissing the keyboard allowed creation to finish. The run did not cover a share destination, password-protected backup entry, TalkBack or the full colour and locale matrix.

### iPhone XR preparation

Xcode detected the XR on iOS 18.7.10. The local wildcard profile includes the XR but has no matching valid local signing identity. For a later build, choose a separate debug-only bundle ID and display name and obtain a development profile covering the test bundle ID and XR, with a matching Apple Development identity in the keychain. Build the same Flutter entry point and verify the distinct container before installation. This Android smoke test did not change iOS signing or install anything on the XR.
