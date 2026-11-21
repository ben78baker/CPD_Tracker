# Reporting gaps and boundaries

Existing code shares a profession/date export selection across formats, with PDF evidence rendering and original-file ZIP fallback. The model stores date, title, details, hours/minutes, attachment references and deletion state. Existing exports are useful activity summaries. They lack scheme-specific calculations and declarations. See [model](../../lib/models.dart), [selection](../../lib/utils/export_selection.dart), [PDF exporter](../../lib/utils/pdf_exporter.dart) and [CSV exporter](../../lib/utils/csv_exporter.dart).

| Priority for a scheme claim | What is missing | Examples and acceptance condition |
|---|---|---|
| Essential | Rule-aware clocks and units | NMC personal three-year renewal with participatory subtotal; GDC role targets and adjacent two-year minimum crossing cycle boundaries; ACCA annual units and carry-forward; ICAEW November–October year; CPA Australia annual/triennial ethics minimum; NZ rolling 36 months; CORU credits; California contact hours. Test boundaries and aggregate rounding separately. |
| Essential | Portfolio evidence selection and historical field support | Include the eligible records, historical values and linked evidence, permit explicit original-file selection, report missing files, and respect anonymisation and reflection privacy. Verify that a ZIP retains distinct original files when names collide. |
| Essential for submission claims | Official workflow handoff | Social Work England portal entry, ARB MyARB/RIBA records, NMC approved reflection form and revalidation confirmation, MyGDC statements, ACCA annual declaration, CORU audit portal and NZ MyNC. Provide handoff instructions or copy-ready drafts and describe the output as a companion unless formally validated. |
| Essential for portfolio claims | Plans, declarations and verifiers | GDC PDP, Ontario annual learning plan, NZ competence evidence and signed declarations, NMC confirmer and separate practice-hour accounting. Add report/portfolio entities only with separate scope approval. |
| Essential for credible audit support | Long-term export and recovery | GDC completed-cycle retention and California four-year proof make data loss consequential. Validate user-managed backup and recovery, stable IDs, manually selectable time windows, evidence privacy and retention expectations. The share ZIP is an export. |
| Optional | Registration details, employer/company branding and layout refinements | Allow editable report-level metadata only where useful and lawful. Profession logos may appear in suitable professional reports without consuming record fields. Never imply endorsement, and leave anonymised or portal-facing outputs neutral by default. |

Test eligibility with fixtures covering scope exceptions, missing values, historical fields, records crossing policy changes and separate app/store recovery. Require a manual review screen before a compliance-sensitive export. Avoid automatically signing, submitting or declaring compliance.

## International programme reporting matrix · 20 November 2026

**Current capability.** Standard PDF can show a date-filtered activity summary. Evidence PDF and ZIP can present or carry evidence. CSV is a fixed-column export and cannot encode configurable choices, eligibility decisions or evidence relationships. None of these formats has verified official import support for the schemes below.

| Scheme | Required presentation or evidence | Current fit | Priority addition and handoff |
|---|---|---|---|
| [NMC UK](uk/nmc.md) | Individual log, own three-year cycle, 35 total/20 participatory hours, evidence, separate approved reflections and confirmation | Partial activity log | Add subset totals, Code theme and a clear cycle boundary. Separate official reflection and confirmation forms. |
| [GDC UK](uk/gdc.md) | Evidence-backed activity log, outcomes, annual declarations and role-specific five-year plus adjacent two-year windows | General summary/evidence only | Exact minutes, evidence eligibility and first-year/cross-cycle tests. MyGDC declaration stays manual. |
| [HCPC UK](uk/hcpc.md) | Ongoing activity log, mix of learning, service outcomes and selected audit profile | Partial | Evidence selection and chronological summary with privacy preview. A personal narrative still needs the official audit workflow. |
| [ACCA](uk/acca.md) | Verifiability, outcome and application, evidence, annual declaration and constrained carry-forward | General time total only | Separate subtotals, explicit adjustments and retained supporting material. Copy totals to myACCA. |
| [CII](uk/cii.md) | Own-format 12-month record, at least 35/21 structured hours, outcomes and evidence on request | General time total only | Qualified-member summary with selected evidence. Verify current expectation for a digitally submitted log by email or portal. |
| [CIOB](uk/ciob.md) | Subscription-year summary with four theme subtotals and separate annual reflection | General time total only | Test theme attribution and date cohort. Portal is the audit handoff. |
| [NICEIC](uk/niceic.md) | Business-assessment record of activity, time and key learning for people in scope | Partial, personal only | Personal assessment summary, evidence/archive recovery. No team attestation or competence verification. |
| [IET](uk/engineering_council_iet.md) and [SRA](uk/sra.md) | Goals, evaluation and learning need/impact. IET overlay hours and SRA annual declarations apply within scope. | Partial | Print portfolio-ready plan references and outcomes. Verify institutional review and keep declarations separate. |
| [New Zealand nursing](new_zealand/nursing.md) | Rolling development and separate practice totals, competency pou, signed and verified audit evidence | General summary only | Scope-specific vocabulary, 36-month window and authentic evidence. MyNC audit handoff. |
| [California RN](usa/california_rn.md) | Recognised provider, awarded contact hours, renewal dates and four-year certificate retention | Eligible hours absent | Scoped decimal unit, exact date and provider fields, certificate list and recovery. External renewal and provider checks. |
| [CPA Australia](australia/cpa_australia.md) and [ICAEW](uk/icaew.md) | Ethics and programme-year summaries with route or category targeting | General time total only | Evidence-linked ethics and separate minimums; confirm caps and category changes. |
| [CORU physiotherapy](ireland/coru_physiotherapy.md) | Twelve-month credit evidence, plan and evaluation for selected audits | Credit and portfolio absent | Exact local credit input and copy-ready audit fields. Official portal. |
| [Ontario nursing](canada/ontario_nursing.md) | Annual learning plan, assessment and declaration | Weak activity-only fit | Goal-linked portfolio and export. Keep official QA separate. |
| [Social Work England](uk/social_work_england.md), [ARB](uk/arb.md), [GPhC](uk/gphc.md), [RCVS](uk/rcvs.md), [RICS](uk/rics.md) and [IOSH](uk/iosh.md) | Prescribed recording/submission. Some accept independent preparation. | Drafts/evidence only | Current-form copy workflows and separate readiness indicators where worthwhile. No claim of direct submission or import. |

### Export contract for later approval

- **Personal activity log.** Preserve legacy output. Render active and relevant historical typed fields, linked evidence references, locale dates and optional approved tile branding. An export uses its selected records even if a layout changes during generation.
- **Cycle summary.** Show scheme/version, member scope, period, derived totals, exclusions and unknown eligibility. Report any rounding or carry-forward assumptions separately. A dashboard counter cannot attest compliance.
- **Audit portfolio and bundle.** Explicit record and evidence selection, redaction preview, path-independent manifest and status for missing or externally held originals. Preserve originals that the user selected. Keep declarations, third-party sign-off and compulsory forms outside ordinary activity rows.
- **CSV and future structured export.** Keep a clearly versioned, spreadsheet-safe flat export with stable field and unit mapping across revisions. Add a structured representation or separate tables if evidence or choice multiplicity makes the flat shape misleading. Record fidelity and future backup are distinct from regulator import.
- **Multi-profession and logos.** Keep one report per profession as the first supported scope. Future grouped outputs should use neutral cover branding and optional per-profession identity in their own sections. Disable branding by default for anonymised or portal-facing artifacts. Do not reuse regulator logos. Preserve existing standard and evidence PDF pagination.

Before claims of audit readiness, compare generated examples against dated official forms and have practitioners reproduce the handoff. Import formats, retention exceptions and authenticated acceptance remain verification tasks.

### Additional international and specialist reporting patterns

| Scheme | What the current exports miss | Product implication |
|---|---|---|
| [NSW teacher PD](australia/nsw_nesa_teachers.md) | Assigned accreditation period, required log columns and standards mapping | Audit-oriented table can accompany the accepted personal log route. Keep certificates out of the default log. |
| [NMBA](australia/nmba_nursing.md) | Audit record, relevant scope/registration, evidence and reflections across the relevant annual period | Separate practice standard from local log design. Confirm consultation outcome before automating totals. |
| [Engineers Australia](australia/engineers_australia.md) and [Singapore PEB](singapore/peb_engineers.md) | Multi-category development and caps, different assessment cycles and official submissions | Use shared field primitives with independently versioned policy calculators and test audit samples. |
| [CPA Ontario](canada/ontario_cpa.md) | Annual and rolling three-calendar-year total, verified subset, ethics subset and retained evidence | Add nested subset validations, five-year evidence preservation and separate copy-ready audit values. |
| [Ontario PEO](canada/ontario_peo.md) | Current practice evaluation, modules and measured hours; 2027/28 transition changes inputs | Defer automatic status. Keep current and future reporting rules distinct. |
| [NZ LBP](new_zealand/lbp_skills_maintenance.md) | Class-based elective time, two on-the-job activities, class quizzes | Counter types differ. A single duration total cannot substitute for recorded activities or quiz confirmations. |
| [California attorney](usa/california_attorney.md) | Award mode, partial credit allocations, exemptions and group dates | Future scheme-specific allocated quantities and personal audit log. Preserve parent/child credit accounting. Verify official tracker status. |
| [Texas nursing](usa/texas_nursing.md) and [Singapore SNB](singapore/snb_nursing.md) | Recent portal requirements, scope-specific award rules and claim statuses | No automated submission. Separate claimed from awarded CPD and distinguish provider verification. |
| [Hong Kong CNE](hong_kong/cne_nursing.md) and [Malta CPE](malta/accountancy_warrant.md) | Recognised routes, rolling or annual credit categories, authorised administrator records or returns | Confirm external workflows and current cohort before claiming a report can support the named compliance step. |
| [Ireland PSI](ireland/psi_pharmacy.md), [NI PSNI](uk/psni.md) and [GB GPhC](uk/gphc.md) | Different portfolio forms, regulator platforms, deadlines and evidence rules | Draft companion only without a verified handoff. No shared “UK and Ireland pharmacy” report. |
| [UK GMC](uk/gmc.md), [Scotland teachers](uk/gtcs.md) and [NZ teachers](new_zealand/teaching_growth_cycle.md) | Appraisal or employer-led learning confirmation and authentic planning evidence | Treat hours as personal data unless a separate body requires them. Individual activity PDF cannot replace appraisal or sign-off. |

The [international scheme index](profession_index.md) links every checked scheme and its local handoff and retention notes.

## Presentation requirements for shared and profession-specific reports

Keep the optional report language independent of the app, device and scheme. Apply it to document headings, available template labels and regulatory terminology, dates, durations and numeric displays. Preserve practitioner-entered text and values. Indicate source-language fallback when a translation is missing. Preserve the existing date preference on the inherited Standard CPD path and preserve the machine-readable CSV format. Explain recipient language expectations separately from the user preference.

The report configuration sets branding according to recipient needs. Support a branded header, subtle identity, discreet attribution and omission of app identity. Keep each option professional and economical to print. When a regulator prescribes a format or forbids branding, its requirements take priority. Maintain the existing professional-body attribution and independent-log wording without suggesting endorsement.

Use readable tables for scheme metrics and full-width activity sections. Identify the activity on continuation pages and retain long text and reference links. Original attachment bytes remain independent. Keep standard PDF, evidence PDF, CSV and conditional ZIP. For specialised release, qualify native sharing, printing and equivalent access to originals. Portable backup and restore cover source records and report configuration. Generated PDFs reside with the user when exported.

Qualify cold offline generation at the supported OS versions. For complex scripts, verify glyph shaping as well as embedded font coverage, extraction, mixed-script wrapping and pagination. [Phase 7A presentation, field-limit and Hindi evidence](international/phase7a_implementation_report.md)

## Recipient metadata and text fidelity

Keep template versions, rule revisions and regulatory review dates in the app’s report details. Include them in recipient-facing PDFs only when a reviewed rule expressly requires them. Use subtle CPD Progress Tracker branding when appropriate and let documented recipient requirements override it.

Author each bundle in the scheme’s working language. Use reviewed translations where available and preserve source terminology where they are unavailable. Keep the separate, optional report language and format dates, numbers and durations accordingly. Report generation never translates recorded values.

Verify multiple long activities in one report, line and page boundaries, unbroken reference IDs, exact link destinations, missing originals, retired values and excluded fields. Count pages with meaningful body content independently of the footer. Complex-script qualification requires offline rendering, valid links, original text preserved by search and copy, and review on both minimum OS versions. [Phase 7B reporting verification](international/phase7b_implementation_report.md)
