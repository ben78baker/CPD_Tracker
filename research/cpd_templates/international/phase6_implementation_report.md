# Phase 6 implementation report

**21 November 2026 · Internal rehearsal.** Phase 6 adds the shared CPD profession creation flow, a simulated store, persistent drafts, scoped template arrangement and a researched UK nursing and midwifery activity-log pilot. The normal app still starts with SharedPreferences and its existing recovery paths. The rehearsal uses a separately launched disposable app and a separate SQLite database. Production SQLite activation, purchases, signing and distribution remain disabled or unchanged as applicable.

## Onboarding and creation

The existing welcome component reuses its language, colour, optional profile and week-start controls with an isolated preferences adapter. Continue leads to the same three choices that Home’s Add Profession action opens.

- **Standard CPD** opens the shared naming and save path with the five canonical free fields. It uses no store call or entitlement. The rehearsal supports creating and editing synthetic entries and viewing their generic projection. Published entry, targets, search, recovery and exports stay on the existing path.
- **Custom CPD** explains app-wide access before opening configuration. Verified Custom Fields and qualifying original paid customer grants permit the complete available Field Library and the Phase 5 editor.
- **Profession Templates** opens a catalogue with one researched pilot. A user can browse and preview, then choose the recipe or leave without committing a profession. A verified owner may adopt multiple independent copies. A template-only owner sees arrangement controls; an owner with app-wide rights sees the full editor.

Both entry points share naming, confirmation, duplicate checks and draft recovery. A repeated save of the same request returns its original profession ID. A separate request with a case-insensitive match is refused, with a distinct message for deleted professions. Rehearsal startup honours saved completion and repairs the checkpoint if the first profession committed before completion was written. An unreadable startup state presents a retry path. [UI specification](../../../docs/custom_fields_ui.md#9-onboarding-and-shared-profession-creation) · [Recovery architecture](architecture_implications.md#10-shared-profession-creation-and-onboarding)

## Entitlement decision matrix

| Access | Creation | Field and layout controls | Reports |
|---|---|---|---|
| Free | Standard CPD | Original five-field layout | Existing standard reporting |
| Template only | Standard CPD and each owned recipe | Reorder, remove or reinstate optional supplied fields, restore defaults | Owned specialised report, optional report inclusion and reset |
| App-wide Custom Fields or verified legacy grant | Standard and independent Custom CPD | Create fields, full available Field Library, change allowed settings and validation, rearrange layout | Standard or custom report selections |
| Both | All three paths, including owned recipes | Full editor on an owned copy with protected CPD bindings | Owned specialised report with compatibility review after changes |

The CPD commit service checks the persisted grant and compares template-only field payloads with the exact adoption snapshot. A forged rename, new field, definition, choice, validation, format, unit, required-field removal or required-report exclusion is rejected independently of the UI. Restore presents missing supplied fields directly. The arrangement editor shares the same renderer, handles and accessible move commands as the full editor.

Form availability and report inclusion are independent. A report-only exclusion does not remove a field from entry. Removing a field from the current form keeps prior values and report selections available in their original revisions. Explicit reinstatement restores the same field identity and immutable definition for future records. Records created while it was absent keep their original field set. The generic engine carries versioning and restoration checks. CPD owns commercial access, protected canonical bindings and scheme rules.

## Drafts, offline and simulated purchase recovery

Name, field arrangement, field settings and report choices are saved as a local draft. Resume and Discard are explicit. A draft carries a base layout revision and is independent of collection and record values. A completed or discarded draft cannot be recreated by a late save. Publishing a draft checks access, name and compatibility again, then saves the configuration and creation receipt atomically. A conflicting base revision is rejected by the repository.

The simulator persists pending attempts and verified grants separately from drafts. Duplicate checkout requests reuse the pending attempt. Older events cannot cancel a newer attempt, and duplicate pending or cancelled messages do not erase a verified grant. Simulated restore and original-customer verification are labelled as such. A simulated outage prevents starting checkout, while prior verified grants and the free route remain available. No prices, real store requests or billing settings participate. A purchase can be recovered after the associated draft has been discarded, with no automatic profession created.

## Pilot selection and primary sources

**Selected:** UK Nursing and Midwifery Council revalidation CPD activity log for nurses, midwives and nursing associates within the applicable registration scope. The strong recording specification, meaningful distinction between total and participatory learning, Code mapping and evidence, and links from reflection to practice make it a strong commercial rehearsal candidate. An independent offline log with a readable summary complements the free official log. Willingness to pay remains unverified.

HCPC was a credible alternative because of broad practitioner coverage and its evidence requirement. Its audit output also requires an individual narrative and profile across the cycle. Dental CPD offers structured evidence and commercial potential, with role-sensitive hours, verifiability and annual declarations. The NMC pilot exercises choices, distinct totals and evidence in one well-documented activity-log scope, and leaves the rest of revalidation distinct. [International shortlist](../initial_catalogue.md) · [HCPC CPD standards](https://www.hcpc-uk.org/standards/standards-of-continuing-professional-development/) · [GDC recording and submission guidance](https://www.gdc-uk.org/education-cpd/cpd/cpd-scheme/recording-and-submitting-cpd)

| Source checked 21 November 2026 | Implication for the pilot |
|---|---|
| [NMC CPD requirements](https://www.nmc.org.uk/revalidation/requirements/cpd/) | Relevant activities total 35 hours, including at least 20 participatory hours, in the applicable three-year registration period. The activity log must identify method, relation to practice, dates, time, Code relevance and evidence. |
| [NMC revalidation guidance](https://www.nmc.org.uk/globalassets/sitedocuments/revalidation/how-to-revalidate-booklet.pdf) | Activity log supports discussion and confirmation. This pilot uses exact minute totals and separately identifies evidence. |
| [The NMC Code](https://www.nmc.org.uk/standards/code/) | Use stable IDs for four supplied themes and allow multiple relevant themes per entry. |
| [NMC written reflective accounts](https://www.nmc.org.uk/revalidation/requirements/written-reflective-accounts/) | Five reflective accounts use the prescribed form. The optional practice note in this pilot is a prompt for activity recording. Official accounts, confirmation and submission remain separate steps. |

The recipe reuses five protected CPD bindings plus method, conditional first day, participatory minutes, Code choices, optional practice reflection and standards references. The supplied form and specialised report are independent product work, with no NMC endorsement or approval claim. The completed examples deliberately contain synthetic evidence references and a small activity subtotal. [Research specification](../uk/nmc.md)

## Pilot previews, reporting and authoring

The catalogue shows profession, country, NMC scheme, version, review date and editing scope. It opens an interactive form with sample evidence, three completed records, a generated PDF and a disposable arrangement trial. Preview values, report resources and layout changes remain outside the rehearsal’s saved records and entitlement state. The viewer has no live sharing or native upload action.

Compatibility checks use the pinned recipe and report rules. Reorder has no reporting effect. Optional removals or exclusions change report content. Missing required bindings or altered semantics flag the report as incomplete, list affected fields and describe reinstating and including them. Combined ownership permits valid structural edits after an explicit warning. Canonical CPD changes that undermine standard semantics are rejected. Incomplete activities, including missing evidence and participatory minutes exceeding total minutes, are identified and excluded from the complete-activity subtotal. The PDF labels incomplete outputs and reports a subtotal, with the full revalidation period and decision kept separate. Saved report choices remain available by revision.

The review screen compares an installed version with a synthetic proposed recipe and displays additions and local differences. Reviewing it writes no upgrade, and the current layout and report settings are retained. Later selective adoption needs its own confirmation and tests.

The pilot uses declarative typed definitions, stable field IDs and the Phase 5 deterministic recipe codec. These artifacts support review and round-trip validation. Future bundles should add a shared catalogue manifest for localised metadata, source and review dates, versioned report bindings, immutable sample fixtures and an export digest. The scheme calculation remains a small CPD-side rule. The renderer, storage and layout concepts remain reusable for General Record Keeping.

- [Version 1 recipe](phase6_pilot/nursing_template_v1.json) and [synthetic completed records](phase6_pilot/nursing_examples.json).
- [Generated example PDF](phase6_pilot/nursing_activity_log.pdf).

## Original paid customers

| Platform and situation | Recommended path and limitations |
|---|---|
| **iOS 16 and later** | After approval, use the App Store-verified app transaction, check the app identity and compare the original build and acquisition date with a verified paid-release timeline. Apple documents a stable original version across upgrades and a date that survives reinstall. A refresh can obtain signed app-transaction information for the relevant App Store context. Verify the same-account device replacement and unavailable or changed-account cases on approved signed test devices. Sandbox uses fixed original values, so it cannot prove the paid-release cutoff. [Apple business-model transition](https://developer.apple.com/documentation/storekit/supporting-business-model-changes-by-using-the-app-transaction) · [Original acquisition date](https://developer.apple.com/documentation/storekit/apptransaction/originalpurchasedate) |
| **iOS 15.6** | The installed iOS SDK declares AppTransaction available from iOS 16. On 15.6, evaluate the Apple-documented original app receipt field and validated app receipt, with a refresh or support recovery when unavailable. Keep receipt validation separate from in-app purchase restoration. A missing or unverifiable receipt leaves the result unresolved. Test signed same-account upgrade, reinstall and replacement separately. [Apple receipt validation on device](https://developer.apple.com/documentation/appstorereceipts/validating-receipts-on-the-device) · [Original receipt version](https://developer.apple.com/library/archive/releasenotes/General/ValidateAppStoreReceipt/Chapters/ReceiptFields.html) |
| **Android upgrade** | Previously verified proof can be preserved across upgrade. The documented Play licensing response describes current authorisation; it does not expose the historical price or an original paid download date. Installation timestamps, current app version and Play installer identity are weak signals only. Use original customer order evidence and a trusted verification route for ambiguous installs. [Google Play licensing reference](https://developer.android.com/google/play/licensing/licensing-reference) |
| **Android reinstall, replacement and restore** | Do not treat Play Billing’s query for in-app products as a historical paid-app receipt. The customer can retrieve the original order in Play history. Offer a privacy-preserving support route to compare the app, paid date and order reference against authorised merchant records where available. A verified resolution needs a durable, recoverable grant design for later reinstalls. This is a release decision, alongside fair handling for customers with unavailable order evidence. [Google Play Billing integration](https://developer.android.com/google/play/billing/integrate) · [Google Play order history](https://support.google.com/googleplay/answer/2850369) |

Previously verified grants should remain usable offline with appropriate app and account provenance. Reconcile them when the store returns. During a first offline launch, expose free use and a way to retry verification or request reviewed support. Do not infer paid ownership from mere installation or ask a verified original paid customer to buy Custom Fields again. Both platforms require an approved paid release timeline and a policy for promotions, refunds, different accounts, absent evidence and recovery. Phase 6 uses simulation only and establishes no real purchase or verified migration status.

## Running the rehearsal

Use the dedicated disposable application ID and SDK/plugin setup from [Phase 3B](phase3b_migration_readiness.md#running-the-disposable-app). Copy the library and rehearsal targets into that app. The screen flow writes only its own app-private Phase 6 database.

```sh
flutter run -d DEVICE_ID -t test/recording_engine/phase6_rehearsal_app.dart
flutter run -d DEVICE_ID -t test/recording_engine/native_phase6_creation.dart
flutter test --dart-define=PHASE6_ARTIFACTS=research/cpd_templates/international/phase6_pilot test/recording_engine/phase6_policy_test.dart
```

## Rehearsal screenshots

| Journey | Android capture |
|---|---|
| Welcome and initial creation | [Preferences](phase6_screenshots/welcome.png) · [First profession choices](phase6_screenshots/choices.png) · [Standard CPD](phase6_screenshots/standard.png) |
| Resume and add another | [Resumed creation draft](phase6_screenshots/draft_resume.png) · [Home](phase6_screenshots/home.png) · [Shared creation from Home](phase6_screenshots/home_add.png) |
| Template evaluation | [Catalogue](phase6_screenshots/catalogue.png) · [Template information](phase6_screenshots/template_details.png) · [Interactive form](phase6_screenshots/preview_form.png) · [Completed activity](phase6_screenshots/completed_example.png) · [Example PDF](phase6_screenshots/preview_pdf.png) |
| Checkout and legacy access | [Pending simulated checkout](phase6_screenshots/purchase_pending.png) · [Cancelled simulation](phase6_screenshots/purchase_cancelled.png) · [Custom Fields access](phase6_screenshots/custom_access.png) |
| Arrangement and reports | [Template-only editor](phase6_screenshots/scoped_layout.png) · [Reinstate a supplied field](phase6_screenshots/reinstate.png) · [Independent report selection](phase6_screenshots/scoped_report_fields.png) · [App-wide editor](phase6_screenshots/custom_editor.png) · [Required-field warning](phase6_screenshots/report_warning.png) |

## Verification

- **Flutter regression:** 166 tests passed. Fifteen new tests cover the entitlement matrix, unauthorised payloads, draft round-trip, recipe export and PDF generation, reused welcome preferences, and both creation entry points across all six locales and eight app colours. Shared choices were checked at 360 × 680 logical pixels and 170% text scale.
- **Static analysis:** The project reported the same 16 pre-existing findings outside the Phase 6 changes. The production entry point, dependency manifests and iOS and Android configurations have no diff.
- **Native:** Phase 6 SQLite creation, grant recovery, editable draft and history checks passed on the iPhone 16 Pro simulator (iOS 18.5) and Pixel 6 emulator (Android API 34). The Phase 2 CPD parity suite passed five scenarios on each runtime, covering legacy data, targets and actual PDF, CSV and ZIP exports. The Phase 3B migration authority and recovery suite also passed on both.
- **Android interaction:** Verified the same three choices on first onboarding and from Home. Force-stopped and relaunched during first-profession drafting and during pending checkout. Resumed the draft and saved the free tile, then resumed checkout and simulated cancellation and completion. Opened the interactive form, completed example and PDF without buying. Verified scoped arrangement and reinstatement, expanded access via a simulated legacy grant, and a visible incomplete-report warning after excluding a required field.
- **PDF:** Regenerated by the app’s reporting code. Rendered and visually checked the single-page A4 example, including its activity fields, explicit synthetic evidence labels and totals. The three entries subtotal four hours, including two hours 45 minutes participatory.

## Known limits

The rehearsal distributes one synthetic pilot with English report content and fallback English for some bundled metadata. Draft autosave covers the profession name, saved layout-draft operations and report selection. Inputs inside an unsubmitted field configuration dialog remain transient. The sample form uses synthetic evidence. Report history covers pinned selections and rules; a public report cycle selector, final evidence handling, broader locales and selectable template upgrades need further work. The minimum OS versions and physical-device VoiceOver and TalkBack remain unverified here.

## Outstanding decisions and next phase

Review pilot fields, practice-note language, evidence handling, naming rights and the generated PDF with users and against the applicable requirements before release. Approve real store verification, the iOS cutoff and Android legacy resolution before moving beyond simulation. Decide on a selectable update workflow, dated scheme cycles, full multilingual report typography, and treatment of generated reports and supporting originals. Exact iOS 15.6 and Android API 24 signed upgrades, physical-device accessibility and recovery of every acknowledged post-activation write remain mandatory release gates. Keep production storage on the existing authority until explicitly authorised.
