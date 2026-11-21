import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_hi.dart';
import 'app_localizations_pt.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('hi'),
    Locale('pt'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'CPD Progress Tracker'**
  String get appTitle;

  /// No description provided for @homeTitle.
  ///
  /// In en, this message translates to:
  /// **'Your Professions'**
  String get homeTitle;

  /// No description provided for @addNew.
  ///
  /// In en, this message translates to:
  /// **'Add New'**
  String get addNew;

  /// No description provided for @newEntry.
  ///
  /// In en, this message translates to:
  /// **'New Entry'**
  String get newEntry;

  /// No description provided for @scanQrCode.
  ///
  /// In en, this message translates to:
  /// **'Scan QR Code'**
  String get scanQrCode;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @menuTooltip.
  ///
  /// In en, this message translates to:
  /// **'Menu'**
  String get menuTooltip;

  /// No description provided for @tipsRestored.
  ///
  /// In en, this message translates to:
  /// **'Tips restored'**
  String get tipsRestored;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @settingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Personalise your app preferences'**
  String get settingsSubtitle;

  /// No description provided for @appColour.
  ///
  /// In en, this message translates to:
  /// **'App colour'**
  String get appColour;

  /// No description provided for @chooseYourAppColour.
  ///
  /// In en, this message translates to:
  /// **'Choose your app colour'**
  String get chooseYourAppColour;

  /// No description provided for @resetTipsDescription.
  ///
  /// In en, this message translates to:
  /// **'Show helpful tips again'**
  String get resetTipsDescription;

  /// No description provided for @colourPurple.
  ///
  /// In en, this message translates to:
  /// **'Purple'**
  String get colourPurple;

  /// No description provided for @colourBlue.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get colourBlue;

  /// No description provided for @colourTeal.
  ///
  /// In en, this message translates to:
  /// **'Teal'**
  String get colourTeal;

  /// No description provided for @colourGreen.
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get colourGreen;

  /// No description provided for @colourOrange.
  ///
  /// In en, this message translates to:
  /// **'Orange'**
  String get colourOrange;

  /// No description provided for @colourRed.
  ///
  /// In en, this message translates to:
  /// **'Red'**
  String get colourRed;

  /// No description provided for @colourPink.
  ///
  /// In en, this message translates to:
  /// **'Pink'**
  String get colourPink;

  /// No description provided for @colourIndigo.
  ///
  /// In en, this message translates to:
  /// **'Indigo'**
  String get colourIndigo;

  /// No description provided for @addProfession.
  ///
  /// In en, this message translates to:
  /// **'Add Profession'**
  String get addProfession;

  /// No description provided for @editPersonalDetails.
  ///
  /// In en, this message translates to:
  /// **'Edit Personal Details'**
  String get editPersonalDetails;

  /// No description provided for @setWeekStartDay.
  ///
  /// In en, this message translates to:
  /// **'Set Week Start Day'**
  String get setWeekStartDay;

  /// No description provided for @resetTips.
  ///
  /// In en, this message translates to:
  /// **'Reset Tips'**
  String get resetTips;

  /// No description provided for @viewDeletedProfessions.
  ///
  /// In en, this message translates to:
  /// **'View Deleted Professions'**
  String get viewDeletedProfessions;

  /// No description provided for @noProfessionsYet.
  ///
  /// In en, this message translates to:
  /// **'No professions yet. Use menu → Add Profession.'**
  String get noProfessionsYet;

  /// No description provided for @renameProfession.
  ///
  /// In en, this message translates to:
  /// **'Rename Profession'**
  String get renameProfession;

  /// No description provided for @deleteProfession.
  ///
  /// In en, this message translates to:
  /// **'Delete Profession'**
  String get deleteProfession;

  /// No description provided for @addEntry.
  ///
  /// In en, this message translates to:
  /// **'Add Entry'**
  String get addEntry;

  /// No description provided for @scanQr.
  ///
  /// In en, this message translates to:
  /// **'Scan QR'**
  String get scanQr;

  /// No description provided for @viewRecords.
  ///
  /// In en, this message translates to:
  /// **'View Records'**
  String get viewRecords;

  /// No description provided for @setEditTarget.
  ///
  /// In en, this message translates to:
  /// **'Set/Edit Target'**
  String get setEditTarget;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @weekStartUpdated.
  ///
  /// In en, this message translates to:
  /// **'Week start updated'**
  String get weekStartUpdated;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @followSystemLanguage.
  ///
  /// In en, this message translates to:
  /// **'Follow system language'**
  String get followSystemLanguage;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @french.
  ///
  /// In en, this message translates to:
  /// **'French'**
  String get french;

  /// No description provided for @german.
  ///
  /// In en, this message translates to:
  /// **'German'**
  String get german;

  /// No description provided for @spanish.
  ///
  /// In en, this message translates to:
  /// **'Spanish'**
  String get spanish;

  /// No description provided for @portuguese.
  ///
  /// In en, this message translates to:
  /// **'Portuguese (Brazil)'**
  String get portuguese;

  /// No description provided for @hindi.
  ///
  /// In en, this message translates to:
  /// **'हिंदी'**
  String get hindi;

  /// No description provided for @welcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome'**
  String get welcome;

  /// No description provided for @setupYourDetails.
  ///
  /// In en, this message translates to:
  /// **'Set up your details'**
  String get setupYourDetails;

  /// No description provided for @nameOptional.
  ///
  /// In en, this message translates to:
  /// **'Name (optional)'**
  String get nameOptional;

  /// No description provided for @companyOptional.
  ///
  /// In en, this message translates to:
  /// **'Company (optional)'**
  String get companyOptional;

  /// No description provided for @addressOptional.
  ///
  /// In en, this message translates to:
  /// **'Address (optional)'**
  String get addressOptional;

  /// No description provided for @emailOptional.
  ///
  /// In en, this message translates to:
  /// **'Email (optional)'**
  String get emailOptional;

  /// No description provided for @enterValidEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email'**
  String get enterValidEmail;

  /// No description provided for @firstProfessionRequired.
  ///
  /// In en, this message translates to:
  /// **'First Profession (required)'**
  String get firstProfessionRequired;

  /// No description provided for @professionExample.
  ///
  /// In en, this message translates to:
  /// **'e.g. Electrician'**
  String get professionExample;

  /// No description provided for @enterProfession.
  ///
  /// In en, this message translates to:
  /// **'Please enter a profession'**
  String get enterProfession;

  /// No description provided for @weekStartsOn.
  ///
  /// In en, this message translates to:
  /// **'Week starts on'**
  String get weekStartsOn;

  /// No description provided for @useDeviceLocaleRecommended.
  ///
  /// In en, this message translates to:
  /// **'Use device locale (recommended)'**
  String get useDeviceLocaleRecommended;

  /// No description provided for @monday.
  ///
  /// In en, this message translates to:
  /// **'Monday'**
  String get monday;

  /// No description provided for @sunday.
  ///
  /// In en, this message translates to:
  /// **'Sunday'**
  String get sunday;

  /// No description provided for @saturday.
  ///
  /// In en, this message translates to:
  /// **'Saturday'**
  String get saturday;

  /// No description provided for @continueLabel.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueLabel;

  /// No description provided for @savedLocallyNotice.
  ///
  /// In en, this message translates to:
  /// **'Saved locally. Some settings may sync on next launch.'**
  String get savedLocallyNotice;

  /// No description provided for @detectedDownloadableFile.
  ///
  /// In en, this message translates to:
  /// **'Detected a downloadable file link'**
  String get detectedDownloadableFile;

  /// No description provided for @whatWouldYouLikeToDo.
  ///
  /// In en, this message translates to:
  /// **'What would you like to do?'**
  String get whatWouldYouLikeToDo;

  /// No description provided for @attachToEntry.
  ///
  /// In en, this message translates to:
  /// **'Attach to this entry'**
  String get attachToEntry;

  /// No description provided for @downloadAndSave.
  ///
  /// In en, this message translates to:
  /// **'Download and save to Attachments'**
  String get downloadAndSave;

  /// No description provided for @openLink.
  ///
  /// In en, this message translates to:
  /// **'Open link'**
  String get openLink;

  /// No description provided for @keepAsUrlOnly.
  ///
  /// In en, this message translates to:
  /// **'Keep as URL only'**
  String get keepAsUrlOnly;

  /// No description provided for @qrCertificateReminder.
  ///
  /// In en, this message translates to:
  /// **'To receive any CPD certificate please follow the link from the scanned QR code at your leisure and add the certificate to this record.'**
  String get qrCertificateReminder;

  /// No description provided for @dontShowAgain.
  ///
  /// In en, this message translates to:
  /// **'Don\'t show this message again'**
  String get dontShowAgain;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @couldNotSaveDetails.
  ///
  /// In en, this message translates to:
  /// **'Could not save details. Please try again.'**
  String get couldNotSaveDetails;

  /// No description provided for @restoreRecordTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore record?'**
  String get restoreRecordTitle;

  /// No description provided for @deleteRecordTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete record?'**
  String get deleteRecordTitle;

  /// No description provided for @restoreRecordConfirm.
  ///
  /// In en, this message translates to:
  /// **'Do you want to restore this record?'**
  String get restoreRecordConfirm;

  /// No description provided for @deleteRecordConfirm.
  ///
  /// In en, this message translates to:
  /// **'Do you want to delete this record?'**
  String get deleteRecordConfirm;

  /// No description provided for @restore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restore;

  /// No description provided for @cpdLinkSubject.
  ///
  /// In en, this message translates to:
  /// **'CPD link'**
  String get cpdLinkSubject;

  /// No description provided for @cpdAttachmentSubject.
  ///
  /// In en, this message translates to:
  /// **'CPD attachment'**
  String get cpdAttachmentSubject;

  /// No description provided for @fileNotFound.
  ///
  /// In en, this message translates to:
  /// **'File not found.'**
  String get fileNotFound;

  /// No description provided for @shareFailed.
  ///
  /// In en, this message translates to:
  /// **'Share failed'**
  String get shareFailed;

  /// No description provided for @noRecordsInSelectedPeriod.
  ///
  /// In en, this message translates to:
  /// **'No records in the selected period.'**
  String get noRecordsInSelectedPeriod;

  /// No description provided for @exportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed'**
  String get exportFailed;

  /// No description provided for @periodLabel.
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get periodLabel;

  /// No description provided for @noCpdRecordsYet.
  ///
  /// In en, this message translates to:
  /// **'No CPD records yet.'**
  String get noCpdRecordsYet;

  /// No description provided for @attachments.
  ///
  /// In en, this message translates to:
  /// **'Attachments'**
  String get attachments;

  /// No description provided for @attachmentRemoved.
  ///
  /// In en, this message translates to:
  /// **'Attachment removed.'**
  String get attachmentRemoved;

  /// No description provided for @shareExport.
  ///
  /// In en, this message translates to:
  /// **'Share / Export'**
  String get shareExport;

  /// No description provided for @futureDateNotAllowedTitle.
  ///
  /// In en, this message translates to:
  /// **'Future date not allowed'**
  String get futureDateNotAllowedTitle;

  /// No description provided for @futureDateNotAllowedBody.
  ///
  /// In en, this message translates to:
  /// **'You can only add CPD entries dated today or earlier.'**
  String get futureDateNotAllowedBody;

  /// No description provided for @takePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take photo'**
  String get takePhoto;

  /// No description provided for @photoLibrary.
  ///
  /// In en, this message translates to:
  /// **'Photo library'**
  String get photoLibrary;

  /// No description provided for @chooseFile.
  ///
  /// In en, this message translates to:
  /// **'Choose file'**
  String get chooseFile;

  /// No description provided for @noQrDataCaptured.
  ///
  /// In en, this message translates to:
  /// **'No QR data captured.'**
  String get noQrDataCaptured;

  /// No description provided for @attachmentFailed.
  ///
  /// In en, this message translates to:
  /// **'Attachment failed'**
  String get attachmentFailed;

  /// No description provided for @enterTitleOrDetails.
  ///
  /// In en, this message translates to:
  /// **'Please enter a title or details.'**
  String get enterTitleOrDetails;

  /// No description provided for @entryUpdated.
  ///
  /// In en, this message translates to:
  /// **'Entry updated'**
  String get entryUpdated;

  /// No description provided for @entrySaved.
  ///
  /// In en, this message translates to:
  /// **'Entry saved'**
  String get entrySaved;

  /// No description provided for @editEntry.
  ///
  /// In en, this message translates to:
  /// **'Edit Entry'**
  String get editEntry;

  /// No description provided for @professionLabel.
  ///
  /// In en, this message translates to:
  /// **'Profession'**
  String get professionLabel;

  /// No description provided for @dateLabel.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get dateLabel;

  /// No description provided for @titleLabel.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get titleLabel;

  /// No description provided for @enterTitle.
  ///
  /// In en, this message translates to:
  /// **'Please enter a title'**
  String get enterTitle;

  /// No description provided for @detailsLabel.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get detailsLabel;

  /// No description provided for @timeLabel.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get timeLabel;

  /// No description provided for @attachmentsEvidence.
  ///
  /// In en, this message translates to:
  /// **'Attachments (evidence)'**
  String get attachmentsEvidence;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @noAttachmentsAdded.
  ///
  /// In en, this message translates to:
  /// **'No attachments added.'**
  String get noAttachmentsAdded;

  /// No description provided for @removeAttachmentTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove attachment?'**
  String get removeAttachmentTitle;

  /// No description provided for @removeAttachmentBody.
  ///
  /// In en, this message translates to:
  /// **'Do you want to remove this attachment?'**
  String get removeAttachmentBody;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @saveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save Changes'**
  String get saveChanges;

  /// No description provided for @saveEntry.
  ///
  /// In en, this message translates to:
  /// **'Save Entry'**
  String get saveEntry;

  /// No description provided for @attachmentsNote.
  ///
  /// In en, this message translates to:
  /// **'Note: Attachments are saved in the app. Choose PDF with evidence to embed supported photos and PDF pages, or PDF + original attachments (ZIP) to share original files.'**
  String get attachmentsNote;

  /// No description provided for @csvEditable.
  ///
  /// In en, this message translates to:
  /// **'CSV (editable)'**
  String get csvEditable;

  /// No description provided for @pdfReadOnly.
  ///
  /// In en, this message translates to:
  /// **'PDF (read-only)'**
  String get pdfReadOnly;

  /// No description provided for @pdfWithoutEvidence.
  ///
  /// In en, this message translates to:
  /// **'PDF without embedded evidence'**
  String get pdfWithoutEvidence;

  /// No description provided for @pdfWithoutEvidenceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Professional record with an evidence list'**
  String get pdfWithoutEvidenceSubtitle;

  /// No description provided for @pdfWithEvidence.
  ///
  /// In en, this message translates to:
  /// **'PDF with evidence'**
  String get pdfWithEvidence;

  /// No description provided for @pdfWithEvidenceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Adds supported photos and PDF pages on dedicated evidence pages'**
  String get pdfWithEvidenceSubtitle;

  /// No description provided for @pdfEvidenceOriginalsNoticeTitle.
  ///
  /// In en, this message translates to:
  /// **'Original evidence included'**
  String get pdfEvidenceOriginalsNoticeTitle;

  /// No description provided for @pdfEvidenceOriginalsNoticeBody.
  ///
  /// In en, this message translates to:
  /// **'Some evidence files cannot be displayed within the PDF. Their original files will be included in an accompanying ZIP archive.'**
  String get pdfEvidenceOriginalsNoticeBody;

  /// No description provided for @pdfAttachmentsBundle.
  ///
  /// In en, this message translates to:
  /// **'PDF + original attachments (ZIP)'**
  String get pdfAttachmentsBundle;

  /// No description provided for @pdfAttachmentsBundleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Text-only PDF and original supporting files'**
  String get pdfAttachmentsBundleSubtitle;

  /// No description provided for @noTitle.
  ///
  /// In en, this message translates to:
  /// **'(No title)'**
  String get noTitle;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @shareAllAttachments.
  ///
  /// In en, this message translates to:
  /// **'Share all attachments'**
  String get shareAllAttachments;

  /// No description provided for @zeroMinutes.
  ///
  /// In en, this message translates to:
  /// **'0m'**
  String get zeroMinutes;

  /// No description provided for @attachmentsCount.
  ///
  /// In en, this message translates to:
  /// **'Attachments ({count})'**
  String attachmentsCount(int count);

  /// No description provided for @hoursPlural.
  ///
  /// In en, this message translates to:
  /// **'{count,plural, =1{{count} hour} other{{count} hours}}'**
  String hoursPlural(int count);

  /// No description provided for @minutesPlural.
  ///
  /// In en, this message translates to:
  /// **'{count,plural, =1{{count} minute} other{{count} minutes}}'**
  String minutesPlural(int count);

  /// No description provided for @shareAll.
  ///
  /// In en, this message translates to:
  /// **'Share All'**
  String get shareAll;

  /// No description provided for @selectPeriod.
  ///
  /// In en, this message translates to:
  /// **'Select Period'**
  String get selectPeriod;

  /// No description provided for @fromLabel.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get fromLabel;

  /// No description provided for @toLabel.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get toLabel;

  /// No description provided for @hoursLabel.
  ///
  /// In en, this message translates to:
  /// **'Hours'**
  String get hoursLabel;

  /// No description provided for @minutesLabel.
  ///
  /// In en, this message translates to:
  /// **'Minutes'**
  String get minutesLabel;

  /// No description provided for @required.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get required;

  /// No description provided for @numbersOnly.
  ///
  /// In en, this message translates to:
  /// **'Numbers only'**
  String get numbersOnly;

  /// No description provided for @mustBeZeroOrMore.
  ///
  /// In en, this message translates to:
  /// **'Must be ≥ 0'**
  String get mustBeZeroOrMore;

  /// No description provided for @tooLarge.
  ///
  /// In en, this message translates to:
  /// **'Too large'**
  String get tooLarge;

  /// No description provided for @zeroToFiftyNine.
  ///
  /// In en, this message translates to:
  /// **'0–59'**
  String get zeroToFiftyNine;

  /// No description provided for @selectDate.
  ///
  /// In en, this message translates to:
  /// **'Select date'**
  String get selectDate;

  /// No description provided for @noItemsAdded.
  ///
  /// In en, this message translates to:
  /// **'No items have been added.'**
  String get noItemsAdded;

  /// No description provided for @link.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get link;

  /// No description provided for @imageAttachment.
  ///
  /// In en, this message translates to:
  /// **'Image attachment'**
  String get imageAttachment;

  /// No description provided for @fileAttachment.
  ///
  /// In en, this message translates to:
  /// **'File attachment'**
  String get fileAttachment;

  /// No description provided for @shareThisAttachment.
  ///
  /// In en, this message translates to:
  /// **'Share this attachment'**
  String get shareThisAttachment;

  /// No description provided for @allTime.
  ///
  /// In en, this message translates to:
  /// **'All time'**
  String get allTime;

  /// No description provided for @toWord.
  ///
  /// In en, this message translates to:
  /// **'to'**
  String get toWord;

  /// No description provided for @pageOf.
  ///
  /// In en, this message translates to:
  /// **'Page {page} of {total}'**
  String pageOf(int page, int total);

  /// No description provided for @cpdRecordsTitle.
  ///
  /// In en, this message translates to:
  /// **'CPD Records'**
  String get cpdRecordsTitle;

  /// No description provided for @cpdPdfDocumentTitle.
  ///
  /// In en, this message translates to:
  /// **'Continuing Professional Development Record'**
  String get cpdPdfDocumentTitle;

  /// No description provided for @cpdPdfDurationLabel.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get cpdPdfDurationLabel;

  /// No description provided for @cpdPdfEvidenceResourcesLabel.
  ///
  /// In en, this message translates to:
  /// **'Evidence / Resources'**
  String get cpdPdfEvidenceResourcesLabel;

  /// No description provided for @cpdPdfContinuedTitle.
  ///
  /// In en, this message translates to:
  /// **'{title} - continued'**
  String cpdPdfContinuedTitle(Object title);

  /// No description provided for @cpdPdfWebLinkLabel.
  ///
  /// In en, this message translates to:
  /// **'Web link'**
  String get cpdPdfWebLinkLabel;

  /// No description provided for @cpdPdfEmailLinkLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get cpdPdfEmailLinkLabel;

  /// No description provided for @cpdPdfTelephoneLinkLabel.
  ///
  /// In en, this message translates to:
  /// **'Telephone'**
  String get cpdPdfTelephoneLinkLabel;

  /// No description provided for @cpdPdfPhotoEvidenceLabel.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get cpdPdfPhotoEvidenceLabel;

  /// No description provided for @cpdPdfPhotographicEvidenceLabel.
  ///
  /// In en, this message translates to:
  /// **'Photographic Evidence'**
  String get cpdPdfPhotographicEvidenceLabel;

  /// No description provided for @cpdPdfDocumentEvidenceLabel.
  ///
  /// In en, this message translates to:
  /// **'PDF document'**
  String get cpdPdfDocumentEvidenceLabel;

  /// No description provided for @cpdPdfDocumentaryEvidenceLabel.
  ///
  /// In en, this message translates to:
  /// **'Documentary Evidence'**
  String get cpdPdfDocumentaryEvidenceLabel;

  /// No description provided for @cpdPdfPagesShownBelow.
  ///
  /// In en, this message translates to:
  /// **'{filename} - {count,plural, =1{1 page shown below} other{{count} pages shown below}}'**
  String cpdPdfPagesShownBelow(Object filename, int count);

  /// No description provided for @cpdPdfSourcePage.
  ///
  /// In en, this message translates to:
  /// **'Source page {page} of {total}'**
  String cpdPdfSourcePage(int page, int total);

  /// No description provided for @cpdPdfUnableToRenderOriginalInZipWithName.
  ///
  /// In en, this message translates to:
  /// **'{filename} - Unable to render; original file in accompanying ZIP'**
  String cpdPdfUnableToRenderOriginalInZipWithName(Object filename);

  /// No description provided for @cpdPdfUnsupportedImageWithName.
  ///
  /// In en, this message translates to:
  /// **'Unsupported image: {filename}'**
  String cpdPdfUnsupportedImageWithName(Object filename);

  /// No description provided for @cpdPdfFileEvidenceLabel.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get cpdPdfFileEvidenceLabel;

  /// No description provided for @cpdPdfOriginalFileInZipWithName.
  ///
  /// In en, this message translates to:
  /// **'{filename} - Original file in accompanying ZIP'**
  String cpdPdfOriginalFileInZipWithName(Object filename);

  /// No description provided for @cpdPdfUnavailableEvidenceLabel.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get cpdPdfUnavailableEvidenceLabel;

  /// No description provided for @nameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get nameLabel;

  /// No description provided for @companyLabel.
  ///
  /// In en, this message translates to:
  /// **'Company'**
  String get companyLabel;

  /// No description provided for @emailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get emailLabel;

  /// No description provided for @totalTimeLabel.
  ///
  /// In en, this message translates to:
  /// **'Total Time'**
  String get totalTimeLabel;

  /// No description provided for @attachmentsEvidenceLabel.
  ///
  /// In en, this message translates to:
  /// **'Attachments / Evidence:'**
  String get attachmentsEvidenceLabel;

  /// No description provided for @attachmentsInlineNotePdf.
  ///
  /// In en, this message translates to:
  /// **'Attachments/Evidence available on request'**
  String get attachmentsInlineNotePdf;

  /// No description provided for @attachmentsInlineNoteZip.
  ///
  /// In en, this message translates to:
  /// **'For Attachments & Evidence see ZIP File'**
  String get attachmentsInlineNoteZip;

  /// No description provided for @cpdRecordsShareSubject.
  ///
  /// In en, this message translates to:
  /// **'CPD records'**
  String get cpdRecordsShareSubject;

  /// No description provided for @cpdRecordsBundleShareSubject.
  ///
  /// In en, this message translates to:
  /// **'CPD records bundle'**
  String get cpdRecordsBundleShareSubject;

  /// No description provided for @attachmentLinksTitle.
  ///
  /// In en, this message translates to:
  /// **'CPD Attachment Links'**
  String get attachmentLinksTitle;

  /// No description provided for @linksFileName.
  ///
  /// In en, this message translates to:
  /// **'links.txt'**
  String get linksFileName;

  /// No description provided for @csvNoAttachmentsInExport.
  ///
  /// In en, this message translates to:
  /// **'None in this export'**
  String get csvNoAttachmentsInExport;

  /// No description provided for @csvDateHeader.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get csvDateHeader;

  /// No description provided for @csvTitleHeader.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get csvTitleHeader;

  /// No description provided for @csvHasAttachmentsHeader.
  ///
  /// In en, this message translates to:
  /// **'Has Attachments'**
  String get csvHasAttachmentsHeader;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @csvRecordsWithAttachments.
  ///
  /// In en, this message translates to:
  /// **'{count,plural, =1{{count} record includes attachments; available upon request} other{{count} records include attachments; available upon request}}'**
  String csvRecordsWithAttachments(int count);

  /// No description provided for @cpdEntriesShareSubject.
  ///
  /// In en, this message translates to:
  /// **'CPD entries for {profession}'**
  String cpdEntriesShareSubject(Object profession);

  /// No description provided for @cpdEntriesShareText.
  ///
  /// In en, this message translates to:
  /// **'CPD entries for {profession} ({from} to {to}) — Total {hours}h {minutes}m'**
  String cpdEntriesShareText(
    Object profession,
    Object from,
    Object to,
    int hours,
    int minutes,
  );

  /// No description provided for @couldNotOpenLink.
  ///
  /// In en, this message translates to:
  /// **'Could not open link.'**
  String get couldNotOpenLink;

  /// No description provided for @noAppToOpenLink.
  ///
  /// In en, this message translates to:
  /// **'No app available to open link.'**
  String get noAppToOpenLink;

  /// No description provided for @cantOpenThisFile.
  ///
  /// In en, this message translates to:
  /// **'Can\'t open this file ({message}).'**
  String cantOpenThisFile(Object message);

  /// No description provided for @openFailed.
  ///
  /// In en, this message translates to:
  /// **'Open failed'**
  String get openFailed;

  /// No description provided for @savedToAttachments.
  ///
  /// In en, this message translates to:
  /// **'Saved to Attachments: {filename}'**
  String savedToAttachments(Object filename);

  /// No description provided for @attachmentNotFoundOnDevice.
  ///
  /// In en, this message translates to:
  /// **'Attachment not found on device.'**
  String get attachmentNotFoundOnDevice;

  /// No description provided for @importFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed'**
  String get importFailed;

  /// No description provided for @downloadFailedStatus.
  ///
  /// In en, this message translates to:
  /// **'Download failed ({status}).'**
  String downloadFailedStatus(int status);

  /// No description provided for @downloadError.
  ///
  /// In en, this message translates to:
  /// **'Download error'**
  String get downloadError;

  /// No description provided for @cpdAttachmentBundleTitle.
  ///
  /// In en, this message translates to:
  /// **'CPD Attachment Bundle'**
  String get cpdAttachmentBundleTitle;

  /// No description provided for @includedFiles.
  ///
  /// In en, this message translates to:
  /// **'Included files:'**
  String get includedFiles;

  /// No description provided for @includedFilesNone.
  ///
  /// In en, this message translates to:
  /// **'Included files: (none)'**
  String get includedFilesNone;

  /// No description provided for @links.
  ///
  /// In en, this message translates to:
  /// **'Links:'**
  String get links;

  /// No description provided for @linksNone.
  ///
  /// In en, this message translates to:
  /// **'Links: (none)'**
  String get linksNone;

  /// No description provided for @cpdAttachmentsShareSubject.
  ///
  /// In en, this message translates to:
  /// **'CPD attachments • {profession} • {date}'**
  String cpdAttachmentsShareSubject(Object profession, Object date);

  /// No description provided for @attachmentsForTitleBody.
  ///
  /// In en, this message translates to:
  /// **'Attachments for \"{title}\" ({profession}).'**
  String attachmentsForTitleBody(Object title, Object profession);

  /// No description provided for @attachmentsForTitleWithLinksBody.
  ///
  /// In en, this message translates to:
  /// **'Attachments for \"{title}\" ({profession}). Links included in manifest.'**
  String attachmentsForTitleWithLinksBody(Object title, Object profession);

  /// No description provided for @fileNotFoundWithName.
  ///
  /// In en, this message translates to:
  /// **'File not found: {filename}'**
  String fileNotFoundWithName(Object filename);

  /// No description provided for @unableToOpenAttachment.
  ///
  /// In en, this message translates to:
  /// **'Unable to open attachment'**
  String get unableToOpenAttachment;

  /// No description provided for @exportFilePrefix.
  ///
  /// In en, this message translates to:
  /// **'cpd_records'**
  String get exportFilePrefix;

  /// No description provided for @deletedProfessionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Deleted Professions'**
  String get deletedProfessionsTitle;

  /// No description provided for @noDeletedProfessions.
  ///
  /// In en, this message translates to:
  /// **'No deleted professions'**
  String get noDeletedProfessions;

  /// No description provided for @deletePermanently.
  ///
  /// In en, this message translates to:
  /// **'Delete Permanently'**
  String get deletePermanently;

  /// No description provided for @professionRestored.
  ///
  /// In en, this message translates to:
  /// **'Profession restored'**
  String get professionRestored;

  /// No description provided for @permanentlyDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete?'**
  String get permanentlyDeleteTitle;

  /// No description provided for @permanentlyDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\" and all its records? This cannot be undone.'**
  String permanentlyDeleteBody(Object name);

  /// No description provided for @professionDeletedPermanently.
  ///
  /// In en, this message translates to:
  /// **'Deleted \"{name}\" permanently (records not yet removed)'**
  String professionDeletedPermanently(Object name);

  /// No description provided for @thisWeek.
  ///
  /// In en, this message translates to:
  /// **'this week'**
  String get thisWeek;

  /// No description provided for @thisMonth.
  ///
  /// In en, this message translates to:
  /// **'this month'**
  String get thisMonth;

  /// No description provided for @thisYear.
  ///
  /// In en, this message translates to:
  /// **'this year'**
  String get thisYear;

  /// No description provided for @targetAchieved.
  ///
  /// In en, this message translates to:
  /// **'Target achieved {cycle} 🎉'**
  String targetAchieved(Object cycle);

  /// No description provided for @timeRemaining.
  ///
  /// In en, this message translates to:
  /// **'{hours} hrs, {minutes} mins remaining {cycle}'**
  String timeRemaining(int hours, int minutes, Object cycle);

  /// No description provided for @weekStartsOnDay.
  ///
  /// In en, this message translates to:
  /// **'Week starts on {day}'**
  String weekStartsOnDay(Object day);

  /// No description provided for @setTargetForProfession.
  ///
  /// In en, this message translates to:
  /// **'Set Target for {profession}'**
  String setTargetForProfession(Object profession);

  /// No description provided for @perWeek.
  ///
  /// In en, this message translates to:
  /// **'per week'**
  String get perWeek;

  /// No description provided for @perMonth.
  ///
  /// In en, this message translates to:
  /// **'per month'**
  String get perMonth;

  /// No description provided for @perYear.
  ///
  /// In en, this message translates to:
  /// **'per year'**
  String get perYear;

  /// No description provided for @targetPeriod.
  ///
  /// In en, this message translates to:
  /// **'Target period'**
  String get targetPeriod;

  /// No description provided for @disable.
  ///
  /// In en, this message translates to:
  /// **'Disable'**
  String get disable;

  /// No description provided for @addProfessionDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Add profession'**
  String get addProfessionDialogTitle;

  /// No description provided for @enterProfessionHint.
  ///
  /// In en, this message translates to:
  /// **'Enter profession'**
  String get enterProfessionHint;

  /// No description provided for @pleaseEnterProfession.
  ///
  /// In en, this message translates to:
  /// **'Please enter a profession'**
  String get pleaseEnterProfession;

  /// No description provided for @professionAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'That profession already exists'**
  String get professionAlreadyExists;

  /// No description provided for @professionInDeletedRestoreInstead.
  ///
  /// In en, this message translates to:
  /// **'That name is in Deleted. Restore it instead.'**
  String get professionInDeletedRestoreInstead;

  /// No description provided for @renameProfessionTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename profession'**
  String get renameProfessionTitle;

  /// No description provided for @pleaseEnterName.
  ///
  /// In en, this message translates to:
  /// **'Please enter a name'**
  String get pleaseEnterName;

  /// No description provided for @deleteProfessionTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete profession?'**
  String get deleteProfessionTitle;

  /// No description provided for @removeProfessionConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove \"{name}\"?'**
  String removeProfessionConfirm(Object name);

  /// No description provided for @movedToDeleted.
  ///
  /// In en, this message translates to:
  /// **'Moved \"{name}\" to Deleted'**
  String movedToDeleted(Object name);

  /// No description provided for @deletedRecordsTitle.
  ///
  /// In en, this message translates to:
  /// **'Deleted Records'**
  String get deletedRecordsTitle;

  /// No description provided for @noDeletedRecords.
  ///
  /// In en, this message translates to:
  /// **'No deleted records'**
  String get noDeletedRecords;

  /// No description provided for @deletedRecordsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load deleted records. Please try again.'**
  String get deletedRecordsLoadFailed;

  /// No description provided for @recordRestoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not restore the record. Please try again.'**
  String get recordRestoreFailed;

  /// No description provided for @restoreRecordProfessionConfirm.
  ///
  /// In en, this message translates to:
  /// **'Restoring this record will also add or restore the profession \"{profession}\". Its other saved, non-deleted records will become visible too. Continue?'**
  String restoreRecordProfessionConfirm(String profession);

  /// No description provided for @migrationTitle.
  ///
  /// In en, this message translates to:
  /// **'Storage rehearsal'**
  String get migrationTitle;

  /// No description provided for @migrationIntro.
  ///
  /// In en, this message translates to:
  /// **'Try moving sample records to the new store. Your own records are separate.'**
  String get migrationIntro;

  /// No description provided for @migrationScenario.
  ///
  /// In en, this message translates to:
  /// **'Sample data'**
  String get migrationScenario;

  /// No description provided for @migrationStandardSample.
  ///
  /// In en, this message translates to:
  /// **'Records with evidence'**
  String get migrationStandardSample;

  /// No description provided for @migrationReviewSample.
  ///
  /// In en, this message translates to:
  /// **'Records needing review'**
  String get migrationReviewSample;

  /// No description provided for @migrationLowSpaceSample.
  ///
  /// In en, this message translates to:
  /// **'Low storage'**
  String get migrationLowSpaceSample;

  /// No description provided for @migrationStart.
  ///
  /// In en, this message translates to:
  /// **'Run rehearsal'**
  String get migrationStart;

  /// No description provided for @migrationRetry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get migrationRetry;

  /// No description provided for @migrationStay.
  ///
  /// In en, this message translates to:
  /// **'Keep this screen open while the check runs.'**
  String get migrationStay;

  /// No description provided for @migrationCheckSpace.
  ///
  /// In en, this message translates to:
  /// **'Checking available space'**
  String get migrationCheckSpace;

  /// No description provided for @migrationCopy.
  ///
  /// In en, this message translates to:
  /// **'Making a recovery copy'**
  String get migrationCopy;

  /// No description provided for @migrationMove.
  ///
  /// In en, this message translates to:
  /// **'Preparing sample records'**
  String get migrationMove;

  /// No description provided for @migrationVerify.
  ///
  /// In en, this message translates to:
  /// **'Checking records and evidence'**
  String get migrationVerify;

  /// No description provided for @migrationReady.
  ///
  /// In en, this message translates to:
  /// **'Sample records verified'**
  String get migrationReady;

  /// No description provided for @migrationReadyDetail.
  ///
  /// In en, this message translates to:
  /// **'The sample copy is ready. Your usual storage is still in use.'**
  String get migrationReadyDetail;

  /// No description provided for @migrationReview.
  ///
  /// In en, this message translates to:
  /// **'Some records need review'**
  String get migrationReview;

  /// No description provided for @migrationReviewDetail.
  ///
  /// In en, this message translates to:
  /// **'The original values are saved. Review these issues before moving the affected records.'**
  String get migrationReviewDetail;

  /// No description provided for @migrationSpaceDetail.
  ///
  /// In en, this message translates to:
  /// **'Free up device space and try again. The original records are still available.'**
  String get migrationSpaceDetail;

  /// No description provided for @migrationProblem.
  ///
  /// In en, this message translates to:
  /// **'The rehearsal paused'**
  String get migrationProblem;

  /// No description provided for @migrationProblemDetail.
  ///
  /// In en, this message translates to:
  /// **'Your source records are still available. You can retry or keep this attempt for review.'**
  String get migrationProblemDetail;

  /// No description provided for @migrationDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Two records share an identifier'**
  String get migrationDuplicate;

  /// No description provided for @migrationDate.
  ///
  /// In en, this message translates to:
  /// **'The original date needs confirmation'**
  String get migrationDate;

  /// No description provided for @migrationDuration.
  ///
  /// In en, this message translates to:
  /// **'The original duration needs confirmation'**
  String get migrationDuration;

  /// No description provided for @migrationUnsupportedEvidence.
  ///
  /// In en, this message translates to:
  /// **'An evidence reference needs review'**
  String get migrationUnsupportedEvidence;

  /// No description provided for @migrationMissingEvidence.
  ///
  /// In en, this message translates to:
  /// **'Evidence was already missing. Its reference was kept.'**
  String get migrationMissingEvidence;

  /// No description provided for @migrationOtherIssue.
  ///
  /// In en, this message translates to:
  /// **'Original information was kept for review'**
  String get migrationOtherIssue;

  /// No description provided for @migrationOriginal.
  ///
  /// In en, this message translates to:
  /// **'View original record'**
  String get migrationOriginal;

  /// No description provided for @migrationOriginalUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The original record could not be opened.'**
  String get migrationOriginalUnavailable;

  /// No description provided for @migrationKeepAttempt.
  ///
  /// In en, this message translates to:
  /// **'Keep this attempt and stop'**
  String get migrationKeepAttempt;

  /// No description provided for @migrationStopped.
  ///
  /// In en, this message translates to:
  /// **'Attempt kept for review'**
  String get migrationStopped;

  /// No description provided for @migrationNew.
  ///
  /// In en, this message translates to:
  /// **'Start a new rehearsal'**
  String get migrationNew;

  /// No description provided for @editFields.
  ///
  /// In en, this message translates to:
  /// **'Edit fields'**
  String get editFields;

  /// No description provided for @addField.
  ///
  /// In en, this message translates to:
  /// **'Add field'**
  String get addField;

  /// No description provided for @customField.
  ///
  /// In en, this message translates to:
  /// **'Custom field'**
  String get customField;

  /// No description provided for @fieldLibrary.
  ///
  /// In en, this message translates to:
  /// **'Field Library'**
  String get fieldLibrary;

  /// No description provided for @chooseField.
  ///
  /// In en, this message translates to:
  /// **'Choose a field type'**
  String get chooseField;

  /// No description provided for @editorSearch.
  ///
  /// In en, this message translates to:
  /// **'Search fields'**
  String get editorSearch;

  /// No description provided for @editorAll.
  ///
  /// In en, this message translates to:
  /// **'All categories'**
  String get editorAll;

  /// No description provided for @editorNoResults.
  ///
  /// In en, this message translates to:
  /// **'No fields match. Try a different word or category.'**
  String get editorNoResults;

  /// No description provided for @editorPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get editorPreview;

  /// No description provided for @editorSettings.
  ///
  /// In en, this message translates to:
  /// **'Field settings'**
  String get editorSettings;

  /// No description provided for @editorName.
  ///
  /// In en, this message translates to:
  /// **'Field name'**
  String get editorName;

  /// No description provided for @editorHelp.
  ///
  /// In en, this message translates to:
  /// **'Help text'**
  String get editorHelp;

  /// No description provided for @editorPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Placeholder'**
  String get editorPlaceholder;

  /// No description provided for @editorRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get editorRequired;

  /// No description provided for @editorProtected.
  ///
  /// In en, this message translates to:
  /// **'Protected field'**
  String get editorProtected;

  /// No description provided for @editorProtectedReason.
  ///
  /// In en, this message translates to:
  /// **'This field is used by the standard CPD form and reports. You can rename or move it.'**
  String get editorProtectedReason;

  /// No description provided for @editorAdvanced.
  ///
  /// In en, this message translates to:
  /// **'More settings'**
  String get editorAdvanced;

  /// No description provided for @editorDefault.
  ///
  /// In en, this message translates to:
  /// **'Default value'**
  String get editorDefault;

  /// No description provided for @editorUnit.
  ///
  /// In en, this message translates to:
  /// **'Unit'**
  String get editorUnit;

  /// No description provided for @editorPrecision.
  ///
  /// In en, this message translates to:
  /// **'Decimal places'**
  String get editorPrecision;

  /// No description provided for @editorNonNegative.
  ///
  /// In en, this message translates to:
  /// **'Zero or greater'**
  String get editorNonNegative;

  /// No description provided for @editorChoice.
  ///
  /// In en, this message translates to:
  /// **'Choice'**
  String get editorChoice;

  /// No description provided for @editorAddChoice.
  ///
  /// In en, this message translates to:
  /// **'Add choice'**
  String get editorAddChoice;

  /// No description provided for @editorFormatting.
  ///
  /// In en, this message translates to:
  /// **'Display format'**
  String get editorFormatting;

  /// No description provided for @editorFuture.
  ///
  /// In en, this message translates to:
  /// **'Future records only'**
  String get editorFuture;

  /// No description provided for @editorBoth.
  ///
  /// In en, this message translates to:
  /// **'Existing and future records'**
  String get editorBoth;

  /// No description provided for @editorHistoryHint.
  ///
  /// In en, this message translates to:
  /// **'Existing records keep their saved values and original requirements.'**
  String get editorHistoryHint;

  /// No description provided for @editorInvalid.
  ///
  /// In en, this message translates to:
  /// **'Check the field name, choices and values.'**
  String get editorInvalid;

  /// No description provided for @editorBadRecord.
  ///
  /// In en, this message translates to:
  /// **'Fill in the required fields and check the entered values.'**
  String get editorBadRecord;

  /// No description provided for @editorDrag.
  ///
  /// In en, this message translates to:
  /// **'Drag to reorder'**
  String get editorDrag;

  /// No description provided for @editorMoveUp.
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get editorMoveUp;

  /// No description provided for @editorMoveDown.
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get editorMoveDown;

  /// No description provided for @editorDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate field'**
  String get editorDuplicate;

  /// No description provided for @editorRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove field'**
  String get editorRemove;

  /// No description provided for @editorRemoveHint.
  ///
  /// In en, this message translates to:
  /// **'This field leaves the current form. Saved values and evidence stay in older records.'**
  String get editorRemoveHint;

  /// No description provided for @editorReplace.
  ///
  /// In en, this message translates to:
  /// **'Replace field'**
  String get editorReplace;

  /// No description provided for @editorReplaceHint.
  ///
  /// In en, this message translates to:
  /// **'Changing number settings creates a new field for future records. Older values keep their original units and precision.'**
  String get editorReplaceHint;

  /// No description provided for @editorDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard changes?'**
  String get editorDiscard;

  /// No description provided for @editorDiscardAction.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get editorDiscardAction;

  /// No description provided for @editorUnsaved.
  ///
  /// In en, this message translates to:
  /// **'Your changes have not been saved.'**
  String get editorUnsaved;

  /// No description provided for @editorLimit.
  ///
  /// In en, this message translates to:
  /// **'Remove a field to add another.'**
  String get editorLimit;

  /// No description provided for @editorSaveError.
  ///
  /// In en, this message translates to:
  /// **'Could not save this layout. Your draft is still open.'**
  String get editorSaveError;

  /// No description provided for @editorAlreadyAdded.
  ///
  /// In en, this message translates to:
  /// **'In this layout'**
  String get editorAlreadyAdded;

  /// No description provided for @editorCreateCopy.
  ///
  /// In en, this message translates to:
  /// **'Add another copy'**
  String get editorCreateCopy;

  /// No description provided for @editorShort.
  ///
  /// In en, this message translates to:
  /// **'Short text'**
  String get editorShort;

  /// No description provided for @editorLong.
  ///
  /// In en, this message translates to:
  /// **'Long text'**
  String get editorLong;

  /// No description provided for @editorInteger.
  ///
  /// In en, this message translates to:
  /// **'Whole number'**
  String get editorInteger;

  /// No description provided for @editorDecimal.
  ///
  /// In en, this message translates to:
  /// **'Decimal number'**
  String get editorDecimal;

  /// No description provided for @editorDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get editorDate;

  /// No description provided for @editorDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get editorDuration;

  /// No description provided for @editorSingle.
  ///
  /// In en, this message translates to:
  /// **'Single choice'**
  String get editorSingle;

  /// No description provided for @editorMultiple.
  ///
  /// In en, this message translates to:
  /// **'Multiple choice'**
  String get editorMultiple;

  /// No description provided for @editorYesNo.
  ///
  /// In en, this message translates to:
  /// **'Yes/no'**
  String get editorYesNo;

  /// No description provided for @editorCheckbox.
  ///
  /// In en, this message translates to:
  /// **'Checkbox'**
  String get editorCheckbox;

  /// No description provided for @editorLink.
  ///
  /// In en, this message translates to:
  /// **'Web link'**
  String get editorLink;

  /// No description provided for @editorFile.
  ///
  /// In en, this message translates to:
  /// **'File attachment'**
  String get editorFile;

  /// No description provided for @editorPhoto.
  ///
  /// In en, this message translates to:
  /// **'Photograph'**
  String get editorPhoto;

  /// No description provided for @editorHeading.
  ///
  /// In en, this message translates to:
  /// **'Section heading'**
  String get editorHeading;

  /// No description provided for @editorSample.
  ///
  /// In en, this message translates to:
  /// **'Sample values'**
  String get editorSample;

  /// No description provided for @editorExample.
  ///
  /// In en, this message translates to:
  /// **'Example entry'**
  String get editorExample;

  /// No description provided for @editorSampleFile.
  ///
  /// In en, this message translates to:
  /// **'Sample evidence'**
  String get editorSampleFile;

  /// No description provided for @editorTry.
  ///
  /// In en, this message translates to:
  /// **'Try the form'**
  String get editorTry;

  /// No description provided for @editorPreviewNotice.
  ///
  /// In en, this message translates to:
  /// **'Try sample values here. They are discarded when you leave.'**
  String get editorPreviewNotice;

  /// No description provided for @editorTemplateDetails.
  ///
  /// In en, this message translates to:
  /// **'About this template'**
  String get editorTemplateDetails;

  /// No description provided for @editorExamplePdf.
  ///
  /// In en, this message translates to:
  /// **'Example PDF report'**
  String get editorExamplePdf;

  /// No description provided for @editorHistorical.
  ///
  /// In en, this message translates to:
  /// **'Historical fields'**
  String get editorHistorical;

  /// No description provided for @editorNewRecord.
  ///
  /// In en, this message translates to:
  /// **'New sample record'**
  String get editorNewRecord;

  /// No description provided for @editorRecords.
  ///
  /// In en, this message translates to:
  /// **'Sample records'**
  String get editorRecords;

  /// No description provided for @editorExport.
  ///
  /// In en, this message translates to:
  /// **'View export'**
  String get editorExport;

  /// No description provided for @editorVersion.
  ///
  /// In en, this message translates to:
  /// **'Template version'**
  String get editorVersion;

  /// No description provided for @editorReviewed.
  ///
  /// In en, this message translates to:
  /// **'Requirements reviewed'**
  String get editorReviewed;

  /// No description provided for @editorProfession.
  ///
  /// In en, this message translates to:
  /// **'Profession'**
  String get editorProfession;

  /// No description provided for @editorCountry.
  ///
  /// In en, this message translates to:
  /// **'Country'**
  String get editorCountry;

  /// No description provided for @editorBody.
  ///
  /// In en, this message translates to:
  /// **'Professional body'**
  String get editorBody;

  /// No description provided for @editorScheme.
  ///
  /// In en, this message translates to:
  /// **'CPD scheme'**
  String get editorScheme;

  /// No description provided for @editorYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get editorYes;

  /// No description provided for @editorNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get editorNo;

  /// No description provided for @editorMinutes.
  ///
  /// In en, this message translates to:
  /// **'Minutes'**
  String get editorMinutes;

  /// No description provided for @editorClear.
  ///
  /// In en, this message translates to:
  /// **'Clear value'**
  String get editorClear;

  /// No description provided for @editorFullCount.
  ///
  /// In en, this message translates to:
  /// **'{count} of {limit} fields'**
  String editorFullCount(int count, int limit);

  /// No description provided for @editorCount.
  ///
  /// In en, this message translates to:
  /// **'Fields: {count}'**
  String editorCount(int count);

  /// No description provided for @editorPosition.
  ///
  /// In en, this message translates to:
  /// **'Position {position} of {count}'**
  String editorPosition(int position, int count);

  /// No description provided for @editorChoiceReplaceHint.
  ///
  /// In en, this message translates to:
  /// **'Choice changes create a new field for future records. Older records keep their original options.'**
  String get editorChoiceReplaceHint;

  /// No description provided for @p6Standard.
  ///
  /// In en, this message translates to:
  /// **'Standard CPD'**
  String get p6Standard;

  /// No description provided for @p6Custom.
  ///
  /// In en, this message translates to:
  /// **'Custom CPD'**
  String get p6Custom;

  /// No description provided for @p6Templates.
  ///
  /// In en, this message translates to:
  /// **'Profession Templates'**
  String get p6Templates;

  /// No description provided for @p6StandardDetail.
  ///
  /// In en, this message translates to:
  /// **'Free CPD recording with the standard fields.'**
  String get p6StandardDetail;

  /// No description provided for @p6CustomDetail.
  ///
  /// In en, this message translates to:
  /// **'Design a form with the field editor and Field Library.'**
  String get p6CustomDetail;

  /// No description provided for @p6TemplateDetail.
  ///
  /// In en, this message translates to:
  /// **'Browse researched recording forms and reports for your profession.'**
  String get p6TemplateDetail;

  /// No description provided for @p6Create.
  ///
  /// In en, this message translates to:
  /// **'Create profession'**
  String get p6Create;

  /// No description provided for @p6First.
  ///
  /// In en, this message translates to:
  /// **'Create your first profession'**
  String get p6First;

  /// No description provided for @p6Name.
  ///
  /// In en, this message translates to:
  /// **'Profession name'**
  String get p6Name;

  /// No description provided for @p6CustomScope.
  ///
  /// In en, this message translates to:
  /// **'Custom Fields lets you design and edit forms across professions.'**
  String get p6CustomScope;

  /// No description provided for @p6TemplateScope.
  ///
  /// In en, this message translates to:
  /// **'Includes the supplied fields, layout arrangement and optional report selections. Custom Fields is needed to change or add field definitions.'**
  String get p6TemplateScope;

  /// No description provided for @p6ChooseTemplate.
  ///
  /// In en, this message translates to:
  /// **'Choose this template'**
  String get p6ChooseTemplate;

  /// No description provided for @p6TryArrangement.
  ///
  /// In en, this message translates to:
  /// **'Try the layout controls'**
  String get p6TryArrangement;

  /// No description provided for @p6Layout.
  ///
  /// In en, this message translates to:
  /// **'Arrange recording fields'**
  String get p6Layout;

  /// No description provided for @p6RestoreField.
  ///
  /// In en, this message translates to:
  /// **'Reinstate a supplied field'**
  String get p6RestoreField;

  /// No description provided for @p6ReportFields.
  ///
  /// In en, this message translates to:
  /// **'Fields in the report'**
  String get p6ReportFields;

  /// No description provided for @p6ReportHint.
  ///
  /// In en, this message translates to:
  /// **'Report choices and recording fields are configured separately.'**
  String get p6ReportHint;

  /// No description provided for @p6RestoreDefaults.
  ///
  /// In en, this message translates to:
  /// **'Restore supplied defaults'**
  String get p6RestoreDefaults;

  /// No description provided for @p6ResetHint.
  ///
  /// In en, this message translates to:
  /// **'This restores the supplied form and report choices. Historical values remain available.'**
  String get p6ResetHint;

  /// No description provided for @p6Compatible.
  ///
  /// In en, this message translates to:
  /// **'Required report fields available'**
  String get p6Compatible;

  /// No description provided for @p6Optional.
  ///
  /// In en, this message translates to:
  /// **'Optional report content changed'**
  String get p6Optional;

  /// No description provided for @p6Incomplete.
  ///
  /// In en, this message translates to:
  /// **'Incomplete activity report'**
  String get p6Incomplete;

  /// No description provided for @p6CompatibilityHint.
  ///
  /// In en, this message translates to:
  /// **'Restore and include the listed fields to recover the scheme report. An incomplete activity log is still available.'**
  String get p6CompatibilityHint;

  /// No description provided for @p6Resume.
  ///
  /// In en, this message translates to:
  /// **'Resume draft'**
  String get p6Resume;

  /// No description provided for @p6Discard.
  ///
  /// In en, this message translates to:
  /// **'Discard draft'**
  String get p6Discard;

  /// No description provided for @p6DraftHint.
  ///
  /// In en, this message translates to:
  /// **'A draft becomes a profession or layout only when you save it.'**
  String get p6DraftHint;

  /// No description provided for @p6Store.
  ///
  /// In en, this message translates to:
  /// **'Rehearsal store'**
  String get p6Store;

  /// No description provided for @p6StoreHint.
  ///
  /// In en, this message translates to:
  /// **'Simulated checkout. No payment is taken.'**
  String get p6StoreHint;

  /// No description provided for @p6Checkout.
  ///
  /// In en, this message translates to:
  /// **'Start simulated checkout'**
  String get p6Checkout;

  /// No description provided for @p6Pending.
  ///
  /// In en, this message translates to:
  /// **'Purchase pending'**
  String get p6Pending;

  /// No description provided for @p6Complete.
  ///
  /// In en, this message translates to:
  /// **'Simulate completion'**
  String get p6Complete;

  /// No description provided for @p6CancelPurchase.
  ///
  /// In en, this message translates to:
  /// **'Simulate cancellation'**
  String get p6CancelPurchase;

  /// No description provided for @p6Cancelled.
  ///
  /// In en, this message translates to:
  /// **'Purchase cancelled'**
  String get p6Cancelled;

  /// No description provided for @p6Restore.
  ///
  /// In en, this message translates to:
  /// **'Restore simulated purchase'**
  String get p6Restore;

  /// No description provided for @p6Legacy.
  ///
  /// In en, this message translates to:
  /// **'Verify simulated original paid customer'**
  String get p6Legacy;

  /// No description provided for @p6Offline.
  ///
  /// In en, this message translates to:
  /// **'Store unavailable'**
  String get p6Offline;

  /// No description provided for @p6UseOffline.
  ///
  /// In en, this message translates to:
  /// **'Simulate store outage'**
  String get p6UseOffline;

  /// No description provided for @p6Owned.
  ///
  /// In en, this message translates to:
  /// **'Access verified'**
  String get p6Owned;

  /// No description provided for @p6Options.
  ///
  /// In en, this message translates to:
  /// **'Profession choices'**
  String get p6Options;

  /// No description provided for @p6OpenReport.
  ///
  /// In en, this message translates to:
  /// **'Open activity report'**
  String get p6OpenReport;

  /// No description provided for @p6TemplateUpdate.
  ///
  /// In en, this message translates to:
  /// **'Review template update'**
  String get p6TemplateUpdate;

  /// No description provided for @p7Period.
  ///
  /// In en, this message translates to:
  /// **'Reporting period'**
  String get p7Period;

  /// No description provided for @p7Deadline.
  ///
  /// In en, this message translates to:
  /// **'Application deadline'**
  String get p7Deadline;

  /// No description provided for @p7ChooseDeadline.
  ///
  /// In en, this message translates to:
  /// **'Set application deadline'**
  String get p7ChooseDeadline;

  /// No description provided for @p7MissingDeadline.
  ///
  /// In en, this message translates to:
  /// **'Deadline not set'**
  String get p7MissingDeadline;

  /// No description provided for @p7ConfigurePeriod.
  ///
  /// In en, this message translates to:
  /// **'Set or view reporting period'**
  String get p7ConfigurePeriod;

  /// No description provided for @p7PeriodHint.
  ///
  /// In en, this message translates to:
  /// **'Confirm dates and deadlines with your professional body.'**
  String get p7PeriodHint;

  /// No description provided for @p7CustomPeriod.
  ///
  /// In en, this message translates to:
  /// **'Custom date range'**
  String get p7CustomPeriod;

  /// No description provided for @p7FixedPeriod.
  ///
  /// In en, this message translates to:
  /// **'Fixed cycle from a start date'**
  String get p7FixedPeriod;

  /// No description provided for @p7RollingPeriod.
  ///
  /// In en, this message translates to:
  /// **'Rolling cycle ending on a date'**
  String get p7RollingPeriod;

  /// No description provided for @p7Recorded.
  ///
  /// In en, this message translates to:
  /// **'Recorded'**
  String get p7Recorded;

  /// No description provided for @p7Complete.
  ///
  /// In en, this message translates to:
  /// **'Complete entries'**
  String get p7Complete;

  /// No description provided for @p7Eligible.
  ///
  /// In en, this message translates to:
  /// **'Eligible in this log'**
  String get p7Eligible;

  /// No description provided for @p7Target.
  ///
  /// In en, this message translates to:
  /// **'Target'**
  String get p7Target;

  /// No description provided for @p7IssueMissing.
  ///
  /// In en, this message translates to:
  /// **'Missing required information'**
  String get p7IssueMissing;

  /// No description provided for @p7IssueInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid or incompatible values'**
  String get p7IssueInvalid;

  /// No description provided for @p7IssueEvidence.
  ///
  /// In en, this message translates to:
  /// **'Evidence unavailable'**
  String get p7IssueEvidence;

  /// No description provided for @p7IssueSplit.
  ///
  /// In en, this message translates to:
  /// **'Activity spans the period boundary'**
  String get p7IssueSplit;

  /// No description provided for @p7IssueDate.
  ///
  /// In en, this message translates to:
  /// **'Date unresolved; outside period totals'**
  String get p7IssueDate;

  /// No description provided for @p7ReviewLog.
  ///
  /// In en, this message translates to:
  /// **'Activities to review'**
  String get p7ReviewLog;

  /// No description provided for @p7EvidenceIndex.
  ///
  /// In en, this message translates to:
  /// **'Evidence references'**
  String get p7EvidenceIndex;

  /// No description provided for @p7Summary.
  ///
  /// In en, this message translates to:
  /// **'Period summary'**
  String get p7Summary;

  /// No description provided for @p7Practitioner.
  ///
  /// In en, this message translates to:
  /// **'Practitioner'**
  String get p7Practitioner;

  /// No description provided for @p7Reviewed.
  ///
  /// In en, this message translates to:
  /// **'Regulatory review'**
  String get p7Reviewed;

  /// No description provided for @p7ReportScope.
  ///
  /// In en, this message translates to:
  /// **'Independent CPD log. Confirm eligibility and submission requirements with your professional body.'**
  String get p7ReportScope;

  /// No description provided for @p7LayoutWarning.
  ///
  /// In en, this message translates to:
  /// **'Report configuration is missing scheme fields. Review the field selection.'**
  String get p7LayoutWarning;

  /// No description provided for @p7Synthetic.
  ///
  /// In en, this message translates to:
  /// **'Synthetic example'**
  String get p7Synthetic;

  /// No description provided for @p7Internal.
  ///
  /// In en, this message translates to:
  /// **'Internal rehearsal'**
  String get p7Internal;

  /// No description provided for @p7RuleRevision.
  ///
  /// In en, this message translates to:
  /// **'Reporting rules'**
  String get p7RuleRevision;

  /// No description provided for @reportLanguage.
  ///
  /// In en, this message translates to:
  /// **'Report language'**
  String get reportLanguage;

  /// No description provided for @reportFollowAppLanguage.
  ///
  /// In en, this message translates to:
  /// **'Use app language'**
  String get reportFollowAppLanguage;

  /// No description provided for @reportTemplateLanguageFallback.
  ///
  /// In en, this message translates to:
  /// **'Some template labels or guidance are shown in the source language where a translation is unavailable.'**
  String get reportTemplateLanguageFallback;

  /// No description provided for @p7aSavedPeriods.
  ///
  /// In en, this message translates to:
  /// **'Saved periods'**
  String get p7aSavedPeriods;

  /// No description provided for @p7aNewPeriod.
  ///
  /// In en, this message translates to:
  /// **'Add a period'**
  String get p7aNewPeriod;

  /// No description provided for @p7aCurrentPeriod.
  ///
  /// In en, this message translates to:
  /// **'Selected period'**
  String get p7aCurrentPeriod;

  /// No description provided for @p7aUsePeriod.
  ///
  /// In en, this message translates to:
  /// **'Use this period'**
  String get p7aUsePeriod;

  /// No description provided for @p7aPeriodDetails.
  ///
  /// In en, this message translates to:
  /// **'Period details'**
  String get p7aPeriodDetails;

  /// No description provided for @p7aFixed.
  ///
  /// In en, this message translates to:
  /// **'Full cycle from a start date'**
  String get p7aFixed;

  /// No description provided for @p7aRolling.
  ///
  /// In en, this message translates to:
  /// **'Full cycle ending on a chosen date'**
  String get p7aRolling;

  /// No description provided for @p7aReportMeasure.
  ///
  /// In en, this message translates to:
  /// **'Measure'**
  String get p7aReportMeasure;

  /// No description provided for @p7aEligible.
  ///
  /// In en, this message translates to:
  /// **'Eligible'**
  String get p7aEligible;

  /// No description provided for @p7aAttribution.
  ///
  /// In en, this message translates to:
  /// **'Generated using CPD Progress Tracker'**
  String get p7aAttribution;

  /// No description provided for @reportHindiRequiresShaping.
  ///
  /// In en, this message translates to:
  /// **'This PDF contains Devanagari text and needs a renderer that can shape the script. Your records and report language setting are saved.'**
  String get reportHindiRequiresShaping;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'de',
    'en',
    'es',
    'fr',
    'hi',
    'pt',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'hi':
      return AppLocalizationsHi();
    case 'pt':
      return AppLocalizationsPt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
