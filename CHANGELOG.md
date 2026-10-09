# CPD Tracker – Change Log

## v1.3.0 — Enhanced PDF and Evidence Exports
**Date:** October 2026

- Improved professional PDF reports with clearer activity and evidence presentation.
- Added PDF exports with embedded photographic and documentary evidence.
- Added dedicated photographic evidence pages that preserve the complete image.
- Added document rendering so attached PDF evidence appears within the report.
- Original attachments are included alongside the report only when required.
- Improved export and sharing reliability across the available formats.

## v1.0.0-beta — Pre-Release Polishing Milestone  
**Date:** November 2025  

This release marks the first polished and feature-complete build of **CPD Tracker**, prepared for international rollout and TestFlight beta testing.

### ✨ New Features
- **Profession Management**
  - Add, rename, and delete professions with dynamic syncing across entries.
  - Profession cards include quick actions for new entries, record viewing, and target setting.

- **CPD Entry Logging**
  - Capture title, description, hours/minutes, and notes.
  - Optional QR scan autofill for certificates.
  - Supports photo, document, and link attachments.

- **Target Progress Tracking**
  - Set custom time targets (weekly, monthly, yearly) per profession.
  - Real-time progress updates after saving entries.
  - Automatically adapts to user’s chosen week start day (Monday/Sunday/Saturday).

- **Week Start Preference**
  - User can choose start of week during onboarding and modify later via Home → Menu → “Set Week Start Day”.

- **Attachment Handling**
  - Local thumbnails display in-app.
  - “Share All” generates a ZIP with folders per record.
  - PDF exports show inline attachments (PDF-only) or reference ZIP bundle (PDF + bundle).

- **Export & Sharing**
  - Export CPD records to professional-format PDF.
  - Select custom date ranges for sharing.
  - Includes total CPD time and per-record breakdowns.

- **Onboarding Flow**
  - Simplified setup screen with Name, Company, Email, First Profession, and Week Start.
  - Optional fields are clearly marked.

### 🧭 Improvements & Polishing
- Cleaner layout for profession targets and progress bars.
- Reduced clutter with dropdowns replacing radio buttons where appropriate.
- Consistent typography and spacing for multi-record PDFs.
- Automatic refresh of targets and totals after adding new entries.
- Smart locale handling for default week start and date formats.

### 🐛 Fixes
- Corrected “Share All” attachment behavior to prevent duplicates.
- Fixed missing “Do not show again” preference for QR certificate prompts.
- Adjusted “PDF + Bundle” mode to avoid inline attachments duplication.
- Fixed iOS context warnings and deprecated widget usage under Flutter 3.35.

### ⚙️ Technical Updates
- Updated for **Flutter 3.35.6 / Dart 3.9.2** compatibility.
- Clean `flutter analyze` (0 issues).
- Fully functional iOS build environment with Xcode integration.
- Added GitHub release tag: `v1.0.0-beta`.

---

**Next Milestone:**
> Final release (v1.0.0) – App Store submission readiness, localized onboarding, and automated backup/sync.
