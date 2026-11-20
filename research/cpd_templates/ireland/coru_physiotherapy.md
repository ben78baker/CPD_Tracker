# CORU physiotherapist CPD audit companion

**Jurisdiction** Ireland  
**Scope** Physiotherapists Registration Board · CORU  
**Recommendation** Suitable with credit, planning and portal-copy features.  
**Status** Research specification for review · 19 November 2026.

## Executive summary and official requirements

The Board Code requires keeping knowledge and skills current. CORU’s audit guidance asks sampled registrants to evidence at least 30 CPD credits per 12-month period, with profession-specific audit periods. Audit covers learning planning, implementation and evaluation/reflection. The editable record is an optional working tool. Audit submission uses the registrant portal; the working form can be copied into it. [I1 · Continuing Professional Development](https://www.coru.ie/health-and-social-care-professionals/continuing-professional-development/) · [I2 · CPD for Physiotherapists](https://www.coru.ie/health-and-social-care-professionals/continuing-professional-development/cpd-for-physiotherapists/) · [I3 · CPD Audit](https://www.coru.ie/health-and-social-care-professionals/continuing-professional-development/cpd-audit/)

## Evidence, official systems and reporting

Capture learning achieved and link it to the plan. Determine acceptable evidence and precise credit allocation from the current Board guidance before automatic totals. No per-activity supervisor signature or separate retention period was established. Guidance linked from the profession page uses a draft filename; confirm status and the current template before making stronger claims. [I1 · Continuing Professional Development](https://www.coru.ie/health-and-social-care-professionals/continuing-professional-development/) · [I2 · CPD for Physiotherapists](https://www.coru.ie/health-and-social-care-professionals/continuing-professional-development/cpd-for-physiotherapists/) · [I3 · CPD Audit](https://www.coru.ie/health-and-social-care-professionals/continuing-professional-development/cpd-audit/)

## Proposed individual record

**8 active fields** including the standard bindings listed below. M is mandatory for the indicated scheme or submission, C is conditional, R is recommended and O is optional. Where a regulator specifies an outcome without prescribing columns, the fields are product recommendations. M/C checks should surface when marking a record ready or preparing a scheme export, with incomplete historical data remaining editable. Show all rows for eligible records unless conditional, and omit blank optional values from PDF. Export rule exceptions appear below.

| Field | Type | Class | Purpose | Standard binding | Proposed validation | Reporting |
|---|---|---|---|---|---|---|
| Activity date | Date | R | Identify audit-period activity | date | completed date | period |
| Activity title | Text | R | Identify learning | title | short label | Detail only |
| Activity and relevance | Long text | R | Describe relevant development | details | avoid identifiable patient data | Detail only |
| Learning need | Text | R | Link to personal plan | New | allow link to planned objective | Detail only |
| Learning achieved and evaluation | Long text | R | Explain enhanced learning and implications | New | own reflection | Detail only |
| CORU credits | Decimal | R | Record self-assessed eligible credit separately | New | nonnegative; validate credit basis before automation | credit total |
| Supporting material | File | O | Preserve local supporting documentation | evidence | omit from portal export unless accepted | Detail only |
| Elapsed time | Duration | O | Personal time tracking | duration | do not convert automatically | personal only |

The specification derives from [I1 · Continuing Professional Development](https://www.coru.ie/health-and-social-care-professionals/continuing-professional-development/) and [I2 · CPD for Physiotherapists](https://www.coru.ie/health-and-social-care-professionals/continuing-professional-development/cpd-for-physiotherapists/) and [I3 · CPD Audit](https://www.coru.ie/health-and-social-care-professionals/continuing-professional-development/cpd-audit/). The types and validation wording are design recommendations. Choice, multi-choice and decimal inputs require separate feature approval.

## App fit and export boundary

The current app has one canonical activity date and duration, title, details, and general evidence. Standard bindings preserve those semantics. Existing PDF, PDF with evidence and CSV work from a profession and date selection and do not calculate this scheme’s eligibility or assemble its portfolio. In a scheme report, export applicable activity fields and evidence filenames/references by default. Make private reflections and original attachments selectable and keep private personal tracking out of formal totals where indicated. Review the [reporting gaps](../reporting_requirements.md) before making any product claims.

## Commercial potential, confidence and outstanding checks

Good localised extension of an allied health library, but the credit and portal workflow differs materially from HCPC. Validate the reachable Irish physiotherapist population and audit preparation burden.

Core obligations above are supported by the linked official guidance. Field layouts are proposals. Commercial confidence is provisional without audience and purchase validation. Before approval, resolve the scope and workflow questions raised above and compare a representative draft and export with the latest regulator example or portal. Avoid assuming a rule from another profession where retention, signatures, categories or exceptions remain unverified.

## Source notes

- [I1 · Continuing Professional Development](https://www.coru.ie/health-and-social-care-professionals/continuing-professional-development/) · Profession-specific audit resources. Board-specific schemes and examples.
- [I2 · CPD for Physiotherapists](https://www.coru.ie/health-and-social-care-professionals/continuing-professional-development/cpd-for-physiotherapists/) · Exemplars and audit. Physiotherapy-specific guidance and Code obligation.
- [I3 · CPD Audit](https://www.coru.ie/health-and-social-care-professionals/continuing-professional-development/cpd-audit/) · CORU CPD Record and audit periods. 30 credits in 12 months, audit-only portal recording and planning/reflection.
