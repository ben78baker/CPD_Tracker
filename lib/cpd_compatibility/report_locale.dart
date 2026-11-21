import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';

/// An export preference, independent of app language and scheme location.
enum ReportLanguage {
  app('', ''),
  englishUk('en-GB', 'English (UK)'),
  englishUs('en-US', 'English (US)'),
  german('de', 'Deutsch'),
  spanish('es', 'Español'),
  french('fr', 'Français'),
  hindi('hi', 'हिन्दी'),
  portuguese('pt', 'Português (Brasil)');

  const ReportLanguage(this.tag, this.nativeName);
  final String tag, nativeName;

  static ReportLanguage fromStored(String? tag) => values.firstWhere(
    (language) => language.tag == tag,
    orElse: () => ReportLanguage.app,
  );
}

class ReportLocale {
  ReportLocale(this.strings, {String? tag})
    : tag =
          tag ??
          switch (strings.localeName) {
            'en' => 'en_GB',
            'pt' => 'pt_BR',
            _ => strings.localeName,
          };

  static Future<ReportLocale> resolve(
    ReportLanguage choice,
    AppLocalizations app,
  ) async {
    await initializeDateFormatting();
    if (choice == ReportLanguage.app) return ReportLocale(app);
    final parts = choice.tag.split('-');
    final strings = await AppLocalizations.delegate.load(Locale(parts.first));
    return ReportLocale(
      strings,
      tag: choice == ReportLanguage.portuguese
          ? 'pt_BR'
          : choice.tag.replaceAll('-', '_'),
    );
  }

  final AppLocalizations strings;

  /// Formatting locale retains its region even when messages share a language.
  final String tag;

  String date(DateTime day) => DateFormat.yMMMd(tag).format(day);
  String integer(int value) => NumberFormat.decimalPattern(tag).format(value);
  // Decimal values persist as exact strings. Only the display punctuation changes.
  String decimal(String value) {
    final symbols = NumberFormat.decimalPattern(tag).symbols;
    return value
        .replaceFirst('.', symbols.DECIMAL_SEP)
        .replaceFirst('-', symbols.MINUS_SIGN);
  }

  String hours(int count) => _formatCount(strings.reportHours(count), count);
  String minutes(int count) =>
      _formatCount(strings.reportMinutes(count), count);

  String _formatCount(String translated, int count) =>
      translated.replaceFirst(RegExp(r'[0-9]+'), integer(count));

  String duration(int value) {
    if (value < 60) return minutes(value);
    final remainder = value % 60;
    return remainder == 0
        ? hours(value ~/ 60)
        : '${hours(value ~/ 60)} ${minutes(remainder)}';
  }
}
