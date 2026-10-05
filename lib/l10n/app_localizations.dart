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
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

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
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
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
    Locale('pt')
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
  /// **'Note: Attachments are saved in the app. Choose PDF with photographic evidence to embed supported photos, or PDF + original attachments (ZIP) to share original files.'**
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
  /// **'PDF with photographic evidence'**
  String get pdfWithEvidence;

  /// No description provided for @pdfWithEvidenceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Adds supported photos on dedicated evidence pages'**
  String get pdfWithEvidenceSubtitle;

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
  String cpdEntriesShareText(Object profession, Object from, Object to, int hours, int minutes);

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
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['de', 'en', 'es', 'fr', 'hi', 'pt'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {


  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de': return AppLocalizationsDe();
    case 'en': return AppLocalizationsEn();
    case 'es': return AppLocalizationsEs();
    case 'fr': return AppLocalizationsFr();
    case 'hi': return AppLocalizationsHi();
    case 'pt': return AppLocalizationsPt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );
}
