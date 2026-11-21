# Custom Fields UI specification

Updated 21 November 2026 · UI specification and internal Phase 5 implementation.

## 1. Agreed scope

**Edit Fields** is a visual editor for one profession tile. It uses the same field shapes, ordering and presentation principles as the actual CPD entry form. Users can configure and reorder fields, add a field from scratch or from the searchable **Field Library**, and save the result as a new layout revision. The editor and library are part of Custom Fields.

Each profession can have **20 active record fields**, including active standard fields. A centrally configured rule governs the editor, the save operation and any resulting template layout. A field available only to future records still counts as active. Retired historical fields, the profession heading and report-branding assets sit outside the count. Replacing or reactivating a field is evaluated against the resulting active layout.

Retain stable field identities, canonical activity date and credited duration, and access to historical values and evidence. Edits are pending until Save. Public navigation, purchasing and release work require separate authorisation.

### Commercial and navigation rules

| Access | Result |
|---|---|
| Standard free app | Continue using the standard record form, editing record values and using existing evidence, search and export functions. |
| Individual profession template · £3.99 initial UK price | One-time, non-consumable ownership of that complete predefined layout, reusable across profession tiles. Users can edit record values on it. Structural editing requires Custom Fields. |
| Custom Fields · £12.99 initial UK price | One-time, non-consumable access to the full editor and Field Library on all current and future profession tiles, including editing independent copies of owned templates. |
| Verified original paid-app customer | Permanent Custom Fields access at no charge. Predefined profession templates are purchased individually. |

Store purchases are associated with the relevant store account. Display store-provided localised prices in the eventual shop and entitlement flows. Each tile retains its own applied layout and history. Ownership of a template and entitlement to edit a layout are independent.

Open **Edit Fields** from the profession tile overflow, the **View Records** page menu, and the individual **View Record** page menu once that screen exists. Resolve the same stable profession identity from each route. Keep the main home menu free of this action. On a locked tile, explain the Custom Fields entitlement and provide a path to purchase, restore or check legacy access when those flows exist. Template-only owners retain the fixed layout and can continue editing values. Refresh a verified entitlement on return where needed, while keeping regular record work available if the store is temporarily unavailable.

Per-profession company logos and report branding remain a separate premium capability for anyone with at least one owned template, purchased Custom Fields or a verified legacy Custom Fields grant. The logo and inclusion preference are stored per profession, consume no field slots, and apply to eligible standard and evidence PDF exports through the separate branding design.

## 2. Visual Edit Fields screen

Reuse the presentation patterns in the [entry form](../lib/add_entry_page.dart) and its [form tile](../lib/widgets/form_section_tile.dart), including labels, spacing, icons, supporting text and theme tokens. Use a configuration mode to add editor controls. A realistic sample shows the field’s input shape, optional help and formatting. It uses illustrative values and exposes no real record data. A preview interaction must never save an activity, upload evidence or start a camera or document picker.

Recommended compact layout. Allow controls to wrap at larger text sizes.

```text
┌────────────────────────────────────┐
│ ‹ Edit Fields                      │
│ Physiotherapy                      │
│ 7 of 20 fields         + Add Field │
├────────────────────────────────────┤
│ Activity date                  ⠿ ⋮ │
│ [ 19 November 2026               ] │
│                                    │
│ Learning and reflection        ⠿ ⋮ │
│ [ What did you learn?            ] │
│ [                                ] │
│                                    │
│              More tiles ↓          │
├────────────────────────────────────┤
│ Cancel                        Save │
└────────────────────────────────────┘
```

Put **+ Add Field** in the top-right area. On smaller phones, place it at the right of a header row below the app bar, with the count beside it or above it if space is tight. Keep the count and Add Field reachable from a long layout. Show the remaining action clearly at capacity, for example **“20 of 20 fields. Remove a field to add another.”** Disable the add action or explain the restriction if activated. Keep reorder, remove and safe replacements available at capacity.

### Tile options

| Menu item | Configuration |
|---|---|
| Rename | Edit the display label and preview how it wraps. The field ID and history follow the field. |
| Required or optional | Change requiredness for applicable new records. Explain how historical blanks are handled. Respect canonical field rules. |
| Placeholder or help text | Provide type-appropriate guidance. A placeholder is a hint and should never be saved as a value. |
| Change field type | Offer supported conversions. Explain preservation and replacement for incompatible types before adding the change to the draft. |
| Configure choices | For an enabled controlled-selection type, edit labels and order, add choices, and retire used choices without disconnecting stored selections. |
| Display and formatting | Offer constrained options appropriate to the type, such as a unit label or supported date/time display. Keep labels and values readable in both the entry form and exports. |
| Move up or down | Provide an accessible alternative to dragging, omitting or disabling unavailable directions. |
| Remove | Stage removal. Show the historical preservation decision when values or evidence exist. Protect canonical fields. |

Use a dedicated drag handle to lift and move the **whole tile**. Only the handle starts a drag. The tile’s menu and preview keep their own gestures. Recommend vertical movement with a visible insertion position and edge auto-scroll. After dropping or using a move action, keep focus on the moved tile, announce its new position and update the visual order immediately. Apply changes to the pending revision.

The canonical activity date and credited duration retain their reporting, filtering and total semantics. The standard form also depends on bindings for title, details and evidence. Title and details supply activity text, with at least one present in the free workflow. Evidence supplies the existing evidence and export paths. These five fields can be moved and relabelled with safe presentation changes. Their identities, types, requiredness and standard behaviour are protected. Extra template or custom fields can be removed from the active layout while historical values remain available. Shared date and duration presentation follows the app’s conventions. Defer per-field fonts, arbitrary colours and typography controls.

## 3. Add Field workflow

```text
Edit Fields → + Add Field → choose a source
                              ├─ Create Custom Field → choose type ──────┐
                              └─ Field Library → search/browse → preview ┤
                                                                         ↓
                        Edit Fields draft ← Add to layout ← configure + choose applicability
                                ↓
                               Save
```

The first modal has two primary options, **Create Custom Field** and **Field Library**. Recommend a short initial sheet, then a taller sheet or dedicated screen for search and configuration so the keyboard, content and actions fit on a small phone. Back returns one step and preserves search/filter context. Cancel closes the flow without changing the layout. Warn before discarding an unfinished field configuration when it contains edits.

### Create Custom Field

1. Choose an available type. Each option shows its name and a short example.
2. Enter a label and configure applicable options such as requiredness, placeholder, help, validation, unit or options. Show a live sample. Keep advanced settings out of the default path.
3. Choose **Apply to existing and future records** or **Future records only**. Explain both in plain language. Both operate only on the selected profession.
4. Validate the configuration and active count. Insert the tile into the draft when the user confirms **Add to layout**. Recommend appending and scrolling to the new tile, with keyboard focus returned to its header. Reposition it with the handle or Move actions.

### Field type status

| Status | Types and behaviours |
|---|---|
| Available in the rehearsal editor | Short and long text, whole and exact decimal numbers, dates, duration, single and multiple choices, yes/no and checkbox, web links, file attachments and photographs, plus section headings. File and photo examples use synthetic evidence only. |
| Further review | Locale-aware dates and decimal input already use the shared presenter. Decimal credits and elapsed minutes have separate meanings. CPD subset durations need a host rule. Decide the public type rollout after device and practitioner checks. |
| Later research candidates | Time and timestamps, structured location, informational blocks, hierarchical competency vocabularies, evidence eligibility metadata and objective links. Keep signatures, declarations and verification at the appropriate portfolio level unless separately specified. |

Publish a library definition only when its type, validation and choices are supported on that build. Use neutral, scheme-specific explanatory copy for available definitions. Exact release sequencing is an approval decision. [Profession research and priorities](../research/cpd_templates/field_type_recommendations.md)

## 4. Searchable Field Library

Put search at the top of the library. Match labels, aliases and professional terminology, descriptions and categories. Show categories or filters without requiring category navigation before search. Recommend ranking exact label matches first, followed by synonyms and wider metadata matches. Keep filters optional, visible and easy to clear. Offer profession or scheme filters when the catalogue is large enough to need them. Nested categories can help browsing if the catalogue grows, with global search and direct result entry available at every level.

| State | Behaviour |
|---|---|
| Search is empty | Show browsable categories and available fields. Offer clear examples of search terms if helpful. |
| Results | Show field name, type and a short description. Include scheme applicability where relevant. Allow preview before adding. |
| No results | Show **No fields found**, retain the query, and offer to clear the query or filters. Keep Create Custom Field accessible through Back or a clear secondary action. |
| No available library content | Explain the empty or unavailable state and keep Create Custom Field available. Recommend a local bundled catalogue for offline browsing. |
| At capacity | If the user is already in a preview and the layout reaches the cap, prevent insertion and explain what must change. Preserve the draft and search context. |

Proposed categories are **Activity Details**, **Learning and Reflection**, **Time and Credits**, **Evidence and Attachments**, **Professional Standards and Competencies**, and **Assessment and Verification**. Treat these as an initial taxonomy for review. Avoid linking a field’s identity to its category.

Preview shows a sample input, description, help, defaults, choices, intended uses and any scheme-specific limits. Where applicable, show a short source reference with jurisdiction and guidance date. Illustrative candidates include learning objectives, impact on practice, learning provider, participatory hours, verifiable CPD units, competency mapping and supporting evidence. Confirm individual definitions against their scheme research before inclusion.

From preview, continue to the same configuration, applicability and insertion steps used for custom fields. Start with the definition’s defaults and show which settings are editable on this copy. Confirm the resulting count before inserting the tile. The new instance stays in the pending revision until Save.

### Library definitions and inserted fields

| Reusable definition | Field instance on a profession tile |
|---|---|
| Stable library ID and version; label and aliases; input type; description and help; validation defaults; predefined choice IDs and labels; category; profession/scheme applicability; source reference and verification date where relevant. | Independent stable field ID, profession association, type and effective configuration, order, requiredness, applicability and retirement metadata. Keep optional provenance back to the library definition and version. |
| A definition update changes the default for a future insertion. | Insertion copies the supported settings. Existing instances and their historical values retain their configuration unless the user explicitly changes them. |

Eligible fields originating from profession-template research can appear normally in the library for everyone with Custom Fields. Do not require purchase of the original profession template to use those fields, or block users from building a similar layout themselves. The template purchase provides the complete managed layout, template updates and any separately approved scheme-specific reporting associated with it. Adding a field does not grant those benefits or certify that a record, export or portfolio satisfies a scheme. Label regulator-specific choices and validation so the user knows where they apply. [Scheme and source index](../research/cpd_templates/profession_index.md)

## 5. Drafts, historical records and save

| Action | Behaviour on save |
|---|---|
| Add to existing and future records | Make the blank field available for applicable older records of the same profession as well as future records. Use applicability metadata so old records need no bulk empty values. |
| Add to future records only | Include it in records created under the relevant new layout. Use creation revision independently of the activity date, so backdated new records still receive the field. |
| Rename or reorder | Retain the field ID, stored values and evidence. Apply the relevant revision when presenting records and exports. |
| Change to an incompatible type | Keep old typed values and evidence on the retired field. Create a new field identity for the replacement and choose its applicability. Offer a safe in-place change only if the value, validation and reporting meaning can be preserved. |
| Remove without historical values | Retire or remove the definition from new entry. Use no additional data-loss warning. |
| Remove with historical values or evidence | Default to **Preserve historical data**. Retain historical values and referenced evidence in record views and exports. Offer **Permanently delete historical data** with a separate explicit confirmation, and **Cancel**. Consider restorable records when assessing impact. |

Requiredness must not block an unrelated edit to an older record because a newly applied field is blank. A new layout revision must not silently remove values or attachments. Explicit purge should show affected records and evidence, be revalidated at Save, and be protected against deleting any shared evidence still in use. Confirm the destructive intent before committing, especially if the impact changed since it was staged. A draft cancellation leaves evidence and records intact.

**Save** validates the complete pending layout, including field count, nonblank labels, supported settings, choices and canonical bindings. Commit the layout revision and agreed historical changes together. Show saving state and prevent duplicate submission. On validation or save failure, keep the draft and show what to fix. On a concurrent layout change, offer to reload or reconcile before saving so an older draft cannot overwrite a newer layout. If editing rights change while the editor is open, preserve the draft for the session and explain how to restore access or exit.

**Cancel, Back and system dismissal** return normally for an unchanged draft. For a modified draft, offer to keep editing or discard it. For the first release, recommend keeping incomplete edits in memory while navigating within the flow and retaining them on a failed save. Decide separately whether to recover drafts after process termination. A recovered draft must never auto-commit or carry forward a stale permanent deletion confirmation.

## 6. Accessibility, responsiveness and validation

- Keep the tile list and library scrollable with the keyboard open. On compact screens, wrap the header and long names, and give long option lists a searchable, scrollable view where warranted. Avoid fixed-height tiles that clip content at large text sizes.
- Give icon buttons accessible names that include the field label where context is needed. Support keyboard focus order, visible focus, activation and reorder actions. Return focus to the invoking control when a modal closes. Mark preview controls as examples so a screen reader does not mistake them for live data entry.
- Use generously sized touch targets for the drag handle, overflow and primary actions. Announce position changes, remaining capacity, validation errors and saved status without relying on colour. Respect reduced motion and test the current accent choices in light and dark themes.
- Show validation close to the control and surface the first relevant error on Save. Explain duplicate or ambiguous labels if used and preserve disambiguation in exports. Require valid bounds and units for durations and decimals. Validate choice sets so stored selections survive label changes and retired choices. Keep unsupported definitions out of creation flows, but preserve historical data that uses them.
- Test a full layout, very long labels and options, large text, keyboard-only reorder, screen-reader navigation, cancel during configuration, a failed save, and save after an intervening entitlement or layout change. Use fixture records with historical values and shared evidence when verifying removal and replacement.

## 7. Architectural implications

The [Phase 4 implementation](../research/cpd_templates/international/phase4_recording_configuration.md) supplies the generic model and storage operations. These requirements guide Phase 5 UI work and host integration.

- Keep **library definition IDs**, **field instance IDs**, **choice IDs**, **profession IDs** and **layout revision IDs** independent. A title, category, array position or option label cannot serve as identity. Choice renames and reordering preserve selections. Retired choices remain resolvable in past records and exports.
- Store field type and effective instance metadata with the relevant revision. Preserve optional library and template version provenance so catalogue changes and template updates do not overwrite local copies. Define compatibility for unknown types and metadata from a newer catalogue.
- Represent each record’s creation revision and sparse values separately from field applicability. Retain historical presentation and canonical bindings. Share a resolver across entry, views, search and exports so applicable, missing and retired values behave consistently.
- Validate the centrally configured limit against the resulting active layout at commit, including batch changes and template application. Use identity-aware revisions so obsolete drafts cannot silently overwrite newer layouts or lose attachments.
- Separate purchase ownership, logo entitlement and Custom Fields access from profession layout data. Store report-branding asset references and inclusion settings separately from field values. A lost entitlement changes available actions, while historical data remains usable.

### Proposed later delivery phases

| Phase | Scope |
|---|---|
| Design approval | Confirm the positions and names of controls, supported type rollout, library taxonomy and scope, canonical-field presentation and historical workflows. Review sample layouts against the existing free entry form. |
| Phase 4 · Engine foundation completed | Stable identities, revision resolution, catalogue provenance, choice retirement, atomic layout validation and historical export projections. The internal preview exercises two synthetic forms. Separate branding metadata remains a host concern. |
| Phase 5 · Internal editor and preview | Rehearse the form-like draft editor, library, historical record presentation and an isolated template preview. Verify purchase-independent access in the rehearsal and keep production navigation separate. |
| Phase 6 · Researched catalogue and authoring, separately authorised | Review each profession specification. Bundle one approved version with its translated metadata, sample values and report context. Verify the actual form and sample report from the same version. |
| Premium release, separately authorised | Surface the public preview from the catalogue regardless of ownership. Connect confirmation, purchase and restore to the CPD host. Integrate reporting and branding on their own schedules. |

### Decisions for approval

- Initial supported selection and decimal types, including how controlled choices, subset durations and scheme credits validate.
- Exact display options and allowed label or placement changes for canonical date and duration.
- Initial library categories, profession filtering, definition review process and compatibility rules for future versions.
- Compact-screen modal transitions, default insertion position and whether preview controls are static samples or use a safe sandbox.
- Duplicate-label policy and cross-launch draft recovery.
- Placement and recency of access messaging, exact destructive confirmation wording and handling of historical choices in exported reports.

## 8. Pre-purchase profession template previews

Offer **Preview** from each profession-template detail page. Viewing a preview is available before purchase. Show the intended profession, country, professional body and scheme; features and limitations; customisation options; current template version; and the date the regulatory requirements were last reviewed.

Use the shared record renderer to show the complete versioned form as it appears after purchase. Users can enter temporary sample values, inspect choice lists, open representative completed records, and view an example PDF report. Provide labelled example evidence without opening a camera, gallery, document picker or upload flow. Present the example report as a sample of the selected template version. Use the production report pipeline with a synthetic input source when the scheme reporting implementation is ready.

The preview session lives in memory and discards edits on exit. The preview route receives bounded template metadata, a recipe snapshot, synthetic values/evidence labels and a read-only report provider. It receives no record-writing, installation or entitlement mutation interface. Its values do not appear in records, targets, statistics, search or the evidence store.

Future purchase, restore and activation are separate CPD-host actions. The host checks ownership before creating a versioned layout for a profession. Access to preview content, reusable library fields or the generic renderer does not change ownership. Verify preview parity against authorised adoption and repeat the check with each official template revision. Use generated preview content from the installed recipe rather than maintained product screenshots. [Phase 5 implementation report](../research/cpd_templates/international/phase5_visual_field_editor.md)
