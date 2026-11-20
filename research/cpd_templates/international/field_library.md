# Field Library catalogue

**60 research definitions** · 20 November 2026. The [JSON catalogue](field_library.json) contains the complete candidate records, source metadata and controlled-choice drafts. It is documentation for review, separate from runtime schema and template content. All defaults are blank so inserting a field cannot imply attendance, verifiability or completion. Keep portfolio definitions out of ordinary Add Field.

Search should match exact label, aliases, descriptions and terminology across all categories. Offer category and optional scheme/jurisdiction filters without requiring nested navigation. Search terms such as `certificate`, `contact hours` and `participatory` should surface related records with their scope badges. Rank exact and synonym matches above category matches. For a regulator-bound result, preview the scope, effective choice vocabulary and source before insertion. [Visual editor specification](../../../docs/custom_fields_ui.md)

**Deduplication rule.** Reuse concepts when purpose, value and reporting meaning match. For example, one activity date and provider name can be shared. Use one duration primitive for credited minutes and duration subsets, but keep NMC participation and CPA Australia ethics as independent semantics. For ACCA, derive units from eligible minutes under its one-hour rule. CORU credits and California contact hours are separately recorded exact quantities. Classifications share controls but each scheme owns its definition of eligibility. A local field copy keeps effective settings and provenance. Template rules and reporting remain separate from library insertion.

**Usage key** M source-backed requirement for the indicated context; C conditional or portfolio-level; R recommended; O optional. Confirm role, exact official form and applicability before using any proposed field in a paid product. Use the [source register](../source_register.md) and the named source references in the JSON.

## Activity details

| Stable ID | Label | Type | Scope and status | Delivery |
|---|---|---|---|---|
| `activity.title` | Activity title | short text | SRA R · NMC R · HCPC R · CA_RN M · GDC M | entry |
| `activity.date` | Activity date | date | NMC M · GDC M · SWE M · CA_RN M · NZ_NURSING M | entry |
| `activity.start_date` | Activity start date | date | NMC C · NZ_NURSING C | entry |
| `activity.description` | Activity description | long text | NMC M · HCPC R · ACCA R · SWE M · GDC M | entry |
| `activity.provider` | Learning provider | short text | GDC R · CA_RN M · CPA_AU R | entry |
| `activity.method` | Learning method | short text | NMC M · IET R | entry |
| `activity.hcpc_category` | HCPC learning category | single select | HCPC R | phase candidate |
| `activity.swe_type` | Social Work England activity type | single select | SWE M | review |
| `activity.ciob_learning_format` | CIOB learning format | single select | CIOB R | phase candidate |
| `activity.niceic_work_scope` | Electrical work or training scope | short text | NICEIC R | entry |
| `activity.gphc_planned` | GPhC planned or unplanned learning | single select | GPHC M | phase candidate |
| `activity.lbp_stream` | Skills maintenance stream | single select | LBP M | review |

## Assessment and verification

| Stable ID | Label | Type | Scope and status | Delivery |
|---|---|---|---|---|
| `activity.provider_id` | Provider approval reference | short text | CA_RN R | entry |
| `activity.awarded_reference` | Course or certificate reference | short text | GDC O · CA_RN O | entry |
| `time.verifiability` | Verifiability | single select | ACCA C · ICAEW R | phase candidate |
| `time.gdc_evidence_state` | GDC evidence eligibility | single select | GDC R | phase candidate |
| `time.formality` | Formal learning classification | single select | RICS C · CII C | review |
| `verification.checklist` | Review confirmations | boolean | SWE C | review |
| `evidence.redaction_review` | Evidence redaction reviewed | boolean | HCPC R · SWE C · GPHC R | portfolio |

## Learning objectives

| Stable ID | Label | Type | Scope and status | Delivery |
|---|---|---|---|---|
| `learning.objective` | Learning objective | long text | GDC R · IET R | entry |
| `learning.relevance` | Relevance to my practice | long text | NMC M · SWE M · HCPC R · ACCA C · ICAEW R | entry |

## Professional development planning

| Stable ID | Label | Type | Scope and status | Delivery |
|---|---|---|---|---|
| `learning.need` | Learning need and how identified | long text | SRA R · CNO R · ACCA C · ICAEW R | entry |
| `learning.plan_reference` | Development plan reference | short text | GDC R · IET R · CNO R · CORU R | entry |
| `outcome.follow_up` | Follow-up action | long text | SRA R · IET R · CNO R · ICAEW R | entry |
| `outcome.review_date` | Review date | date | CNO O · SRA O | review |

## Learning and reflection

| Stable ID | Label | Type | Scope and status | Delivery |
|---|---|---|---|---|
| `learning.outcome` | What I learned | long text | SWE M · ACCA C · IET R · CORU R | entry |
| `learning.peer_reflection` | Peer reflection | long text | SWE C | entry |
| `learning.reflective_account_link` | Reflective account reference | short text | NMC O | entry |

## Professional practice outcomes

| Stable ID | Label | Type | Scope and status | Delivery |
|---|---|---|---|---|
| `outcome.practice_impact` | Impact on professional practice | long text | HCPC R · ACCA C · SRA R · SWE M | entry |
| `outcome.service_user_impact` | Benefit to service users | long text | HCPC R · SWE C | entry |

## Time and credits

| Stable ID | Label | Type | Scope and status | Delivery |
|---|---|---|---|---|
| `time.credited_minutes` | Credited CPD duration | duration | NMC M · GDC M · ACCA M · IET C · NZ_NURSING M | entry |
| `time.participatory_minutes` | Participatory CPD time | duration | NMC M | phase candidate |
| `time.ethics_minutes` | Ethics CPD time | duration | CPA_AU C · ICAEW R | phase candidate |
| `time.coru_credits` | CORU credits claimed | decimal | CORU C | phase candidate |
| `time.ca_contact_hours` | California RN contact hours | decimal | CA_RN M | phase candidate |
| `activity.cii_structured` | CII structured CPD classification | single select | CII M | phase candidate |
| `time.verified_minutes` | Verifiable CPD time | duration | CPAO C | phase candidate |
| `time.verified_ethics_minutes` | Verifiable professional ethics time | duration | CPAO C | review |
| `time.mcle_awarded` | California MCLE awarded credit | decimal | CALBAR M | review |
| `time.mcle_subfield_allocations` | MCLE subfield credit allocation | allocation | CALBAR C | review |
| `time.snb_points_claimed` | Singapore CPE points claimed | decimal | SNB C | review |
| `time.snb_points_awarded` | Singapore CPE points awarded | decimal | SNB C | review |

## Regulatory declarations

| Stable ID | Label | Type | Scope and status | Delivery |
|---|---|---|---|---|
| `time.annual_credit_adjustment` | Prior-year credit carried forward | decimal | ACCA C | portfolio |
| `verification.confirmation_reference` | Independent verification reference | short text | NMC C · NZ_NURSING C | portfolio |
| `verification.renewal_declaration` | Renewal declaration status | single select | GDC C · ACCA C · CNO C · NZ_NURSING C | portfolio |

## Professional standards and competencies

| Stable ID | Label | Type | Scope and status | Delivery |
|---|---|---|---|---|
| `standards.nmc_code` | Relevant part of the NMC Code | multi select | NMC M | phase candidate |
| `standards.gdc_outcomes` | GDC development outcomes | multi select | GDC M | phase candidate |
| `standards.swe` | Social Work England CPD standards | multi select | SWE M | review |
| `standards.nz_pou` | Relevant Nursing Council pou | single select | NZ_NURSING M | review |
| `standards.arb_topic` | ARB mandatory topic | multi select | ARB R | review |
| `standards.reference` | Competency reference | short text | IET O · HCPC O | entry |
| `activity.ciob_theme` | CIOB learning theme | single select | CIOB C | phase candidate |
| `standards.gphc` | GPhC reflective account standard | single select | GPHC C | portfolio |
| `standards.nsw_aitsl` | Australian teaching standards addressed | multi select | NSW M | review |
| `standards.malta_core` | Malta accountancy CPE category | single select | MTA C | review |

## Evidence and attachments

| Stable ID | Label | Type | Scope and status | Delivery |
|---|---|---|---|---|
| `evidence.files` | Supporting evidence | file | NMC M · GDC C · ACCA C · CA_RN M · HCPC R | entry |
| `evidence.photo` | Evidence photograph | photo | NMC O · HCPC O | entry |
| `evidence.external_reference` | External evidence reference | short text | NMC C · ACCA C · HCPC R | entry |
| `evidence.url` | Evidence URL | url | HCPC O · ACCA O | review |
| `evidence.additional_reflection` | Additional reflection document | file | SWE O | entry |
