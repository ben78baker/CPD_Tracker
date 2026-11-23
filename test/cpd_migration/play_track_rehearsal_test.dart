import 'package:cpd_tracker/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'play_track_rehearsal.dart' show matchesPlayFixture;

const _token = 'a123456789abcdef01234567';

Map<String, Object?> _fixture() => {
  'professions': ['Rehearsal alpha', 'Rehearsal beta'],
  'entries_json_list': [
    for (var row = 1; row <= 6; row++)
      CpdEntry(
        id: row,
        profession: row <= 3 ? 'Rehearsal alpha' : 'Rehearsal beta',
        date: DateTime(2025, 4, row),
        title: 'CPD $_token $row',
        details: '',
        hours: 0,
        minutes: 30,
        attachments: row == 1 ? ['attachments/fixture.pdf'] : [],
        deleted: row == 6,
      ).toJson(),
  ],
};

void main() {
  test('only the exact disposable row set admits a Play rehearsal', () {
    final fixture = _fixture();
    final rows = fixture['entries_json_list'] as List<String>;
    expect(matchesPlayFixture(fixture, _token), isTrue);
    expect(matchesPlayFixture(fixture, ''), isFalse);
    expect(matchesPlayFixture(fixture, 'f' * 24), isFalse);
    expect(matchesPlayFixture({}, _token), isFalse);

    final valuesRequiringRejection = [
      {
        ...fixture,
        'professions': ['Rehearsal alpha', 'Other data'],
      },
      {
        ...fixture,
        'deleted_professions': ['Prior data'],
      },
      {
        ...fixture,
        'entries_json_list': [...rows, rows.first],
      },
      {
        ...fixture,
        'entries_json_list': [...rows.take(5), rows.first],
      },
      {
        ...fixture,
        'entries_json_list': [...rows.take(5), '{'],
      },
      {
        ...fixture,
        'entries_json_list': [
          ...rows.take(5),
          rows.last.replaceFirst('CPD', 'Personal'),
        ],
      },
    ];
    for (final source in valuesRequiringRejection) {
      expect(matchesPlayFixture(source, _token), isFalse);
    }
  });
}
