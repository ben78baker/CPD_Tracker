# Phase 6 plan · onboarding and profession creation

**21 November 2026 · Approved internal rehearsal.** Phase 6 adds shared profession creation, onboarding recovery and scoped template customisation. The [UI specification](../../../docs/custom_fields_ui.md#9-onboarding-and-shared-profession-creation) defines screen behaviour. The [architecture](architecture_implications.md#10-shared-profession-creation-and-onboarding) defines access, commit and recovery boundaries. The [implementation report](phase6_implementation_report.md) records the verified results.

## Review of the existing flow and components

| Area | Reuse and Phase 6 work |
|---|---|
| Welcome and preferences | The current welcome includes language, app colour, optional personal details, profession name and week start. The action already says Continue. It currently attempts the profession write and completion flag before replacing the route with Home, including a fallback to Home after a caught error. Reuse the welcome header, colour selector and existing preference widgets. Remove naming and profession creation from this page, persist preferences separately and use Continue to open Page 2. [Onboarding page](../../../lib/onboarding_page.dart) |
| Home and shared naming | Home currently uses an independent Add Profession dialog and refreshes active and deleted tiles after saving. Route each Home add entry to the same creation page as onboarding. Reuse CPD name normalisation, active and deleted name checks and the existing recovery path. Validate again on commit. [Home creation](../../../lib/home_page.dart) · [CPD name normalisation](../../../lib/cpd_compatibility/cpd_data_store.dart) |
| Layout editor | Reuse the Phase 5 editor, field settings, searchable library and field tiles. Use a draft-only save handoff for creation before there is a persisted profession. Reuse CPD protected bindings and the 20-active-field limit at both UI and commit. [Edit Fields](../../../lib/recording_editor/edit_fields_page.dart) · [CPD layout policy](../../../lib/cpd_compatibility/cpd_layout_policy.dart) |
| Templates and previews | The Phase 5 host can render a sample template and compare a revised recipe to an installed layout. Phase 6 adds a browsable catalogue and selection flow around the reusable preview. Supply localised metadata, synthetic examples and an example report tied to one approved recipe and reporting version. Verify the preview against the layout actually adopted. [Template preview](../../../lib/recording_editor/template_preview.dart) · [Phase 5 authoring and comparison](phase5_visual_field_editor.md#template-updates-and-authoring) |
| Data and store access | The rehearsal has a transactional SQLite repository with saved recipes, layout revisions and host metadata. Add a CPD host creation service for atomic commits and resume receipts in the isolated store. Route purchases and restore through a CPD host boundary. Use controlled entitlement fixtures for Phase 6, with verified accounts and actual store integration subject to separate authorisation. [Repository](../../../lib/recording_engine_storage/sqlite_recording_repository.dart) · [Storage authority](phase3b_migration_readiness.md) |

## Implementation sequence

1. **Shared shell and free default.** Move profession naming to shared creation. Wire a synthetic first launch and Home Add Profession to the same three tiles. Reuse the existing theme, preference controls and localisations. Implement Standard CPD before the paid paths and verify it under offline and store-failure fixtures.
2. **Drafts and access.** Connect Custom CPD to the Phase 5 editor, show the relevant access terms before editing, and rehearse app-wide and verified legacy grants. Connect the versioned template catalogue and preview. Rehearse verified template ownership, restore, purchase transitions and optional editing of the adopted template. Test each path from each entry point.
3. **Durable creation and recovery.** Persist creation receipts and independent entitlement state in the rehearsal. Exercise double submission, duplicate and late purchase events, process termination, name conflicts, storage failure and retry. Verify launch classification against legacy and partially completed synthetic installs. Keep the production startup and write paths separate.
4. **Pilot content and parity.** Seek approval for one profession specification and its sample report. The existing nursing research fixture is a candidate. Review the fields, choices, permitted marketing claims, localised metadata, reporting rules and sample data. Verify recipe version parity from preview through adoption and verify that editing report-affecting fields produces understandable feedback. [Nursing research specification](../uk/nmc.md)
5. **Review and release gates.** Review the rehearsal results and accessibility on native runtimes. Where the exact minimum versions are unavailable, record the gap and exercise the closest supported test environment. Approve real store integration and public navigation separately. Retain the iOS 15.6 and Android API 24 signed-upgrade gates, physical-device checks, migration recovery and retention, and proof that recovery keeps all acknowledged post-activation writes. [Migration readiness](phase3b_migration_readiness.md)

Show the access scope immediately for a paid route. Where checkout is required, recommend checking the name before starting checkout so an invalid or conflicting name can be resolved first. The final save still checks name and access. Restore or late transaction verification can recover ownership independently of a draft. Label the amount with the store-provided localised price when a real store is authorised.

## Relaunch and recovery flow

```text
Launch → Read existing completion and storage authority
           ├─ Completed → Home / existing recovery
           ├─ Confirmed receipt for the first profession → Repair completion → Home
           ├─ Confirmed older installation → Home / existing recovery
           ├─ Welcome step completed and first profession pending → Resume shared creation
           ├─ Confirmed new installation → Welcome with any saved preferences
           └─ Read or authority uncertain → Retry / existing recovery

Pending or restored purchase → Verify and record entitlement → Update the creation choices
                                                                  └─ Wait for explicit creation
```

Automatically persist creation and field-edit drafts locally. Preserve the base revision, pending field layout and report choices. Offer Resume and Discard; an outdated edit must be reviewed before it can replace the active revision. A recovered purchase after abandonment still grants access and leaves the choice of profession creation with the user.

## Rehearsal acceptance criteria

| Test group | Pass condition |
|---|---|
| Welcome and navigation | Welcome shows the existing preferences with no profession input. Continue opens the shared creation UI after a successful preference save. Back, app restart and invalid or failed saves preserve the latest valid preferences. Both entry points render the same three choices and take the same path for naming, editor, catalogue, payment, failure and confirmation. First creation opens Home; subsequent creation returns to the existing Home with the new tile visible. |
| Free path and naming | Standard CPD creates one profession with the free layout even offline or during an unavailable store, pending purchase or access check failure. It keeps ordinary entry, duration, targets, search, deletion/recovery and exports. Blank names, normalised duplicates and deleted names get the same validation from both entry points. A deleted-name conflict offers existing recovery. Concurrent attempts with the same name produce one created tile and a conflict or idempotent success as appropriate. |
| App-wide and scoped access | Unentitled users see Custom CPD access requirements before entering the editor. Purchased Custom Fields and a verified legacy grant permit app-wide editing without another payment for that capability. A verified template owner can customise multiple independent copies of the same template. Template-only ownership leaves Custom CPD from scratch and edits of unrelated layouts gated. App-wide Custom Fields by itself leaves unowned templates unowned. Check canonical field protections and the 20-field cap in each path. |
| Template evaluation and back | From each entry point, open the complete pre-purchase form, interact with controlled choices and profession fields, view completed examples and generated PDF, and inspect version and full regulatory review date. Compare the approved base recipe and report provider with adoption. Back restores catalogue context and returns to the three choices without payment. Preview interactions leave no record, target, statistics, search, file or entitlement changes. |
| Checkout and restore | Rehearse owned, unowned, cancelled, declined, pending, offline and restored cases. Test duplicate/out-of-order callbacks, late success after Back, repeated taps and relaunch between verification, entitlement persistence and profession creation. A purchase event is processed once logically and grants the correct scope; restore recovers access without charging again. A verified purchase is retained if the draft is cancelled or a profession write fails. Standard remains reachable. |
| Creation and onboarding recovery | Terminate before commit, during commit and after commit but before completion is saved. A retry of the same request yields at most one profession and the correct active layout. Failures leave no partial tile. An existing installation, including one with no current tiles or with deleted data, bypasses a repeated onboarding flow. Verified recovered first creation opens Home; unreadable state enters retry/recovery. Check preferences and durable completion against migrated synthetic data without enabling production migration. |
| Localisation and accessibility | Rehearse English, German, Spanish, French, Hindi and Portuguese across all eight app colours using automated checks, including narrow screens and large text. Check translated and user-entered names, text wrapping, touch targets, focus and error announcements, keyboard and system Back, VoiceOver and TalkBack, scrolling, drag and accessible reorder actions. Run representative native cases on both platforms and track minimum-version and physical-device gaps explicitly. |
| Regression and isolation | Run the existing Flutter suite, static analysis, CPD parity and migration/recovery suites. Verify no production activation, no changes to signing or release settings, no preview access to production data and no user data conversion. Exercise realistic recovery checkpoints and preserve the established release gates. |

## Phase 9 addition to the creation flow

Both first-run and existing-user creation get the same catalogue and preview trial controls. Trial activation is a distinct action and is never inferred from browsing or copied into a creation draft. Starting the trial does not complete onboarding or create a profession. Keep the free Standard CPD choice and back navigation accessible while the store or trial authority is unavailable. Apply the same confirmation and idempotent commit when the user creates the first or an additional trial placement. [Phase 9 trial states and acceptance checks](phase9_template_trials.md)

## Definitive Phase 6 approval conditions

- Rehearse the approved tile names and retain free Standard CPD. Use simulated store access without prices.
- Apply the [entitlement decision matrix](../../../docs/custom_fields_ui.md#10-phase-6-entitlement-decision-matrix) to both UI commands and CPD commits. Verify optional field removal and reinstatement, report exclusion independently of form availability, default reset, immutable template payloads and independent placements.
- Exercise automatic local creation and edit drafts through relaunch, discard and stale saves. Rehearse purchase recovery independently of the draft, including previously verified offline grants.
- Select and verify one pilot from authoritative sources. Demonstrate current, optional-content and incomplete reporting states. Keep the historical report configuration and template version available after edits or an offered update.
- Review signed minimum-version, physical device and full recovery coverage before release. Live store mappings, verification, pricing and distribution are separate decisions.
