# Phase 8 portable backup and write recovery

Status on 21 November 2026. Internal rehearsal on `feature/recording-engine`. Production continues to use its existing storage and recovery paths.

**Product direction updated 22 November 2026.** The whole-store replacement flow and per-save recovery copies below describe the historical rehearsal. The approved public direction is free, user-managed profession backup and additive restoration. [Current assessment and proposed protocol](phase8_profession_backup_assessment.md)

## Recording format and coverage

Version 1 is a single `.recordingbackup` file. The first eight ASCII bytes are `RECBAK01`. A four-byte big-endian unsigned length precedes the UTF-8 JSON manifest. The manifest carries a UTC creation date, backup and SQLite schema versions, and an ordered list of payload names, byte lengths and SHA-256 digests. Its first payload is `rows.ndjson`. Remaining payloads contain original evidence bytes without recompression. The reader verifies the exact file length, the manifest fingerprint the user reviewed and every payload fingerprint. An internal version-1 reader accepts SQLite logical schema 4. A future reader needs an explicit, tested converter before accepting other schema versions.

The SQLite adapter exports table rows in foreign-key order and preserves insertion order within each table. It rebuilds the destination from trusted SQL and bound values. It never opens a SQLite binary supplied by the archive. Coverage includes active and deleted collections and records, field definitions, retired values, attachment relationships and original files, independent placements, pinned template/layout revisions, report configuration, periods, targets, preferences, legacy preservation chunks and migration provenance already in the recording store. An already unresolved evidence reference remains visible as such. A managed original missing or changed during capture blocks publication. Unreferenced files outside the managed graph, caches, derived PDFs and operating-system settings belong to separate inventories.

The CPD adapter retains the validated template recipe and reporting-rule envelope during adoption. It verifies the saved record of each adoption and the rules referenced by retained periods. Restored historical calculations can obtain that exact envelope without an installed catalogue. An older rehearsal database missing an envelope needs an exact pinned-version backfill or recovery review. No current bundle is inferred to be the historical version. Archived envelopes are historical data. A future externally distributed catalogue still needs authenticity, compatibility, provenance and explicit adoption checks before activation.

Purchase grants, legacy paid-app grants, purchase attempt state and the authoritative installation handoff are excluded from portable CPD export and ignored by portable import. Verified purchases and legacy eligibility must be restored through the CPD application layer. The internal recovery copy can preserve installation-local state, but its API is separate from the file picker, and its authority remains bound to the local fence.

Manifest bounds are 8 MiB, 20,000 entries including the row stream, 64 GiB aggregate payload and 16 MiB per encoded row. Evidence manifest names follow a restricted flat syntax. Original destinations are relative to a fresh originals directory. Checks reject traversal, aliases, unexpected entries, duplicate row identities and incompatible versions. Extraction streams bounded chunks. The SQL candidate is assessed for structural integrity, FK coverage and coherence between the recording graph and evidence manifest. Storage is checked before staging and again during creation; a failed operation leaves the prior workspace in place. Process termination can leave unpublished temporary directories. Treat them as untrusted scratch and review cleanup separately.

## Authority and verified replacement

| Copy | Role |
| --- | --- |
| Active recording workspace | The host owns the only active write path. Native SQLite uses rollback journalling and `synchronous=FULL` in the protected rehearsal. Evidence originals are flushed before records refer to them. |
| Acknowledged-write checkpoint | After the pending fence, each host mutation must finish and its independent logical checkpoint must verify before the external fence advances and the caller receives success. A missing or inconsistent fence, a higher unpublished checkpoint, missing evidence or changed live data blocks further writes. The last acknowledgement can be rebuilt into a separate workspace. |
| Pre-migration legacy recovery copy | Quiesces legacy writes, independently copies source preferences and evidence and compares them with the live source. Phase 8 rechecks after the staging checkpoint and before opening SQLite. Failure or unresolved status preserves the snapshot and legacy originals. |
| User-portable file | Explicitly created or selected by a user. It can be inspected and rebuilt in an isolated directory. The local owner, verified existing recovery copy and explicit confirmation are prerequisites for preparing a replacement. |

The protected store currently takes a complete checkpoint per acknowledged operation. This is the reference guarantee for the rehearsal. A failure after the SQL commit leaves that data in the live workspace and holds authority for review. Recovery can inspect the last acknowledgement without replacing the potentially newer live workspace. No conflict merge or automatic rewind is implemented. Restored candidates have no production authority. SQLite documents transaction durability under its VFS and filesystem assumptions. Portable files and authority use flushed files and same-volume rename. Dart does not provide the explicit directory barriers needed to claim resilience to sudden device power loss. Same-volume recovery cannot survive loss of that volume. [SQLite atomic commit](https://www.sqlite.org/atomiccommit.html) · [SQLite synchronous modes](https://www.sqlite.org/pragma.html#pragma_synchronous)

Complete per-write copies grow with every save. They require a single exclusive host writer and temporarily require space for the comparison, row stream and next checkpoint. This is unsuitable for broad production rollout on evidence-heavy installations as implemented. The current product direction retires per-save recovery copies from the future production path. Its review covers SQLite journalling and original-file publication. Preserve the existing 30-day minimum for migration recovery beginning only after verified activation. There is no automatic deletion of legacy originals or uncertain snapshots.

## Workflow and privacy

The internal page uses the existing branded header, form surfaces, tactile actions and accessible focus behavior. It explains the contents and plaintext exposure, creates a verified copy, and offers native sharing. Restore selects a file through the system picker, privately validates a candidate, then shows its creation time, original-evidence count and verification outcome. The replacement consequence appears before the destructive-looking confirmation. Cancel keeps the current history. On confirmation the synthetic host checks the independent current copy and prepares a verified replacement for review. It leaves current records available. Busy operations block duplicate taps. Low space and unsupported versions have distinct feedback. The UI resolves all six app locales and eight accents.

SHA-256 detects alteration and accidental corruption. A party able to edit a plaintext archive can also recompute its digests, so these fingerprints confer neither authenticity nor purchase rights. Phase 8 uses the previously resolved `crypto` package for SHA-256 and adds no encryption mechanism. A public workflow needs an explicit choice about passphrase protection and the policy for exchanging unencrypted files. Native file protection helps while records are app-private, and system pickers/share sheets enable user-directed copies. Neither protects a file after the user sends it to another destination. Verify provider caching, sensitive temporary-file exclusion from OS backup, protection classes and lifecycle cleanup on real devices. [Apple app file protection](https://developer.apple.com/documentation/uikit/encrypting-your-app-s-files) · [Android Storage Access Framework](https://developer.android.com/training/data-storage/shared/documents-files)

For portable encryption, prefer a separately versioned, authenticated streaming envelope after review. Assess Argon2id parameters on API 24 and iOS 15.6, authenticated chunk ordering and truncation protection, recovery codes versus no password reset, and what happens to shared files if the passphrase is lost. NIST specifies AES-GCM for authenticated encryption. The Dart `cryptography` package lists Argon2id and AES-GCM under Apache-2.0; that is a candidate for review, with dependency and streaming design still to qualify. An installation-bound Keychain or Keystore key could protect local snapshots but would prevent independent recovery if used as the only portable key. Keep the decision reversible until approved. [RFC 9106, September 2021](https://www.rfc-editor.org/rfc/rfc9106.html) · [NIST SP 800-38D](https://csrc.nist.gov/pubs/sp/800/38/d/final) · [Dart cryptography package](https://pub.dev/packages/cryptography). Sources checked 21 November 2026.

## Validation and release decisions

See the verification results below. Keep SQLite production activation disabled. Use the [profession backup assessment](phase8_profession_backup_assessment.md) for the current protocol and pending approvals, including the public encryption decision. Keep the approved initial model of bundled templates unlocked by verified store purchase, with externally distributed, validated bundles as a later option. No remote distribution or compulsory online backup was added.

All Phase 7B release gates remain open. They include faithful offline complex-script PDF rendering with exact Unicode search, selection and copying; signed upgrade and runtime on iOS 15.6; production-signed Android API 24 upgrades; physical-device accessibility; public specialised sharing, printing and evidence export parity; and verified purchases and restoration. Six app languages, independent report locale and the explicit unsupported-renderer guard remain in place. Further complex-script experiments are deferred.

## Rehearsal results

The full Flutter suite passed 251 tests. Full static analysis reported the same 13 pre-existing warnings and informational findings, including the untracked marketing output. Phase 8 introduced no analyzer findings. Tests cover truncated, modified and appended files, malicious names and size declarations, future format versions, case aliases, same-destination creation races, insufficient storage, changing the reviewed source file and the confirmation and cancellation paths. Narrow-screen widgets exercised six locales across eight accents at 170% text scale.

Native debug targets ran against iOS 18.5 on an iPhone 16 Pro simulator and Android API 24 and API 34 emulators on an Apple M4 Pro. The native runner exercised the non-CPD equipment fixture, old controlled values and deleted identities, physical database and evidence corruption, missing evidence, genuine SQLite uniqueness errors, a forged legacy grant, and restoration of a verified legacy projection with preserved original evidence. The CPD fixture also preserved independent placements, history, reporting-rule envelopes and separate app and report locales. A 52,780-byte backup containing a PDF, a photograph and another managed original travelled each way between iOS and Android API 24. Both imports independently verified the transferred manifests and rebuilt their recording workspaces without accessing the issuing application's sandbox or catalogue.

On iOS and Android API 24, the harness stopped the native app after the SQLite commit and before the acknowledgement checkpoint. Restart held authority, rebuilt the last acknowledgement in a separate workspace and confirmed the newer transaction still existed in the interrupted live workspace. The attempt exercised process termination and app restart. Sudden power loss, interrupted removable storage and the full range of document providers remain unverified. Insufficient capacity was injected at the copy boundary. It did not publish any output, and the staged current data remained intact. Phase 8 did not fill the test devices' system volumes.

The iOS migration runner passed the native authority suite. Corrupting the pre-migration manifest at the staging checkpoint blocked import before SQLite opened and left the legacy original available. The scaled migration runner passed 32-, 420- and 3,600-record cases with six professions, mixed evidence, recovery review, historical records and oversized legacy payload transfer. At 3,600 records it verified 144 originals, took 18.0 s, used 99.2 MB of additional disk space at peak and produced an 8.39 MB database. The debug runner sampled about 726 MB RSS at peak. Its separate 20-record PDF took 28 ms and the CSV took 377 ms. The 233 ms scratch first frame is a rehearsal measurement. Production startup has no new copy or migration work.

### Portable scale sample

These timings include SHA-256 and logical graph verification. The fixture has 2,000 records in eight equipment collections and 56 one-MiB managed originals. The archive was 60,168,731 bytes and the SQLite store was about 1.65 MB on each platform. RSS is the larger of the samples taken after creation and restore, including the debug Flutter runtime. Treat these as development measurements.

| Debug target | Create and verify | Restore and verify | Sampled RSS |
| --- | ---: | ---: | ---: |
| iOS 18.5 | 1.27 s | 1.15 s | 648 MB |
| Android API 24 | 1.33 s | 2.44 s | 366 MB |
| Android API 34 | 3.07 s | 4.36 s | 409 MB |

### Visual evidence

The Android rehearsal opened the native share sheet for a generated backup. It also selected the iOS-created file in the Android Downloads provider, reverified it, and displayed the successful preparation of a separate candidate after explicit confirmation. The iOS screenshot covers the localized rehearsal entry screen. End-to-end iOS Files provider export and import are still to qualify.

- [iOS 18.5 · French, indigo](phase8_rehearsal/ios-backup-fr.png)
- [Android API 34 · verified copy](phase8_rehearsal/android-verified-backup.png)
- [Android API 34 · replacement confirmation](phase8_rehearsal/android-restore-confirmation.png)
- [Android API 34 · verified restore candidate](phase8_rehearsal/android-verified-candidate.png)

iOS 15.6 was unavailable as a runnable simulator or connected device. Debug Android API 24 runtime verification does not cover the production signing key or a public upgrade. Production signing, minimum OS versions, activation settings and normal application navigation were preserved.

The implementation and repeatable probes are in commit `0bcad4639650af67113877dd563c6f3f6f72e4d0`.
