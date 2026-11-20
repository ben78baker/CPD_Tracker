# Custom Fields UI specification

Updated 20 November 2026 · Design specification for later development.

## 1. Agreed scope

**Edit Fields** is a visual editor for one profession tile. It uses the same field shapes, ordering and presentation principles as the actual CPD entry form. Users can configure and reorder fields, add a field from scratch or from the searchable **Field Library**, and save the result as a new layout revision. The editor and library are part of Custom Fields.

Each profession can have **20 active record fields**, including active standard fields. A centrally configured rule governs the editor, the save operation and any resulting template layout. A field available only to future records still counts as active. Retired historical fields, the profession heading and report-branding assets sit outside the count. Replacing or reactivating a field is evaluated against the resulting active layout.

Retain stable field identities, canonical activity date and credited duration, and access to historical values and evidence. Edits are pending until Save. The proposed interactions and implementation phases below require separate development authorisation.

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

The canonical activity date and credited duration retain their reporting, filtering and total semantics. They cannot be deleted or converted into unrelated types. Where display labels or placement are configurable, preserve the canonical binding, distinguish it from extra dates or durations, and keep the controls usable. Shared presentation may follow the app’s existing date and duration conventions. Defer per-field fonts, arbitrary colours and typography controls.

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
| Established planning baseline | Short text, long text, date, duration, photograph and file attachment. Reuse existing date, duration and evidence semantics. This is the minimum design baseline from earlier planning. |
| Proposed additions for approval | Dropdown or single-select with stable choices, and decimal number or credits with an explicit unit. Avoid using decimal credits as canonical elapsed minutes. Subset durations such as participatory time may need an additional validation rule. |
| Later research candidates | Multi-select taxonomy for competencies or standards, evidence references and eligibility metadata, optional second dates, and objective links. Keep signatures, declarations and verification at the appropriate portfolio level unless separately specified. |

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

## 7. Phase 1 architectural implications

These are data design requirements for consideration when Phase 1 is authorised. They do not prescribe a widget framework or database.

- Keep **library definition IDs**, **field instance IDs**, **choice IDs**, **profession IDs** and **layout revision IDs** independent. A title, category, array position or option label cannot serve as identity. Choice renames and reordering preserve selections. Retired choices remain resolvable in past records and exports.
- Store field type and effective instance metadata with the relevant revision. Preserve optional library and template version provenance so catalogue changes and template updates do not overwrite local copies. Define compatibility for unknown types and metadata from a newer catalogue.
- Represent each record’s creation revision and sparse values separately from field applicability. Retain historical presentation and canonical bindings. Share a resolver across entry, views, search and exports so applicable, missing and retired values behave consistently.
- Validate the centrally configured limit against the resulting active layout at commit, including batch changes and template application. Use identity-aware revisions so obsolete drafts cannot silently overwrite newer layouts or lose attachments.
- Separate purchase ownership, logo entitlement and Custom Fields access from profession layout data. Store report-branding asset references and inclusion settings separately from field values. A lost entitlement changes available actions, while historical data remains usable.

### Proposed later delivery phases

| Phase | Scope |
|---|---|
| Design approval | Confirm the positions and names of controls, supported type rollout, library taxonomy and scope, canonical-field presentation and historical workflows. Review sample layouts against the existing free entry form. |
| Phase 1 · Architecture, when authorised | Plan stable identities, revision resolution, catalogue provenance, choice retirement, atomic validation and historical/export compatibility. Leave an additive path for branding metadata. |
| Editor and Field Library, when authorised | Build the form-like editor, reorder and accessibility paths, field configuration, historical prompts and a reviewed searchable catalogue. Verify draft, save and failure recovery. |
| Premium release, separately authorised | Integrate store entitlements, templates and branding on their own schedules. Review each researched template specification before development or publication. Verify restore, offline behaviour and export continuity. |

### Decisions for approval

- Initial supported selection and decimal types, including how controlled choices, subset durations and scheme credits validate.
- Exact display options and allowed label or placement changes for canonical date and duration.
- Initial library categories, profession filtering, definition review process and compatibility rules for future versions.
- Compact-screen modal transitions, default insertion position and whether preview controls are static samples or use a safe sandbox.
- Duplicate-label policy and cross-launch draft recovery.
- Placement and recency of access messaging, exact destructive confirmation wording and handling of historical choices in exported reports.
