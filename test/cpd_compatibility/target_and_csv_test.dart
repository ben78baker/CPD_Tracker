import 'package:cpd_tracker/cpd_compatibility/cpd_targets.dart';
import 'package:cpd_tracker/l10n/app_localizations_en.dart';
import 'package:cpd_tracker/models.dart';
import 'package:cpd_tracker/utils/csv_exporter.dart';
import 'package:cpd_tracker/utils/export_selection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'target periods preserve inclusive start and exclusive end across years',
    () {
      final today = DateTime(2024, 12, 31, 14);
      expect(cpdTargetPeriod(today, 'week'), (
        DateTime(2024, 12, 30),
        DateTime(2025, 1, 6),
      ));
      expect(cpdTargetPeriod(today, 'week', firstWeekday: DateTime.saturday), (
        DateTime(2024, 12, 28),
        DateTime(2025, 1, 4),
      ));
      expect(cpdTargetPeriod(today, 'month'), (
        DateTime(2024, 12, 1),
        DateTime(2025, 1, 1),
      ));
      expect(cpdTargetPeriod(today, 'year'), (DateTime(2024), DateTime(2025)));
      expect(scaleCpdTargetMinutes(60, 'week', 'month'), 260);
      expect(scaleCpdTargetMinutes(60, 'month', 'week'), 14);
      expect(scaleCpdTargetMinutes(60, 'year', 'week'), 1);
    },
  );

  test('CSV keeps the legacy header, escaping, line flattening and totals', () {
    final texts = AppLocalizationsEn();
    final csv = buildCpdCsv(
      selection: CpdExportSelection.fromVisibleRecords(
        profession: 'Dental "care"',
        range: DateTimeRange(
          start: DateTime(2024, 2, 1),
          end: DateTime(2024, 2, 29),
        ),
        visibleRecords: [
          CpdEntry(
            id: 1,
            profession: 'Dental "care"',
            date: DateTime(2024, 2, 29),
            title: 'Evidence, "course"',
            details: 'Ligne 1\n学習',
            hours: 1,
            minutes: 5,
            attachments: ['attachments/missing.png'],
          ),
        ],
      ),
      dateFormat: 'dd/MM/yyyy',
      texts: texts,
      userName: 'Sample "User"',
    );
    final lines = csv.text.split('\n');
    expect(lines[0], '"${texts.nameLabel}:","Sample ""User"""');
    expect(lines[3], '"${texts.professionLabel}:","Dental ""care"""');
    expect(
      lines[4],
      '"${texts.periodLabel}:","01/02/2024 ${texts.toWord} 29/02/2024"',
    );
    expect(lines[5], '"${texts.totalTimeLabel}:","1h 5m"');
    expect(
      lines[8],
      '${texts.csvDateHeader},${texts.csvTitleHeader},${texts.hoursLabel},${texts.minutesLabel},${texts.detailsLabel},${texts.csvHasAttachmentsHeader}',
    );
    expect(
      lines[9],
      '"29/02/2024","Evidence, ""course""",1,5,"Ligne 1 学習","${texts.yes}"',
    );
    expect((csv.hours, csv.minutes), (1, 5));
  });
}
