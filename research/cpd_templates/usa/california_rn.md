# California RN continuing education log

**Jurisdiction** United States · California  
**Scope** Board of Registered Nursing · active RN renewal  
**Recommendation** Suitable with contact-hour and provider validation guidance.  
**Status** Research specification for review · 20 November 2026.

## Executive summary and official requirements

Active RNs ordinarily need 30 contact hours per two-year renewal period from recognised providers. Provider status matters, and repeat identical courses in a cycle count once. The first two years of initial licensure have an exception to the ordinary CE requirement, but one hour of direct participation in approved implicit-bias training is required during that period. Other exemptions and advanced practice rules need separate handling. [BRN regulatory approval effective 1 July 2024](https://www.rn.ca.gov/pdfs/regulations/approval-1452-2.pdf) The ordinary requirements centre on eligible courses and proof. No reflection or PDP requirement was established for the standard route. [U1 · Continuing Education for License Renewal](https://www.rn.ca.gov/licensees/ce-renewal.shtml)

## Evidence, official systems and reporting

Retain certificates or grade slips for four years. BRN conducts random audits. Store course name, provider and completion details for renewal and use official provider verification. Distinguish contact hours from elapsed minutes and avoid converting provider credits without an approved rule. Keep renewal declarations and exceptions out of individual records. [U1 · Continuing Education for License Renewal](https://www.rn.ca.gov/licensees/ce-renewal.shtml)

## Proposed individual record

**8 active fields** including the standard bindings listed below. M is mandatory for the indicated scheme or submission, C is conditional, R is recommended and O is optional. Where a regulator specifies an outcome without prescribing columns, the fields are product recommendations. M/C checks should surface when marking a record ready or preparing a scheme export, with incomplete historical data remaining editable. Show all rows for eligible records unless conditional, and omit blank optional values from PDF. Export rule exceptions appear below.

| Field | Type | Class | Purpose | Standard binding | Proposed validation | Reporting |
|---|---|---|---|---|---|---|
| Course completion date | Date | M | Determine renewal window | date | completed date | period |
| Course name | Text | M | Identify activity | title | nonblank | deduplication aid |
| Course content and objective | Long text | R | Support relevance and identify repeats | details | brief summary | deduplication aid |
| Provider name | Text | M | Identify issuer | New | nonblank for claimed hours | Detail only |
| Provider approval identifier | Text | R | Support recognised provider verification | New | preserve leading zeros; allow alternate provider routes | Detail only |
| Elapsed duration | Duration | O | Preserve tracker duration semantics | duration | do not infer qualifying credit | personal only |
| Contact hours awarded | Decimal | M | Use exact qualifying provider figure | New | nonnegative; eligibility user-confirmed | contact-hour total |
| Proof of completion | File | M | Retain certificate or grade slip | evidence | retain authentic proof or external reference | Detail only |

The specification derives from [U1 · Continuing Education for License Renewal](https://www.rn.ca.gov/licensees/ce-renewal.shtml). The types and validation wording are design recommendations. Choice, multi-choice and decimal inputs require separate feature approval.

## App fit and export boundary

The current app has one canonical activity date and duration, title, details, and general evidence. Standard bindings preserve those semantics. Existing PDF, PDF with evidence and CSV work from a profession and date selection and do not calculate this scheme’s eligibility or assemble its portfolio. In a scheme report, export applicable activity fields and evidence filenames/references by default. Make private reflections and original attachments selectable and keep private personal tracking out of formal totals where indicated. Review the [reporting gaps](../reporting_requirements.md) before making any product claims.

## Commercial potential, confidence and outstanding checks

Clear evidence structure and feasible state-specific companion. Validate willingness to pay and competitor availability. An all-US nursing layout would obscure state variation.

Core obligations above are supported by the linked official guidance. Field layouts are proposals. Commercial confidence is provisional without audience and purchase validation. Before approval, resolve the scope and workflow questions raised above and compare a representative draft and export with the latest regulator example or portal. Avoid assuming a rule from another profession where retention, signatures, categories or exceptions remain unverified.

## Source notes

- [U1 · Continuing Education for License Renewal](https://www.rn.ca.gov/licensees/ce-renewal.shtml) · Eligibility, audits, exceptions. 30 contact hours, recognised providers and four-year evidence.

- [BRN final regulatory approval](https://www.rn.ca.gov/pdfs/regulations/approval-1452-2.pdf) · Checked 20 November 2026. First-licensure implicit-bias exception and effective date.
