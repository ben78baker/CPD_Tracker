# Research baseline and independent checks

**Audit date** 20 November 2026. The starting library dated 19 November held 53 targets, 14 detailed scheme reports and 39 leads. Existing scheme reports are preserved as working specifications. [Prior index](../profession_index.md) · [Older shortlist and alternatives](../commercial_priorities.md) · [Field types](../field_type_recommendations.md) · [Export gaps](../reporting_requirements.md) · [Custom Fields UI](../../../docs/custom_fields_ui.md)

## What the earlier research established

- The record is often one piece of a larger workflow. NMC revalidation includes separate reflection and confirmation, GDC combines yearly statements with a multi-year cycle, and HCPC asks selected registrants for a profile. ACCA allows an independent log, while Social Work England and ARB prescribe where official records are entered.
- Existing research proposed 6–9 active fields per initial report. It distinguished canonical activity date and duration, optional extra fields and independent per-profession branding. It treated marketed suitability and willingness to pay as unproven.
- Initial commercial candidates were NMC, GDC, HCPC and ACCA, with IET and SRA following. The prior queue left major gaps in veterinary, pharmacy, surveying, technical trades and international schemes. Official form parity, authenticated portals, competitor workflows and reachable markets were largely untested.

## Current primary-source rechecks

Each row confirms the specific point below. Coverage of all clauses, exceptions, deadlines and current official forms varies. See the [cumulative source register](../source_register.md) for publication dates and scope.

| Existing report | Point independently rechecked on 20 November 2026 | Primary source |
|---|---|---|
| NMC UK | Thirty-five hours over three years, including at least twenty with participation. | [NMC CPD requirements](https://www.nmc.org.uk/revalidation/requirements/cpd/) |
| GDC UK | At least ten verifiable hours in consecutive two-year periods, including across cycle boundaries. | [GDC CPD scheme](https://www.gdc-uk.org/education-cpd/cpd/cpd-scheme) |
| HCPC UK | A continuous record can take different formats. Learning needs a mixture and benefits should be considered. | [HCPC standards](https://www.hcpc-uk.org/standards/standards-of-continuing-professional-development/) |
| ACCA standard route | Forty units including twenty-one verifiable, with constrained carry-forward. | [ACCA CPD guide](https://www.accaglobal.com/gb/en/member/cpd/your-guide-to-cpd.html) |
| Social Work England | Portal activity form distinguishes optional per-record peer reflection from the annual requirement. | [Record CPD](https://www.socialworkengland.org.uk/cpd/record-cpd/) |
| ARB UK | MyARB and eligible RIBA recording routes constrain a standalone log. | [ARB CPD scheme](https://arb.org.uk/architect-information/cpd/) |
| SRA England and Wales | Recommended evidence includes learning needs and identification; SRA template format is optional. | [SRA recording and evaluation](https://www.sra.org.uk/solicitors/resources/continuing-competence/record-evaluate/) |
| IET and Engineering Council | IET says 30 hours for professionally active members and 10 for partially active members. The Engineering Council’s general requirement must be kept separate. | [IET CPD](https://www.theiet.org/career/professional-development/continuing-professional-development) · [Engineering Council CPD](https://www.engc.org.uk/resources-and-guidance/professional-development/continuing-professional-development-cpd) |
| ICAEW | Members can use an independent spreadsheet or employer system. | [ICAEW recording CPD](https://www.icaew.com/membership/cpd/your-guide-to-cpd/recording-cpd) |
| CORU physiotherapy | CORU audit guidance calls for 30 credits in each twelve-month period. Board-specific audit dates and current guidance status matter. | [CORU audit](https://www.coru.ie/health-and-social-care-professionals/continuing-professional-development/cpd-audit/) |
| CPA Australia | Total 120 hours per triennium and separate minimums. | [CPA Australia CPD](https://www.cpaaustralia.com.au/professional-development/continuing-professional-development) |
| NZ Nursing Council | Sixty professional-development hours in prior 36 months, distinct from practice time. | [NZ Nursing Council continuing competence](https://www.nursingcouncil.org.nz/Public/NCNZ/nursing-section/Continuing_Competence.aspx) |
| Ontario nursing | Annual reflection and plan, with different QA assessment components for selected nurses. | [CNO Quality Assurance](https://www.cno.org/quality-assurance) |
| California RN | Ordinarily 30 contact hours per two-year cycle with recognised providers. | [BRN continuing education](https://www.rn.ca.gov/licensees/ce-renewal.shtml) |

## Read-only application baseline

| Surface | Observed in the checkout | Consequence |
|---|---|---|
| Record schema and storage | Fixed CpdEntry properties and JSON list in SharedPreferences. Identifiers and duration are stored together with editable profession string, activity date, title, details and attachment references. | Dynamic values and historical layouts need a compatibility and migration design. [Model](../../../lib/models.dart) · [Repository](../../../lib/entry_repository.dart) |
| Profession state | Lists, recovery and targets use names. A rename must coordinate stored state. | Give each existing and recovered tile an immutable identity, and keep names editable. [Settings store](../../../lib/settings_store.dart) |
| Forms and search | Standard form uses branded tiles, date/duration controls and evidence selection. Search matches title, details and attachments. | Extend existing visual and local search patterns with typed values and retained choice labels. [Entry page](../../../lib/add_entry_page.dart) · [Search](../../../lib/utils/record_search.dart) |
| Export | Shared range and profession selection. Standard PDF, evidence PDF, original bundle and fixed CSV. CSV flattens details line breaks and exposes an attachment flag. | Can produce a general activity log. Structured multi-scheme output, accurate classifications and evidence pointers require deliberate versioning. [Export selection](../../../lib/utils/export_selection.dart) · [PDF](../../../lib/utils/pdf_exporter.dart) · [CSV](../../../lib/utils/csv_exporter.dart) |
| Platform | App version 1.4.1+15. No billing dependency in the inspected manifest. Local files use managed paths and native sharing. | Offline record capture is a plausible advantage. Store restoration and data transfer solve different problems. [Dependencies](../../../pubspec.yaml) · [Attachment handling](../../../lib/utils/attachment_io.dart) |

**Open at programme start** Exact regulatory revision/effective dates for some schemes, official forms and import support, exceptions and retention, independently observed competitor ergonomics, eligible population by sub-route and paid conversion. Existing planning assumptions on prices, access and the active-field cap are kept fixed throughout the programme.
