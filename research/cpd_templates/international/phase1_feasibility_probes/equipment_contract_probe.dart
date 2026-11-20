// Disposable data-shape and boundary check. Uses only Dart core libraries.
import 'dart:convert';

void check(bool result, String label) {
  if (!result) throw StateError(label);
  print('PASS $label');
}

void main() {
  // A recipe has field keys and input types. A layout application assigns
  // different field IDs per collection. Neither contains record values.
  const recipe = {
    'equipment_id': 'short_text',
    'description': 'long_text',
    'inspection_date': 'date',
    'result': 'single_select',
    'notes': 'long_text',
    'technician': 'short_text',
    'evidence': 'managed_attachments',
    'next_inspection': 'date',
  };
  final applied = {
    for (final name in ['workshop', 'vehicles'])
      name: {for (final key in recipe.keys) key: '$name/$key'},
  };
  final workshop = applied['workshop']!;
  check(workshop.length == 8, 'eight generic fields');
  check(
    workshop.values
        .toSet()
        .intersection(applied['vehicles']!.values.toSet())
        .isEmpty,
    'one recipe creates independent field IDs',
  );

  const labelsByVersion = {
    'v1': {'ok': 'Pass', 'follow_up': 'Needs follow-up'},
    'v2': {'ok': 'Pass', 'review': 'Review before use'},
  };
  final fixture = {
    'id': 'record-01',
    'layout': 'workshop/rev-1',
    'choiceVersion': 'v1',
    'values': {
      workshop['equipment_id']!: 'PUMP-042',
      workshop['description']!: 'North pump',
      workshop['inspection_date']!: '2026-11-19',
      workshop['result']!: 'follow_up',
      workshop['notes']!: 'Check seal, clean housing.',
      workshop['technician']!: 'É. Malik',
      workshop['evidence']!: ['asset-photo-1', 'asset-document-1'],
      workshop['next_inspection']!: '2027-02-19',
    },
  };
  final record = jsonDecode(jsonEncode(fixture)) as Map<String, dynamic>;
  final values = record['values'] as Map<String, dynamic>;
  final result = values[workshop['result']] as String;
  final historicalLabel = labelsByVersion[record['choiceVersion']]![result];
  check(
    historicalLabel == 'Needs follow-up' &&
        !labelsByVersion['v2']!.containsKey(result),
    'retired choice resolves with historical meaning',
  );
  check(
    (values[workshop['next_inspection']] as String).compareTo(
          values[workshop['inspection_date']] as String,
        ) >
        0,
    'future next inspection survives round-trip',
  );
  final searchable = [
    values[workshop['equipment_id']],
    historicalLabel,
    values[workshop['technician']],
  ].join(' ').toLowerCase();
  check(
    searchable.contains('pump-042') && searchable.contains('needs follow-up'),
    'search uses value and historical choice label',
  );
  // Simulate a value edit and an export projection pinned to the revision.
  values[workshop['notes']!] = 'Seal replaced, no leak.';
  final reportRow = {
    for (final field in recipe.keys)
      field: field == 'result' ? historicalLabel : values[workshop[field]],
  };
  check(
    reportRow['notes'] == 'Seal replaced, no leak.' &&
        reportRow['result'] == historicalLabel &&
        (reportRow['evidence'] as List).join(',') ==
            'asset-photo-1,asset-document-1',
    'value edit and export projection retain version and evidence order',
  );
}
