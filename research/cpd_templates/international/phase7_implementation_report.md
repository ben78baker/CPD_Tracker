# Phase 7 implementation and rehearsal

**21 November 2026 · Internal rehearsal.** The NMC pilot now uses a versioned template bundle, shared profession cards, independent reporting periods and a shared activity PDF. The published app still uses the existing production storage and exports. The rehearsal starts from a separate entry point and uses its own synthetic SQLite database.

## Product decisions

- Standard CPD retains the free recording path, the existing card and target behaviour, and current PDF, evidence PDF, CSV and ZIP exports.
- One template purchase covers independent placements of that template and subsequent updates. Each placement owns its layout, period history and report settings. Users may arrange supplied optional fields and choose report inclusion within the existing entitlement scope. App-wide Custom Fields continues to unlock changing or adding field definitions. The approved £3.99 and £12.99 initial UK proposals remain one-time prices. Future store UIs take their prices from the stores.
- The owner will identify original paid-app customers manually and use an approved voucher, promotion or equivalent to grant permanent app-wide Custom Fields. The existing verified grant boundary is retained. Automated historical verification is deferred. Future purchase verification, transaction handling, restoration and refunds still belong to the CPD app layer.
- The approval gate for migrating an existing installation is a complete independent backup verified against the quiescent source. Pending or unresolved data stays recoverable. Creating a new SQLite store requires authorised activation and reliable evidence that the installation has no legacy footprint.

## Implemented architecture

| Component | Behaviour |
|---|---|
| [Template bundle](../../../lib/cpd_creation/template_bundle.dart) and [NMC configuration](../../../lib/cpd_creation/nursing_bundle.dart) | A typed CPD envelope embeds the deterministic recording-engine recipe. It includes stable template and product identity, versions and compatibility, profession and scheme, translations, reviewed sources, rule bindings, named metrics, cycle options, tile content, report fields, and synthetic records and evidence. The decoder rejects unknown compatibility, calculators or report formats, misbound fields or choice IDs, bad thresholds, inconsistent durations, missing protected report inputs and invalid sample evidence references. It uses the central 20-active-field limit. |
| [Scheme progress](../../../lib/cpd_creation/scheme_progress.dart) and [period store](../../../lib/cpd_creation/scheme_period_store.dart) | The CPD layer stores immutable calendar windows and a selected-period pointer per profession. Each window pins template identity, version and rule revision. Progress resolves the original adoption’s field-instance IDs against each record’s historical layout and derives totals directly from its values. The selected period is also used by the specialised report. |
| [Shared profession card](../../../lib/widgets/profession_card.dart) and [scheme progress area](../../../lib/cpd_creation/scheme_progress_panel.dart) | The existing card supplies the branded header, common menu, colour and action layout. The scheme fills the progress area with its metric bars, period, deadline and review count. Standard CPD uses its existing progress area. The isolated test route uses synthetic record editing and evidence substitutes. |
| [Document renderer](../../../lib/recording_reports/activity_document.dart) and [CPD presentation](../../../lib/cpd_creation/scheme_report.dart) | The neutral renderer handles printable typography, summaries, full-width titles and fields, pagination, and a reference appendix. The CPD layer formats dates, durations, statuses, scheme information and evidence. It resolves originals without writing to them. Web evidence links are clickable in the appendix. Managed files remain available through the existing evidence export routes. |
| [Rehearsal entry point](../../../test/recording_engine/phase7_rehearsal_app.dart) | Reuses the Phase 6 creation flow and generic form preview. The preview reads synthetic records and invokes the same report renderer without a repository or grant mutation interface. Actual rehearsal reports recheck ownership against the relevant adoption. |

### Calendar and regulatory interpretation

NMC requires 35 hours relevant to scope of practice per personal three-year registration period, with at least 20 hours involving participation. The user supplies the application deadline from MyNMC. The template helps prepare an independent activity log. Other aspects of revalidation, including reflective accounts, confirmation and official submission, remain separate. Primary sources checked 21 November 2026. [NMC CPD requirements](https://www.nmc.org.uk/revalidation/requirements/cpd/) · [Revalidation date](https://www.nmc.org.uk/revalidation/online-application/revalidation-date/) · [Existing NMC research](../uk/nmc.md)

A saved period can be a custom date range, a fixed cycle from an entered date or a rolling window frozen as of an entered date. Stored bounds are start-inclusive and end-exclusive. The UI displays inclusive days and the date arithmetic uses calendar months and dates, with leap-day anniversaries clamped to the last day of the month. Period history has no automatic rebasing.

The pilot distinguishes the valid duration recorded in the period, the portion attached to complete records and the quantity eligible under the configured in-app rules. A dated record with missing evidence can add to recorded time while leaving eligible totals unchanged. Missing dates, impossible participatory amounts, changed choice meanings and activities spanning a saved boundary are flagged. The pilot neither guesses dates nor apportions hours across a boundary. It uses the user’s recorded scope and participation information. Evidence availability confirms a managed original can be resolved or an HTTP(S) reference was recorded. It does not verify the regulator’s acceptance of the evidence.

### Template updates and historical integrity

Phase 9 evaluation and purchase access are keyed to the template identity. Publishing a new version does not reset the five-record allowance or alter historical rule bindings. Exhaustion affects new template records. Existing records, evidence, report settings and pinned reports remain available. [Evaluation and authority rules](phase9_template_evaluation.md)

The bundle codec is stable for the current reader. The same store product identifies subsequent template revisions. A comparison rejects unrelated products and flags changed thresholds, role bindings and controlled meanings. Regulatory changes require advancing the rule revision. The existing generic template comparison remains the layout comparison mechanism. It can compare the supplied baseline, local edits and the new recipe. Phase 7 introduces no automatic adoption, layout rewrite or application of new rules to old periods.

Keep the prior bundle and supported calculator available for historical periods. Rendering uses the field meanings stored for each record. Version pins preserve interpretation after a template update. Later edits to a record can still change a regenerated report. If users need evidence of exactly what was submitted, retain the exported artifact separately. A full selective adoption UI, the signed distribution and catalogue retirement policy, and backups that restore old bundle versions are future deliverables.

## Verification

| Check | Result |
|---|---|
| Full Flutter suite | 221 tests passed, including 55 new checks. The card tests exercised all 48 locale and colour combinations at 320 logical pixels and 1.85× text scale. Coverage also includes malformed bundle data, deterministic encoding, calendar boundaries, category-specific eligibility, changed field meanings and report pagination. |
| Static analysis | Targeted analysis passed with zero findings. Full-project analysis retained the same 16 findings in older code, a feasibility probe and an existing local marketing script. |
| Native SQLite | Passed on an iPhone 16 Pro simulator with iOS 18.5 and a Pixel 6 emulator with Android 14/API 34. The fixture exercised two copies of the NMC template, distinct field identities and selected periods, close and reopen, immutable saved history, managed originals, a linked reference, missing evidence and PDF generation. The nursing copy produced 360 recorded and 240 eligible total minutes, with 255 recorded and 165 eligible participatory minutes. |
| Legacy parity and recovery | Five native parity scenarios passed per platform, including existing entries, professions, targets, search, PDF/CSV/ZIP exports, malformed IDs, low-storage rollback, recoverable snapshots and schema upgrade. The native Phase 3B authority suite and Phase 6 creation, entitlement and draft-recovery suite also passed on both platforms. These were isolated debug targets. |
| Visual review | Inspected native shared cards on both platforms and period selection and PDF preview on Android. Rendered the two-page sample and five-page pagination fixture with Poppler. Text extraction verified all 170 numbered observations and the final sentinel, the period labels and totals, the missing-evidence status and the clickable evidence URI. |
| Release evidence | Exact iOS 15.6 and Android API 24 runtimes were unavailable. Physical-device assistive technology, signed upgrades, public share/print for specialised reports, localised official terminology and offline Hindi PDF font and shaping quality remain open. The internal report uses a downloadable Hindi font and surfaces a report error if it cannot be loaded. |

### Rehearsal evidence

| Screenshot | What it illustrates |
|---|---|
| [iOS · Shared cards](phase7_pilot/ios-profession-cards.png) | Standard and NMC cards use the same header, controls and accent. |
| [Android · Targets and deadline](phase7_pilot/android-profession-cards.png) | Independent total and participatory targets with a review count. |
| [Android · Saved periods](phase7_pilot/android-periods.png) | The selected three-year window and an older retained window. |
| [Android · PDF preview](phase7_pilot/android-scheme-report.png) | Scheme summary and an explicitly unavailable evidence item. |

- [NMC synthetic example PDF](phase7_pilot/nmc-example.pdf) · three completed activities, 4 hours total, 2 hours 45 minutes participatory and a sample evidence reference.
- [NMC pagination and evidence PDF](phase7_pilot/nmc-pagination.pdf) · five pages with long text, deliberate incomplete evidence and an appendix link.
- [Inspectable NMC bundle](phase7_pilot/nmc-bundle.json) · human-readable output of the runtime recipe envelope. Regenerate it with the PDFs after an approved pilot change.

Reproduce the synthetic host test and documents by setting a new scratch directory for the artifacts. Run the native entry points in a separate debug application identity with the required plugins.

```sh
CPD_PHASE7_ARTIFACTS=/tmp/cpd-phase7-artifacts flutter test --no-pub test/recording_engine/phase7_scheme_test.dart
flutter run --no-pub -d <test-device> --dart-define=PHASE7_SAMPLES=true -t test/recording_engine/phase7_rehearsal_app.dart
flutter run --no-pub -d <test-device> -t test/recording_engine/native_phase7_scheme.dart
```

## Backup, cutover and release readiness

**Production cutover remains blocked.** Phase 2 established that the imported inventory reproduces legacy behaviour and that an independent recovery snapshot can be read. The Phase 3B coordinator gates legacy writes, checks capacity, copies the legacy preference inventory and app-owned files, verifies the copy against its source before opening the staging database and verifies again before publishing readiness. The authority resolver keeps unresolved handoff states in recovery and prevents an earlier legacy source from replacing authoritative SQLite data. Keep the minimum 30-day recovery period beginning at verified activation and hold retention whenever integrity is uncertain. Retain original files and legacy storage until a separately approved cleanup policy is verified. [Phase 2 compatibility](phase2_compatibility_validation.md) · [Phase 3B authority and recovery](phase3b_migration_readiness.md)

| Priority | Next gate |
|---|---|
| Existing-install protection | Freeze all production writers before inventory. Enumerate legacy state and app-owned evidence under the signed application identities. Confirm that the inventory captures everything needed to restore records, preferences, targets and attachment references. An inaccessible original, unreadable recovery copy or inconclusive inspection holds migration for review. |
| New-install detection | After explicit activation approval, recognise a new install only when readable storage has no records, deleted/recoverable history, prior-use preferences, owned evidence or handoff artifacts. Malformed state or contradictory artifacts lead to retry or recovery. Direct SQLite initialisation needs its own durable startup marker and restart tests. |
| Acknowledged writes | Prove detection and recovery of missing or older SQLite files with otherwise valid identifiers. Compare recovered data against an independent record of acknowledged edits, deletes and evidence writes. A verified pre-migration snapshot covers the legacy source only. |
| Portable backup and restore | Provide a user-accessible format covering records, layouts, pinned bundled rules, settings and managed originals. Rehearse verification and staged restore outside the live store, including lost device, interrupted copy, changed platform and future schema. Complete this before a public release. |
| Commercial delivery | Approve the actual owner-managed offer or redemption process on each store and its restoration behaviour. Verify ordinary purchases, pending transactions, restoration, refunds and previous ownership. Confirm availability of each approach before any promise to original customers. |
| Template and report quality | Have practising users review the NMC form, terminology, date and evidence presentation, and rule interpretation. Verify older-rule restoration and explicit update adoption. Qualify both public report sharing and preservation of evidence, including a specialised appendix or companion bundle. Check type scaling and screen-reader behaviour on physical devices. |
| Signed minimum-OS release | Exercise signed upgrades, verified-backup gating, migration interruption and portable restore using iOS 15.6 and Android API 24. Prove existing exports and recovery under each production identity before activation approval. |

**Recommendation.** Keep recording-engine development on the feature branch and prioritise portable backup/restore plus proof that recovery covers acknowledged SQLite writes. Review the pilot with practitioners and approve the store grant process separately. Continue rehearsing with synthetic data while those gates remain open.
