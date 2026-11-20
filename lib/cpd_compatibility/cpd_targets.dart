/// The existing CPD target cycle and rounding policy, shared with parity tests.
(DateTime start, DateTime end) cpdTargetPeriod(
  DateTime now,
  String cycle, {
  int firstWeekday = DateTime.monday,
}) {
  switch (cycle) {
    case 'week':
      final today = DateTime(now.year, now.month, now.day);
      final diff = (now.weekday - firstWeekday) % 7;
      final start = today.subtract(Duration(days: diff));
      return (start, start.add(const Duration(days: 7)));
    case 'month':
      return (
        DateTime(now.year, now.month, 1),
        DateTime(now.year, now.month + 1, 1),
      );
    default:
      return (DateTime(now.year, 1, 1), DateTime(now.year + 1, 1, 1));
  }
}

int scaleCpdTargetMinutes(int minutes, String fromCycle, String toCycle) {
  if (fromCycle == toCycle) return minutes;

  const wPerY = 52.0;
  const mPerY = 12.0;
  const wPerM = wPerY / mPerY; // ~4.3333

  final mins = minutes.toDouble();
  double factor = 1.0;

  if (fromCycle == 'week' && toCycle == 'year') {
    factor = wPerY;
  } else if (fromCycle == 'year' && toCycle == 'week') {
    factor = 1 / wPerY;
  } else if (fromCycle == 'month' && toCycle == 'year') {
    factor = mPerY;
  } else if (fromCycle == 'year' && toCycle == 'month') {
    factor = 1 / mPerY;
  } else if (fromCycle == 'week' && toCycle == 'month') {
    factor = wPerM;
  } else if (fromCycle == 'month' && toCycle == 'week') {
    factor = 1 / wPerM;
  }

  return (mins * factor).round();
}
