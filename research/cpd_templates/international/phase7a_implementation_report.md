# Phase 7A presentation review

**21 November 2026 · Internal rehearsal.** The refined profession UI uses the production Home shell. The shared PDF now supports an independent language choice and recipient-controlled branding. The nursing and midwifery pilot remains the sole profession template. Production SQLite remains disabled.

## Home and reporting periods

| Review finding | Refinement |
|---|---|
| The Phase 7 rehearsal supplied a plain app bar, a top-level Add Profession button and a bounded list. The production Home supplied the app icon, branded title, search, overflow menu and full-width list insets. | Extracted the production chrome and list layout into `HomeShell` and `HomeProfessionList`. Both hosts use them. The production Home keeps its existing search, menu, storage, ordering and navigation callbacks. In the rehearsal, Add Profession is back in the overflow menu. The mock reference and SQLite demo intentionally show different synthetic professions. |
| The Phase 7 cards already reused the production shell of each individual card. Nursing repeated the eligibility description and drew thinner bars. | Standard CPD keeps its existing controls, spacing and target path. The nursing progress area uses the same 10-point progress-bar treatment with two independently named measures, a shared eligibility caption and a wrapping period action. The deadline and review count can share a line. |
| The earlier screen mixed saved and new periods and gave version numbers prominence without explaining them. | Saved periods and Add a period have distinct actions. Text and a check icon identify the selected window. Period details show the deadline and labelled template and rule versions. Reselecting a historical period requires confirmation. The editor uses the existing branded section, tactile buttons and disabled treatment. |
| English dates used month-first formatting even for the UK pilot. | UK English uses day-first formatting on the card, picker and in reports. US English remains a report option. The published Standard CPD date setting still applies when the report uses its inherited defaults. |

The underlying period store, period bounds, eligibility calculations and historical pins are the Phase 7 ones. No storage cutover or template adoption changes were required.

**Visual comparisons.** The production reference uses the actual Home widget with mock legacy preferences under an isolated debug identity. The SQLite rehearsal uses synthetic records. Its camera and unrelated management menu actions are simulated. Public navigation continues to use the current production handlers.

- [Android production, Phase 7 and refined Home](phase7a_pilot/home-android.png)
- [iOS production and refined Home](phase7a_pilot/home-ios.png)
- [Standard CPD and nursing cards side by side](phase7a_pilot/standard-and-nursing.png)
- [Previous period screen, saved periods and historical details](phase7a_pilot/periods-before-after.png)
- [English application and French report preview](phase7a_pilot/report-language.png)

## PDF, report language and branding

The existing production PDF informed the palette, small identity mark and continuation treatment. The Phase 6 NMC example informed the reporting content. The shared renderer now uses a labelled table for targets and recorded, complete and eligible totals. A compact date and duration treatment leaves space for full-width activities. The activity heading repeats when a record continues. Inline field labels keep values associated with their labels. A short evidence index can fit inline and a longer one gets its own section. Reference links remain clickable and source attachment files remain independent. PDF bytes are generated on demand.

[Before-and-after PDF first pages](phase7a_pilot/pdf-before-after.png)

**Independent language.** In the current checkout the Standard CPD export sheet used the application language and display date format. It had no independent report-language control. Phase 7A adds an optional row to that sheet and shares the picker with the rehearsal for Standard, custom and profession-specific reports. Confirming an export saves the choice separately from app language. The pre-purchase fixture uses the chosen preference without requiring any change to real records or entitlements. Existing users inherit the previous Standard CPD PDF messages and date behaviour until they choose an explicit language. CSV keeps its existing structure and date preference.

For an explicit locale, the report formats headings, available template labels, dates, numbers and durations. The scheme country supplies metadata only. Original text, identifiers and controlled choices retain their saved meaning. The French fixture deliberately omits one translation and shows the source label and fallback notice. The five-page fixture includes French, Spanish and German user text in a French report and preserves it as entered.

| Recipient option | Verified example |
|---|---|
| Standard | [French report with the app name and small logo](phase7a_pilot/standard-fr.pdf). The source-language note and missing-translation fallback are visible. |
| Subtle | [UK English report with a quiet footer and subdued accent](phase7a_pilot/subtle-en-GB.pdf). The representative three-activity log now fits on one page. |
| Attribution | [German report with localised discreet attribution](phase7a_pilot/attribution-de.pdf). |
| No app branding | [Unbranded US English report](phase7a_pilot/none-en-US.pdf). Verification found no app identity in the generated document. |
| Continuations and evidence | [French multi-page report with original multilingual text](phase7a_pilot/multilingual-continuations.pdf). It has five pages, an unavailable-evidence warning and a clickable reference. |

The NMC bundle defaults to subtle branding. The alternatives are synthetic presentation fixtures. Recipient rules take priority over brand preferences, and application branding conveys no regulatory endorsement. The separate per-profession organisation logo remains a planned capability.

## The 20-active-field policy

The earlier product decision set 20 as the centrally enforced CPD maximum, including active standard bindings. Its practical justification is manageable mobile forms, field editing and report review. No repository, SQLite schema or rendering boundary at 20 was found. The generic engine stores field values as rows and accepts an optional limit from its host. A 21-field equipment inspection fixture passed the generic codec and failed with the CPD host policy applied. This is evidence of a product boundary, not a throughput benchmark.

Retain 20 for CPD. Retired historical fields, headings and report assets remain outside the count. A future General Record Keeping app can choose a different host limit after testing long forms, search, export density, accessibility and larger mixed attachment collections. Changing the CPD limit would require a separate product decision and corresponding boundary regression tests. [CPD policy](../../../lib/cpd_compatibility/cpd_layout_policy.dart) · [Generic codec](../../../lib/recording_engine/template_review.dart) · [Repository](../../../lib/recording_engine_storage/sqlite_recording_repository.dart)

## Offline Hindi PDF feasibility

Embedding a Devanagari font solves glyph coverage. The renderer also needs Unicode script detection, OpenType substitution and positioning, and correct shaping through line breaks. A scratch probe used the same Noto Sans Devanagari TTF in Dart PDF and in an offline macOS Core Text PDF. The font-only Dart output misplaced vowels and rendered conjuncts incorrectly. Core Text produced 22 positioned glyphs from 30 code points for the first line and drew both mixed-script lines with the expected shaping. This is a one-page feasibility observation on macOS. It does not qualify a production renderer, pagination or extraction on iOS and Android. [Shaping comparison](phase7a_pilot/hindi-shaping.png)

| Item | Finding |
|---|---|
| Licence and embedding | Noto Sans Devanagari is available under SIL OFL 1.1. Bundle the notices with distributed font files. Embedding a subset in a report is supported under the font licence. |
| Measured font cost | The static regular and bold files measured 219,212 and 225,748 bytes respectively, 444,960 bytes together. A deflated scratch ZIP used 189,285 bytes. These figures describe the samples. Measure signed app download and installed size separately. |
| Current renderer | The installed Dart PDF stack can embed the font, but the visual probe exposed a shaping failure. The new shared report surfaces an explicit error for Devanagari text even in a report written in another language. Explicit Hindi selection in legacy PDF export surfaces the same limitation. The pre-existing default export path remains available. |
| Recommended approach | Prototype an offline HarfBuzz-backed shaped-text path within the existing shared renderer, using pinned Noto static assets. Keep compatible glyph-to-Unicode mapping for selection, searching and copying. Verify mixed-script lines, line breaking across clusters, wrapping, fallback fonts, evidence links and extraction. Test paragraphs on a cold offline install at both minimum OS versions. |
| Alternative | Compare native shaping and PDF output through the platforms if a cross-platform shaper cannot meet binary size, glyph mapping or build constraints. A raster-only fallback would give up selectable text and can increase PDF size. Reserve it for a separately approved exception. |

No font binaries or shaping dependency were added to the app. The scratch fonts were read offline after retrieval. The existing Latin report font provider still attempts its current font acquisition and can fall back to built-in fonts. Cold offline coverage for all supported languages and full script/font fidelity remain release work. [Noto font sources](https://github.com/notofonts/noto-fonts/tree/main/hinted/ttf/NotoSansDevanagari) · [Noto OFL notice](https://github.com/google/fonts/blob/main/ofl/notosansdevanagari/OFL.txt) · [SIL embedding guidance](https://software.sil.org/oflt/) · [HarfBuzz shaping clusters](https://harfbuzz.github.io/clusters.html) · [Dart PDF Indic shaping issue](https://github.com/DavBfr/dart_pdf/issues/1907)

## Verification

| Check | Result |
|---|---|
| Flutter regression suite | **230 passed.** The nine additional tests cover language independence, UK/US ordering and numbers, persistence, Standard PDF formatting, the export chooser and shared Home, four brand policies, missing translations, long multilingual reports, Devanagari detection and host-specific field limits. The card suite exercised all six app locales and eight colours at 320 logical pixels and 1.85× text scale. |
| Static analysis | **13 existing findings**, down from 16 in Phase 7. No new findings. |
| Native rehearsal | iPhone 16 Pro simulator on iOS 18.5 and Pixel 6 emulator on Android 14/API 34. Both passed the native scheme checks, independent app/report locale persistence, Phase 6 creation and entitlement regressions, five legacy parity scenarios and Phase 3B authority/recovery. |
| Visual and export inspection | Compared the actual production Home and refined rehearsal on both available platforms. Opened saved period details and selected French from the English app on Android. Rendered and inspected all four branding samples and the multilingual fixture. Verified all 170 observations, the final original-language sentence, continuation headings on pages 2–5, the unavailable evidence label and the live URI annotation. |
| Boundaries | Debug fixtures used isolated synthetic data. Real stores, migrations, purchase configuration and production releases were outside the rehearsal. Exact iOS 15.6 and Android API 24 environments and physical-device assistive-technology testing remain unverified. |

The font-backed PDF fixture can be reproduced with the test target and a scratch output directory. Set `CPD_PHASE7A_FONTS` to an approved local test font directory containing `Latin-Regular.ttf` and `Latin-Bold.ttf` for the reviewed Western-script rendering.

```sh
CPD_PHASE7A_ARTIFACTS=/tmp/cpd-phase7a-pdfs flutter test --no-pub test/recording_engine/phase7a_presentation_test.dart
flutter run --no-pub -d <test-device> --dart-define=PHASE7A_REFERENCE=true -t test/recording_engine/phase7_rehearsal_app.dart
flutter run --no-pub -d <test-device> --dart-define=PHASE7_SAMPLES=true -t test/recording_engine/phase7_rehearsal_app.dart
```

## Roadmap and release gates

Review the presentation and PDF evidence before authorising Phase 8. Continue to require portable backup and restore, recovery that covers every acknowledged SQLite write, verified independent pre-migration backup for existing users, signed upgrades on iOS 15.6 and Android API 24, and physical-device accessibility. Public specialised sharing, printing and evidence/conditional ZIP parity require their own qualification. Store verification and restoration, the manual owner-managed legacy grant process, and explicit template-update adoption remain separate work. Keep all source records and originals recoverable throughout.

The next reporting experiment is offline shaping with a selectable Unicode layer. Keep production cutover disabled while the recovery and reporting release gates remain open.
