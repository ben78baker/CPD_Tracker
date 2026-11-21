# Phase 7B reporting completion and compatibility

**21 November 2026 · Internal rehearsal.** Recipient PDFs now omit the template version, reporting-rules version and regulatory review date. The same pinned details remain available in the app. The shared Western-script renderer passed the extended report and pagination checks. Offline native prototypes rendered Hindi and mixed-script documents but did not meet text-copy fidelity. Production SQLite remains disabled.

## Recipient reports and language

- Prepared report data now passes through a renderer-independent activity document. The CPD layer retains the rules, historical layout resolution and report locale. The Dart PDF backend still handles ordinary scheme PDFs. The HTML shaping comparison consumes the same prepared content.
- App report details expose the selected period’s template version, reporting-rules version and regulatory review date. An exception that prints technical details needs a reviewed professional or regulatory requirement. The NMC pilot has no such exception.
- Subtle branding remains the default. Standard branding, attribution and omission of the app brand retain their existing configuration. The practitioner, dates, activity review, evidence and relevant requirements remain in the document.
- The optional saved report language stays independent of the app language, device locale and scheme. English, French, German, Spanish, Brazilian Portuguese and Hindi remain the supported languages. Brazilian Portuguese uses `pt_BR` for report formats while retaining the saved `pt` preference. Hindi report duration units are localised independently of inherited legacy export text.
- The bundle declares its source language. When reviewed specialist translations are absent, it preserves the source terms and explains the fallback. The original user text and stored option meanings are unchanged.

[Recipient NMC report](phase7b_pilot/nmc-recipient.pdf) · [Revised UI and reporting specification](../../../docs/custom_fields_ui.md#12-report-language-and-presentation)

## Reporting and blank-page verification

The three-year fixture contains 360 activities, including three separate long entries. It checks 360 unique record markers, 204 numbered long paragraphs, a 720-character unbroken reference, a long web URL, a historical retired value, report exclusion, absent optional values, unavailable evidence and repeated references. Each attachment identity receives one evidence number. Distinct originals with the same filename remain distinguishable by number. An unavailable reference appears in the appendix without offering a stale link. Both available annotations retain their full, distinct destinations.

| Check | Result |
|---|---|
| Large report | 78 pages and 226,941 bytes. All record markers, long strings, historic text and links verified. One host test run took 404 ms with a 23.1 MiB change in process RSS between snapshots. |
| Boundary regressions | Fixtures with 1, 38, 67 and 121 body lines produced 1, 1, 2 and 3 pages. No blank or footer-only pages appeared in the boundary fixtures or the 78-page stress report. The original unwanted-page report did not include a reproducible PDF, so the result is specific to these cases. |
| Visual and text integrity | Rendered the recipient report, representative stress pages and native complex-script examples. Independently checked PDFium page text, final text, continuation headings, evidence numbering and link annotations. |
| Flutter | 237 tests passed. Static analysis retained 13 existing findings. |

[Stress report](phase7b_pilot/stress-western.pdf) · [Independent PDF checks](phase7b_pilot/render-checks.json) · [Verification script](phase7b_probes/verify_reports.py)

## Offline Hindi and mixed-script investigation

All prototype inputs were generated from the shared report content. Font resources were embedded from local Noto font bytes and the document policy blocked remote resources. The separate Chrome comparison also used an offline browser context and recorded zero external requests. It served as a comparison, not a proposed browser dependency.

| Approach | Evidence and decision |
|---|---|
| Dart PDF with an embedded font | Phase 7A already showed missing shaping with correctly embedded font data. Bundling the font alone cannot meet the acceptance case. |
| Direct HarfBuzz with Dart PDF | HarfBuzz provides the shaping engine and keeps CPD logic independent. The tested `pdf_text_shaper` 1.0.0 and 1.1.0 could not resolve with Dart 3.11.4 because the package requires Dart 3.13 or later. Its outline-plus-text-layer design also needs viewer-level validation. Consider a compatible implementation that preserves the original Unicode mapping and existing OS floors. |
| System shaping via local HTML and native print | Selected for the isolated executable prototype to assess rendering with the current Flutter toolchain and no new application package. Android used the deprecated existing print method. iOS used the isolated Objective-C bridge after the simulator incident. Correct visible conjuncts and pre-base vowel placement were checked against the earlier Core Text reference. Search, exact copy and annotations differed by backend. The approach remains unqualified for production. |
| Raster output | Can display shaped glyphs using platform layout. A raster-only PDF does not preserve the required selectable and searchable text. |
| Proposed next technical path | Keep the current shared renderer’s controls and prototype a cluster-aware, embedded Unicode text mapping backed by a compatible or pinned shaper. Qualify selection, searching, copying, wrapping, continuation headings and links across viewers on the actual supported OS floors. Retain the existing visible guard until then. |

Sources checked 21 November 2026. [HarfBuzz source and licence](https://github.com/harfbuzz/harfbuzz) · [HarfBuzz cluster handling](https://harfbuzz.github.io/clusters.html) · [Dart PDF shaper package](https://pub.dev/packages/pdf_text_shaper) · [Android print adapter](https://developer.android.com/reference/android/webkit/WebView#createPrintDocumentAdapter(java.lang.String))

### Results and release implications

| Backend | Rendering and text-layer result | Scope of measurement |
|---|---|---|
| Android API 34 | Both prototype documents rendered five pages. PDFium found all three representative Devanagari phrases, with nine matches per document. Each selected text result inserted whitespace within words. The numbered paragraphs survived extraction and both link destinations were present. | Hindi and mixed runs took 1,512 ms and 300 ms. App RSS changes were about +90.0 MiB and +0.3 MiB. |
| Android API 24 | Five pages each with visible shaped Devanagari and both annotations. Exact phrase search and copy failed. The extractor could not confirm every numbered paragraph. This was an actual API 24 run. | 610 ms and 391 ms with app RSS changes of about +25.9 MiB and +25.7 MiB. PDFs were about 133 and 130 KiB. |
| Corrected iOS 18.5 probe | Five pages each with visible shaped text and all numbered paragraphs identifiable in extracted text after whitespace normalisation. Exact phrase search and copy did not pass in PDFium. The iOS print output did not retain both web links and did not repeat the activity title consistently on continuation pages. | 740 ms and 662 ms with app RSS changes of about +6.4 MiB and −9.7 MiB. PDFs were about 74 and 66 KiB. |
| Offline headless Chrome | Five pages each. All numbered paragraphs and both links survived. Search found the phrases. PDFium’s selected text inserted additional spaces. | PDF print calls took 49 ms and 32 ms after fonts loaded. These are desktop comparison timings. |

RSS figures are before-and-after snapshots of the app process, not peak memory or the combined memory of a separate WebView renderer. Measurements came from isolated emulator or simulator debug runs on the M4 Pro host. The four static Latin and Devanagari font files used 1,589,908 bytes raw or 757,901 bytes in a deflated scratch archive. The Devanagari pair alone uses 444,960 bytes raw. These are asset measurements, not signed application download sizes. The prototype added no fonts, platform bridge or native package to the production app. Noto is licensed under SIL OFL 1.1. Keep redistribution notices with any eventual bundle. Apache-2.0 and HarfBuzz notices would also apply if the direct package were adopted. [Noto OFL notice](https://github.com/google/fonts/blob/main/ofl/notosansdevanagari/OFL.txt) · [SIL embedding guidance](https://software.sil.org/oflt/) · [Shaper licence](https://pub.dev/packages/pdf_text_shaper/license)

[Hindi on Android API 24](phase7b_pilot/android24-hindi.pdf) · [Mixed language on iOS 18.5](phase7b_pilot/ios-mixed.pdf) · [Rendered comparison](phase7b_pilot/native-shaping-comparison.png). These are diagnostic examples. Their text-layer limitations prevent release.

## Two iOS simulator crashes and their resolution

Both reports belong to `org.cpdtracker.phaseonesmoke.recordingValidation`, the temporary debug Runner, on the iOS 18.5 build 22F77 simulator. The reports have distinct causes.

- **17:28:39 GMT · SIGTRAP.** The deprecated `printing` bridge was exercised after it reported `canConvertHtml=false`. Its iOS `PrintJob.swift:277` force-unwrapped the app delegate’s window. The active Flutter scene did not provide a window through that property. The diagnostic call stack ends in that conversion path. The isolated replacement now finds the foreground scene window, handles its absence and uses a non-persistent local WebKit view.
- **17:31:00 GMT · DYLD library missing.** Xcode 27.2 build 27B52 and Swift 6.4.2 compiled the first scene-safe Swift probe against the 27.2 SDK with deployment target 15.6. Its Swift-refined `WKWebView.callAsyncJavaScript` call introduced a strong `LC_LOAD_DYLIB` for `/usr/lib/swift/libswiftWebKit.dylib` in `Runner.debug.dylib`. The iOS 18.5 loader could not resolve it before the app started. The load command and matching linked artifact identify the experimental build as the cause. The failure matches WebKit issue 293831 for Swift-refined calls on this runtime. A minimal Swift link test reproduced the overlay when calling the refined API. A WebKit import that only constructed a view linked the system framework without the overlay. The simulator contains a Cryptex symlink for the overlay, while the required normal runtime path is absent. These results identify the SDK/runtime linking boundary and the new experimental call. Clearing stale Flutter data or modifying the production minimum target would not remove it. [WebKit issue 293831](https://bugs.webkit.org/show_bug.cgi?id=293831) · [Apple framework troubleshooting](https://developer.apple.com/documentation/xcode/addressing-missing-framework-crashes)

The replacement calls the Objective-C WebKit API directly. The corrected simulator binary links system `WebKit.framework` and has no `libswiftWebKit` load. Its Mach-O minimum remains 15.6. It launched and generated both PDFs twice on the same iOS 18.5 simulator. No new Runner crash report appeared during those reruns. The temporary probe registration was then removed from the scratch Runner before the ordinary native regressions.

**Production linkage.** The production Release configuration still specifies 15.6. A fresh, representative unsigned device Release build from the current source and unchanged project configuration also reported 15.6 in its Info.plist and Mach-O build version. Its executable and all 16 inspected embedded binaries had no `libswiftWebKit` load command. The app has no production route to the deprecated conversion or the probe bridge. The two triggers are isolated to the rehearsal. An older physical device and the actual signed distribution binary were outside this verification, so their runtime qualification remains a release gate.

[Isolated Objective-C probe](phase7b_probes/IOSShapingProbe.m)

## Minimum platforms and regression results

- **Android API 24:** Installed the official Android 7.0 ARM64 default image in a scratch SDK. Both APKs passed signature verification for API 24 and had the same signer. Replaced debug version code 700, built from pre-Phase 7B source, with version code 701 using `adb install -r` and the same isolated package identity. The real legacy APIs returned two active records, including a historical record, a deleted record, active and deleted professions, the year target, display and report language settings, and profile and onboarding preferences. The captured raw preference inventory and original PDF and photo bytes matched exactly. This was a same-key debug upgrade. Production-signed upgrades and real purchase/restore entitlements remain unverified.
- **iOS 15.6:** No such simulator or available physical device was present. The iOS 18.5 corrected-probe and ordinary regression runs are reported separately. They do not fill the signed iOS 15.6 gate.
- **Ordinary native regression:** The iOS 18.5 and Android API 34 isolated builds ran scheme reports, Phase 6 scoped entitlements and draft recovery, five legacy PDF/evidence PDF/CSV/ZIP parity and migration scenarios, and the Phase 3B authority checks. The standard app continues to use legacy persistence.
- The 20-field limit remains a CPD host usability policy. The production Home, template ownership, historical layouts and existing recovery behaviour retain their approved boundaries.

## Reproduction and next decision

Baseline `c398229`. Implementation and probes are in `347b01e`. The companion documentation and evidence commit is titled “Document Phase 7B reporting evidence and the iOS incident”. The native fixtures use synthetic records. Run the Objective-C helper only in an isolated Runner with the research source and scratch font assets. The report test emits HTML inputs only when supplied with the local fixture fonts. It preserves the production app’s packaging and dependencies.

```sh
CPD_PHASE7B_ARTIFACTS=/tmp/cpd-phase7b-artifacts flutter test --no-pub test/recording_engine/phase7b_reporting_test.dart
python3 research/cpd_templates/international/phase7b_probes/verify_reports.py /tmp/cpd-phase7b-artifacts
```

**Recommendation.** Review Phase 7B before authorising Phase 8. Keep offline complex-script rendering gated because the current candidates fail exact copy or search requirements. Require signed iOS 15.6 and production-signed API 24 verification, physical accessibility, public specialised sharing and evidence parity, verified pre-migration backups, portable restore and recovery of acknowledged SQLite writes. Retain store verification, restoration and explicit template-update adoption as separate release work.
