/// Match the stored preference or Material's Sunday-based locale index.
int cpdFirstWeekday(String preference, int localeFirstDayIndex) =>
    switch (preference) {
      'monday' => DateTime.monday,
      'saturday' => DateTime.saturday,
      'sunday' => DateTime.sunday,
      _ => localeFirstDayIndex == 0 ? DateTime.sunday : localeFirstDayIndex,
    };

/// The existing CPD target cycle and rounding policy, shared with parity tests.
(DateTime start, DateTime end) cpdTargetPeriod(
  DateTime now,
  String cycle, {
  int firstWeekday = DateTime.monday,
}) {
  switch (cycle) {
    case 'week':
      final diff = (now.weekday - firstWeekday) % 7;
      return (
        DateTime(now.year, now.month, now.day - diff),
        DateTime(now.year, now.month, now.day - diff + 7),
      );
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
