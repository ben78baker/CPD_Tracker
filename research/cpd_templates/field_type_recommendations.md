# Field type recommendations

| Priority | Type or capability | Evidence and use | Complexity and design |
|---|---|---|---|
| 1 | Stable single-select categories | ACCA verifiability, IET learning method, GDC evidence state, Social Work England portal category | Medium. Persist stable option IDs, support controlled Other, and retain labels for retired choices. |
| 1 | Additional duration with subset validation | NMC participatory minutes and CPA Australia ethics minutes | Medium. Store integer minutes and validate subset against the canonical duration. Keep calculation rules separate from label text. |
| 1 | Multiline text with prompts and copy | HCPC benefit, Social Work England long reflections, ACCA application, SRA outcomes | Low to medium. Offline drafting, clipboard transfer, word-count guidance and private export inclusion matter more than rich text. Preserve line breaks. |
| 2 | Multi-select controlled taxonomy | GDC outcomes, Social Work England standards, ARB topics | Medium. Stable choices and deterministic export labels. Support coverage indicators. |
| 2 | Decimal credits with explicit scheme unit | CORU credits and California contact hours | Medium. Exact decimal or scaled representation; never silently convert to canonical minutes. Expose scheme-specific rounding at aggregation. |
| 2 | Evidence reference and eligibility metadata | NMC proof, GDC evidence, ACCA verifiable claims and California certificates | Medium. Reuse file import and preserve a reference for external evidence. Eligibility is user-confirmed. Sensitive evidence stays selectable. |
| 3 | Optional second date | Multi-day NMC and completion workflows | Low. Keep standard activity date as completed date and validate the optional start. A reporting period is a report criterion. |
| 3 | Objective/goal reference | Engineering CPD, Ontario QA and dental PDP | Medium to high. A text reference can work initially; real many-to-one plan links are a portfolio feature. |
| Defer | Signature and declaration fields | NZ audit verification and selected renewal workflows | High. Model separately at portfolio level. A checkbox should never imply independent verification. |

Priorities are proposed, not approved. Standard date and duration stay canonical. Retired historical definitions remain readable and exportable. Centrally enforce 20 active fields including standard bindings. Logo assets and portfolio metadata are separate from activity fields.

## International programme recommendation · 20 November 2026

The [Field Library catalogue](international/field_library.md) translates the research into deduplicated field definitions. The following is the proposed minimum for the first catalogue, subject to separate approval. Keep draft records editable, and distinguish ready-to-report checks from saving an in-progress record.

| Primitive or configuration | First-catalogue recommendation | Validation, accessibility and output |
|---|---|---|
| Short and multiline text | Support both using one text storage model, with separate presentation affordances. | Trim names and codes conservatively, preserve body line breaks, and avoid hard minimum word counts where guidance is advisory. Use named controls and copy-ready prompts. Export text with proper CSV quoting and mitigate unintended spreadsheet formula evaluation. |
| Date | Date-only for canonical activity and optional start or review dates. | A completed activity uses date rules appropriate to its scheme. A planned review may be in the future. Allow locale-aware display, stable ISO machine output and start-before-completion validation. |
| Duration | Integer minutes for the existing credited field and supplemental duration fields. | Keep NMC participation and eligible ethics as separate concepts. Enforce subset bounds when both values exist. Show units and permit explicit zero. Separate rounding and inclusion at report time. |
| Managed attachment | File and photograph are capture/display configurations over shared evidence metadata. | Preserve originals, support unresolved references, set accessible labels, and require explicit selection for private originals or sensitive outputs. |
| Controlled choice | Approve single-select and a bounded multi-select on one stable-choice representation. | GDC outcomes genuinely need multiple choices, while CII structure needs one. Preserve retired option identifiers and labels. Distinguish blank, Other and no eligible option. Provide searchable options for long lists, clear keyboard focus and spoken selected state. |
| Exact numeric quantity | Approve only when launching schemes that require exact awards, such as California contact hours or CORU credits. Integer is a scale/bounds configuration. | Preserve decimal precision and explicit unit, support the locale decimal separator, and prevent summing unlike units. Keep stored values distinct from formatted output. |
| Boolean, references and URLs | Later or scope-specific. A yes/no confirmation is one input mode; use nullable choice when unknown is meaningful. Objective link and URL are reference configurations. | No verification inferred from checking a box. Restrict supported URL schemes and require explicit opening. Portfolio entities and signatures need separate design. |

**Versioning.** Keep scheme vocabulary separate from a library category and from the user’s local choice IDs. Exports resolve an historical value to a meaningful label even if the choice was retired. Search should match current labels, scoped aliases and retained choice labels where appropriate. Conditional rules should initially be a small set of domain validations, such as evidence required when marked verifiable. Defer a general-purpose rules editor.

**Downstream sequencing.** The foundation is short/long text, dates, durations and evidence. The highest-ranked regulated candidates add stable single-select, bounded multi-select and one subset duration. Credits can use the same decimal quantity type where genuinely awarded, with explicit policy unit and precision. ACCA units can be derived from minutes under the approved route rule. These distinctions prevent a generic number field from silently reclassifying historical data.
