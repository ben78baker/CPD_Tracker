/// Types supported by the recording foundation. Hosts bind their own business
/// concepts to definition IDs. Decimals persist as exact base-10 strings.
enum FieldKind {
  text,
  date,
  duration,
  choice,
  multipleChoices,
  attachments,
  integer,
  decimal,
  boolean,
  url,
}

class FieldDefinition {
  FieldDefinition({
    required this.id,
    required this.version,
    required this.label,
    required this.kind,
    Map<String, String> choices = const {},
    this.multiline = false,
    this.unit,
    this.decimalPlaces,
    this.maxLength,
    this.nonNegative = false,
    this.description,
    Map<String, String> translations = const {},
  }) : choices = Map.unmodifiable(choices),
       translations = Map.unmodifiable(translations) {
    if (id.trim().isEmpty || version < 1 || label.trim().isEmpty) {
      throw ArgumentError('A field definition needs an ID, version and label.');
    }
    final selectable =
        kind == FieldKind.choice || kind == FieldKind.multipleChoices;
    final numeric = kind == FieldKind.integer || kind == FieldKind.decimal;
    if (selectable != choices.isNotEmpty ||
        choices.entries.any(
          (choice) => choice.key.trim().isEmpty || choice.value.trim().isEmpty,
        ) ||
        (multiline && kind != FieldKind.text) ||
        (unit != null && (!numeric || unit!.trim().isEmpty)) ||
        (nonNegative && !numeric) ||
        (maxLength != null && (kind != FieldKind.text || maxLength! < 1)) ||
        ((decimalPlaces != null) != (kind == FieldKind.decimal)) ||
        (decimalPlaces != null &&
            (decimalPlaces! < 0 || decimalPlaces! > 12))) {
      throw ArgumentError('Field configuration does not match its type.');
    }
  }

  final String id;
  final int version;
  final String label;
  final FieldKind kind;
  final bool multiline;
  final String? unit;
  final int? decimalPlaces;
  final int? maxLength;
  final bool nonNegative;
  final String? description;
  final Map<String, String> translations;

  /// Stable option ID to display label, in presentation order.
  final Map<String, String> choices;

  String localizedLabel(String? locale) =>
      localize(label, translations, locale);

  /// Layouts can version labels, validation and choices without changing the
  /// identity of the value. Units, precision and type require replacement.
  bool hasSameValueMeaning(FieldDefinition other) =>
      id == other.id &&
      kind == other.kind &&
      unit == other.unit &&
      decimalPlaces == other.decimalPlaces;

  void validate(Object value) {
    final valid = switch (kind) {
      FieldKind.text =>
        value is String &&
            (maxLength == null || value.runes.length <= maxLength!),
      FieldKind.date => value is String && isCalendarDay(value),
      FieldKind.duration => value is int && value >= 0,
      FieldKind.choice => value is String && choices.containsKey(value),
      FieldKind.multipleChoices =>
        value is List &&
            value.isNotEmpty &&
            value.toSet().length == value.length &&
            value.every(choices.containsKey),
      FieldKind.attachments =>
        value is List &&
            value.isNotEmpty &&
            value.every((id) => id is String && id.trim().isNotEmpty),
      FieldKind.integer => value is int && (!nonNegative || value >= 0),
      FieldKind.decimal => value is String && _validDecimal(value),
      FieldKind.boolean => value is bool,
      FieldKind.url => value is String && _isHttpUrl(value),
    };
    if (!valid) throw ArgumentError('Invalid value for field definition $id.');
  }

  bool _validDecimal(String value) {
    if (value.length > 40 ||
        !_decimal.hasMatch(value) ||
        (nonNegative && value.startsWith('-'))) {
      return false;
    }
    return (value.split('.').elementAtOrNull(1)?.length ?? 0) <= decimalPlaces!;
  }

  Object displayValue(Object value) => switch (kind) {
    FieldKind.choice => choices[value]!,
    FieldKind.multipleChoices => List<String>.unmodifiable(
      (value as List).map((id) => choices[id]!),
    ),
    _ => value,
  };

  Map<String, Object?> toJson() => {
    'id': id,
    'version': version,
    'label': label,
    'kind': kind.name,
    'choices': choices,
    'multiline': multiline,
    if (unit != null) 'unit': unit,
    if (decimalPlaces != null) 'decimalPlaces': decimalPlaces,
    if (maxLength != null) 'maxLength': maxLength,
    if (nonNegative) 'nonNegative': true,
    if (description != null) 'description': description,
    if (translations.isNotEmpty) 'translations': translations,
  };

  factory FieldDefinition.fromJson(Map<String, dynamic> json) =>
      FieldDefinition(
        id: json['id'] as String,
        version: json['version'] as int,
        label: json['label'] as String,
        kind: FieldKind.values.byName(json['kind'] as String),
        choices: (json['choices'] as Map).cast<String, String>(),
        multiline: json['multiline'] as bool,
        unit: json['unit'] as String?,
        decimalPlaces: json['decimalPlaces'] as int?,
        maxLength: json['maxLength'] as int?,
        nonNegative: json['nonNegative'] as bool? ?? false,
        description: json['description'] as String?,
        translations: readTranslations(json['translations']),
      );

  static final _decimal = RegExp(r'^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$');
}

bool _isHttpUrl(String value) {
  if (value.contains(RegExp(r'\s|[\x00-\x1f]'))) return false;
  final uri = Uri.tryParse(value);
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

bool isCalendarDay(String value) {
  if (!RegExp(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}$').hasMatch(value)) return false;
  final date = DateTime.tryParse(value);
  return date != null &&
      date.year > 0 &&
      date.toIso8601String().startsWith(value);
}

Map<String, String> readTranslations(Object? json) =>
    (json as Map?)?.cast<String, String>() ?? const {};

/// Catalogue keys use lower-case BCP 47 language tags.
String localize(
  String fallback,
  Map<String, String> translations,
  String? locale,
) {
  if (locale == null) return fallback;
  final tag = locale.toLowerCase().replaceAll('_', '-');
  return translations[tag] ?? translations[tag.split('-').first] ?? fallback;
}
