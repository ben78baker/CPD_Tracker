import 'package:flutter/material.dart' show DateTimeRange;

import '../models.dart';
import 'date_utils.dart';

/// The immutable, fully filtered record set supplied to every exporter.
///
/// Callers provide the records currently visible to the user. This factory
/// then applies the profession and inclusive date-range boundaries once, so
/// CSV, PDF, and ZIP exports cannot diverge in their record selection.
class CpdExportSelection {
  CpdExportSelection._({
    required this.profession,
    required this.range,
    required List<CpdEntry> records,
  }) : records = List<CpdEntry>.unmodifiable(records);

  factory CpdExportSelection.fromVisibleRecords({
    required String profession,
    required DateTimeRange range,
    required Iterable<CpdEntry> visibleRecords,
  }) {
    final normalizedProfession = profession.trim().toLowerCase();
    final start = dateOnly(range.start);
    final end = dateOnly(range.end);

    final selected = visibleRecords.where((entry) {
      if (entry.deleted) return false;
      if (entry.profession.trim().toLowerCase() != normalizedProfession) {
        return false;
      }

      final date = dateOnly(entry.date);
      return !date.isBefore(start) && !date.isAfter(end);
    }).toList();

    selected.sort((a, b) {
      final dateComparison = dateOnly(a.date).compareTo(dateOnly(b.date));
      if (dateComparison != 0) return dateComparison;
      return a.id.compareTo(b.id);
    });

    return CpdExportSelection._(
      profession: profession,
      range: DateTimeRange(start: start, end: end),
      records: selected,
    );
  }

  final String profession;
  final DateTimeRange range;
  final List<CpdEntry> records;

  bool get isEmpty => records.isEmpty;
}
