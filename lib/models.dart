import 'dart:convert';

class CpdEntry {
  final int id; // unique, hidden from UI
  final String profession; // source profession
  final DateTime date; // stored ISO; formatted per setting in UI
  final String title;
  final String details;
  final int hours; // >= 0
  final int minutes; // 0..59
  final List<String> attachments; // links/notes for now
  final bool deleted; // hidden from UI

  CpdEntry({
    required this.id,
    required this.profession,
    required this.date,
    required this.title,
    required this.details,
    required this.hours,
    required this.minutes,
    required this.attachments,
    this.deleted = false,
  });
  String get attachmentsFlag =>
      attachments.isNotEmpty ? 'Evidence available on request' : '';

  Map<String, dynamic> toMap() => {
    'id': id,
    'profession': profession,
    'date': date.toIso8601String(),
    'title': title,
    'details': details,
    'hours': hours,
    'minutes': minutes,
    'attachments': attachments,
    'deleted': deleted,
  };

  factory CpdEntry.fromMap(Map<String, dynamic> m) => CpdEntry(
    id: m['id'] as int,
    profession: m['profession'] as String,
    date: DateTime.parse(m['date'] as String),
    title: (m['title'] as String?) ?? '',
    details: (m['details'] as String?) ?? '',
    hours: (m['hours'] as num?)?.toInt() ?? 0,
    minutes: (m['minutes'] as num?)?.toInt() ?? 0,
    attachments:
        (m['attachments'] as List?)?.map((e) => e.toString()).toList() ??
        const <String>[],
    deleted: (m['deleted'] as bool?) ?? false,
  );

  String toJson() => jsonEncode(toMap());
  factory CpdEntry.fromJson(String s) =>
      CpdEntry.fromMap(jsonDecode(s) as Map<String, dynamic>);
}

// Very light date formatting — default dd/MM/yyyy with two alternates.
// (We’ll replace with full intl later if needed.)
String formatDate(DateTime d, String fmt) {
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  final yyyy = d.year.toString();
  switch (fmt) {
    case 'MM/dd/yyyy':
      return '$mm/$dd/$yyyy';
    case 'yyyy-MM-dd':
      return '$yyyy-$mm-$dd';
    case 'dd/MM/yyyy':
    default:
      return '$dd/$mm/$yyyy';
  }
}
