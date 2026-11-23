import 'dart:convert';

import 'models.dart';

/// Generic long-form CSV rows preserve stable identities and each historical
/// field's label, unit and exact stored value even when layouts differ.
List<List<String>> recordExportRows(
  RecordingRecord record,
  Iterable<LayoutField> fields, {
  String? locale,
}) => [
  for (final field in fields)
    if (record.values[field.id] case final value?)
      [
        record.id,
        record.collectionId,
        record.layoutVersion.toString(),
        field.id,
        field.localizedLabel(locale),
        field.definition.kind.name,
        field.definition.kind == FieldKind.duration
            ? 'minutes'
            : field.definition.unit ?? '',
        jsonEncode(value),
        _exportDisplay(field.definition.displayValue(value)),
      ],
];

const recordExportHeader = [
  'record_id',
  'collection_id',
  'layout_version',
  'field_id',
  'field_label',
  'type',
  'unit',
  'value_json',
  'display_value',
];

String _exportDisplay(Object value) =>
    value is List ? jsonEncode(value) : value.toString();
