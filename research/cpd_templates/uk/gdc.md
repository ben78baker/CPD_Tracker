# GDC Enhanced CPD log

**Jurisdiction** United Kingdom  
**Scope** GDC registrants · dentists and dental care professionals; temporary registration exception  
**Recommendation** Suitable with cycle and verifiable-hours reporting.  
**Status** Research specification for review · 19 November 2026.

## Executive summary and official requirements

Five-year verifiable hours depend on title: dentists 100, therapists/hygienists/orthodontic therapists/clinical dental technicians 75, dental nurses and dental technicians 50. The guidance lists a separate 20-hour minimum for temporary dentist registrants. Highest applicable registered title governs. At least 10 verifiable hours across consecutive two-year periods including a cycle boundary, subject to first-year rules. Maintain a PDP and activity log and link planned activity to at least one development outcome. [D1 · CPD scheme](https://www.gdc-uk.org/education-cpd/cpd/cpd-scheme) · [D2 · Recording and submitting CPD](https://www.gdc-uk.org/education-cpd/cpd/cpd-scheme/recording-and-submitting-cpd)

## Evidence, official systems and reporting

Keep provider certificate, email or appropriate mapping document showing content, objectives, outcomes, participant, date, hours and quality assurance. A generic attachment does not prove eligibility. Submit annual CPD statements at renewal even in a zero-hour year. Round only the annual aggregate per GDC instructions. Retain completed cycle records for possible audit for up to five years. Clinical records and personal reflections need separate handling. Dentists use January–December and submit by 28 January. Dental care professionals use August–July and submit by 28 August. Confirm temporary-route rules and confirm the first-cycle boundary before automated reporting. [D1 · CPD scheme](https://www.gdc-uk.org/education-cpd/cpd/cpd-scheme) · [D2 · Recording and submitting CPD](https://www.gdc-uk.org/education-cpd/cpd/cpd-scheme/recording-and-submitting-cpd)

## Official activity log recheck · 20 November 2026

The GDC template confirms title and description, date, evidence-backed hours and at least one applicable development outcome per planned/completed activity. It recommends recording reflection or its occurrence, allows another tool or format that meets the requirements, and says to omit non-verifiable CPD from a record it requests. Covering all four outcomes over a cycle is encouraged. Current dentist renewal uses MyGDC, which replaced eGDC in March 2026; the November 2026 notice gives a 28 January 2027 statement deadline for that renewal. [Official activity log, pp. 2–4](https://www.gdc-uk.org/docs/default-source/education-and-cpd/cpd/cpd-scheme/cpd-activity-log-template-2025_a.pdf) · [Current renewal notice](https://www.gdc-uk.org/news-blogs/news/detail/2026/11/09/gdc-opens-annual-renewal-period-for-dentists)

## Proposed individual record

**9 active fields** including the standard bindings listed below. M is mandatory for the indicated scheme or submission, C is conditional, R is recommended and O is optional. Where a regulator specifies an outcome without prescribing columns, the fields are product recommendations. M/C checks should surface when marking a record ready or preparing a scheme export, with incomplete historical data remaining editable. Show all rows for eligible records unless conditional, and omit blank optional values from PDF. Export rule exceptions appear below.

| Field | Type | Class | Purpose | Standard binding | Proposed validation | Reporting |
|---|---|---|---|---|---|---|
| Completion date | Date | M | Map to correct CPD year | date | match provider evidence | period |
| Activity title | Text | M | Identify subject | title | short label | Detail only |
| Content and learning aims | Long text | M | Summarise scope and objectives | details | use evidence-aligned summary | Detail only |
| Provider | Text | R | Identify evidence issuer | New | nonblank if available | Detail only |
| Recorded CPD time | Duration | M | Retain exact activity minutes | duration | do not round per activity | eligible subtotal via status |
| Evidence status | Choice | R | Distinguish verified evidence from pending or nonqualifying | New | only self-confirmed qualifying entries count | eligibility filter |
| Development outcomes | Multi-choice | M | Link planned and completed activity to GDC outcomes | New | at least one where applicable | outcome coverage |
| Provider evidence | File | C | Retain authentic proof for verifiable CPD | evidence | certificate/email/mapping or external reference | Detail only |
| Relevance and impact | Long text | R | Link learning to PDP and practice | New | keep personal reflection selectively shareable | Detail only |

The specification derives from [D1 · CPD scheme](https://www.gdc-uk.org/education-cpd/cpd/cpd-scheme) and [D2 · Recording and submitting CPD](https://www.gdc-uk.org/education-cpd/cpd/cpd-scheme/recording-and-submitting-cpd). The types and validation wording are design recommendations. Choice, multi-choice and decimal inputs require separate feature approval.

## App fit and export boundary

The current app has one canonical activity date and duration, title, details, and general evidence. Standard bindings preserve those semantics. Existing PDF, PDF with evidence and CSV work from a profession and date selection and do not calculate this scheme’s eligibility or assemble its portfolio. In a scheme report, export applicable activity fields and evidence filenames/references by default. Make private reflections and original attachments selectable and keep private personal tracking out of formal totals where indicated. Review the [reporting gaps](../reporting_requirements.md) before making any product claims.

## Commercial potential, confidence and outstanding checks

Specific and defensible paid product. Main value is accurate records plus rolling verification and evidence. MyGDC handles statements and the GDC provides recording guidance. A personal log alone cannot establish compliance.

Core obligations above are supported by the linked official guidance. Field layouts are proposals. Commercial confidence is provisional without audience and purchase validation. Before approval, resolve the scope and workflow questions raised above and compare a representative draft and export with the latest regulator example or portal. Avoid assuming a rule from another profession where retention, signatures, categories or exceptions remain unverified.

## Source notes

- [D1 · CPD scheme](https://www.gdc-uk.org/education-cpd/cpd/cpd-scheme) · Hours and development outcomes. Role thresholds, five-year and consecutive two-year rules.
- [D2 · Recording and submitting CPD](https://www.gdc-uk.org/education-cpd/cpd/cpd-scheme/recording-and-submitting-cpd) · Recording, statement, evidence and audit. Provider evidence, annual declarations, rounding and retention.

## Independent check · 20 November 2026

The GDC's March 2025 improvements removed the requirement to include a GDC registration number on CPD certificates, clarified grace and restoration guidance, and describe permitted provider email evidence. Avoid making the certificate registration number a mandatory stored field. The GDC confirmed 28 January 2027 for dentists' current annual CPD statement, through MyGDC. Use a separate step for the personal development plan. [GDC process updates, March 2025](https://www.gdc-uk.org/news-blogs/news/detail/2025/03/04/gdc-announces-updates-to-cpd-processes) · [GDC dentist renewal notice, November 2026](https://www.gdc-uk.org/news-blogs/news/detail/2026/11/09/gdc-opens-annual-renewal-period-for-dentists)

The 30 October 2026 council papers show design of a future CPD model in 2027 as provisional, with development of a new scheme in 2028–30 dependent on legislation. This is a policy watch trigger. Maintain Enhanced CPD semantics until formal adoption and transition dates are known. [GDC council papers, strategic roadmap Objective 1](https://www.gdc-uk.org/docs/default-source/about-us/public-council-meeting---30-october-2026---website-30-10-2026-compressed.pdf)
