// lib/utils/date_utils.dart
/// Strips the time portion from a DateTime, leaving only year/month/day.
/// Useful for comparing dates without worrying about time-of-day.
DateTime dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

/// Formats a DateTime as DD/MM/YYYY string.
String formatDateDMY(DateTime dt) {
  return '${dt.day.toString().padLeft(2, '0')}/'
         '${dt.month.toString().padLeft(2, '0')}/'
         '${dt.year}';
}

/// Formats a DateTime range as "DD/MM/YYYY → DD/MM/YYYY".
String formatDateRange(DateTime from, DateTime to) {
  return '${formatDateDMY(from)} → ${formatDateDMY(to)}';
}