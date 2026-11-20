// Read-only checks against existing pure Dart models and search on synthetic data.
import '../../../../lib/models.dart';
import '../../../../lib/utils/record_search.dart';

void check(bool result, String label) {
  if (!result) throw StateError(label);
  print('PASS $label');
}

void main() {
  final sparse = CpdEntry.fromJson(
    '{"id":9,"profession":"Éducation","date":"2024-02-29",'
    '"attachments":["attachments/证书.pdf"],"future_field":{"v":3}}',
  );
  check(
    sparse.title == '' &&
        sparse.details == '' &&
        sparse.hours == 0 &&
        sparse.minutes == 0 &&
        !sparse.deleted,
    'missing legacy optional fields receive existing defaults',
  );
  check(
    RecordSearch.matches(sparse, '证书') &&
        !sparse.toMap().containsKey('future_field'),
    'existing search uses raw attachment string and fixed writer drops unknown key',
  );
  final offset = CpdEntry.fromJson(
    '{"id":10,"profession":"Éducation","date":"2024-02-29T23:30:00-02:00"}',
  );
  check(
    formatDate(offset.date, 'yyyy-MM-dd') == '2024-03-01',
    'offset-bearing legacy date displays the parsed day',
  );
  final invalidCalendarDay = CpdEntry.fromJson(
    '{"id":11,"profession":"Éducation","date":"2024-02-30"}',
  );
  check(
    formatDate(invalidCalendarDay.date, 'yyyy-MM-dd') == '2024-03-01',
    'existing decoder normalises an invalid calendar date',
  );
  final numeric = CpdEntry.fromJson(
    '{"id":12,"profession":"Éducation","date":"2024-02-29","hours":1.5}',
  );
  check(
    numeric.hours == 1,
    'existing decoder truncates non-integer numeric hours',
  );
}
