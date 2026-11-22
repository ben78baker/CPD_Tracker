import 'fields.dart';
import 'layout_details.dart';

export 'fields.dart';
export 'layout_details.dart';

class LayoutField {
  LayoutField({
    required this.id,
    required this.definition,
    this.required = false,
    this.labelOverride,
    this.helpText,
    this.placeholder,
    this.format = FieldFormat.standard,
    this.source,
    Object? defaultValue,
  }) : defaultValue = defaultValue is List
           ? List<Object?>.unmodifiable(defaultValue)
           : defaultValue {
    if (id.trim().isEmpty || labelOverride?.trim().isEmpty == true) {
      throw ArgumentError('A field needs an ID and a nonblank label.');
    }
    if ((format == FieldFormat.checkbox &&
            definition.kind != FieldKind.boolean) ||
        (format == FieldFormat.photograph &&
            definition.kind != FieldKind.attachments)) {
      throw ArgumentError('The format does not match the field type.');
    }
    if (this.defaultValue case final value?) {
      if (definition.kind == FieldKind.attachments) {
        throw ArgumentError('An attachment must be selected for each record.');
      }
      definition.validate(value);
    }
  }

  final String id;
  final FieldDefinition definition;
  final bool required;
  final String? labelOverride;
  final String? helpText;
  final String? placeholder;
  final Object? defaultValue;
  final FieldFormat format;
  final LibrarySource? source;
  String get label => labelOverride ?? definition.label;
  String localizedLabel(String? locale) =>
      labelOverride ?? definition.localizedLabel(locale);

  bool canReviseAs(LayoutField replacement) =>
      id == replacement.id &&
      source?.id == replacement.source?.id &&
      source?.version == replacement.source?.version &&
      definition.hasSameValueMeaning(replacement.definition) &&
      definition.version <= replacement.definition.version;

  LayoutField reidentify(String newId, {bool? required}) => LayoutField(
    id: newId,
    definition: definition,
    required: required ?? this.required,
    labelOverride: labelOverride,
    helpText: helpText,
    placeholder: placeholder,
    format: format,
    source: source,
    defaultValue: defaultValue,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'definition': definition.toJson(),
    'required': required,
    'labelOverride': labelOverride,
    'helpText': helpText,
    'placeholder': placeholder,
    if (format != FieldFormat.standard) 'format': format.name,
    if (source case final library?) 'source': library.toJson(),
    if (defaultValue != null) 'defaultValue': defaultValue,
  };

  factory LayoutField.fromJson(Map<String, dynamic> json) => LayoutField(
    id: json['id'] as String,
    definition: FieldDefinition.fromJson(
      json['definition'] as Map<String, dynamic>,
    ),
    required: json['required'] as bool,
    labelOverride: json['labelOverride'] as String?,
    helpText: json['helpText'] as String?,
    placeholder: json['placeholder'] as String?,
    format: FieldFormat.values.byName(json['format'] as String? ?? 'standard'),
    source: json['source'] == null
        ? null
        : LibrarySource.fromJson(json['source'] as Map<String, dynamic>),
    defaultValue: json['defaultValue'],
  );
}

/// An immutable recipe. Field IDs are recipe-local until the recipe is applied.
class TemplateVersion {
  TemplateVersion({
    required this.id,
    required this.version,
    required this.label,
    required Iterable<LayoutField> fields,
    Iterable<SectionHeading> headings = const [],
    this.origin = TemplateOrigin.user,
    this.description,
    Map<String, String> translations = const {},
    Map<String, String> descriptionTranslations = const {},
  }) : fields = List.unmodifiable(fields),
       headings = List.unmodifiable(headings),
       translations = Map.unmodifiable(translations),
       descriptionTranslations = Map.unmodifiable(descriptionTranslations) {
    if (id.trim().isEmpty || version < 1 || label.trim().isEmpty) {
      throw ArgumentError('A template needs an ID, version and label.');
    }
    validateLayout(this.fields, this.headings);
  }

  final String id;
  final int version;
  final String label;
  final List<LayoutField> fields;
  final List<SectionHeading> headings;
  final TemplateOrigin origin;
  final String? description;
  final Map<String, String> translations;
  final Map<String, String> descriptionTranslations;

  String localizedLabel(String? locale) =>
      localize(label, translations, locale);
  String localizedDescription(String? locale) =>
      localize(description ?? '', descriptionTranslations, locale);

  Map<String, Object?> settingsToJson() => {
    if (origin != TemplateOrigin.user) 'origin': origin.name,
    if (description != null) 'description': description,
    if (translations.isNotEmpty) 'translations': translations,
    if (descriptionTranslations.isNotEmpty)
      'descriptionTranslations': descriptionTranslations,
    if (headings.isNotEmpty) 'headings': [for (final h in headings) h.toJson()],
  };
}

class LayoutRevision {
  LayoutRevision({
    required this.collectionId,
    required this.version,
    required Iterable<LayoutField> fields,
    Iterable<String> includeExisting = const [],
    Iterable<SectionHeading> headings = const [],
    this.templateId,
    this.templateVersion,
  }) : fields = List.unmodifiable(fields),
       headings = List.unmodifiable(headings),
       includeExisting = Set.unmodifiable(includeExisting) {
    validateLayout(this.fields, this.headings);
    if (collectionId.trim().isEmpty ||
        version < 1 ||
        !this.includeExisting.every(
          this.fields.map((field) => field.id).contains,
        ) ||
        (templateId == null) != (templateVersion == null) ||
        templateId?.trim().isEmpty == true ||
        (templateVersion != null && templateVersion! < 1)) {
      throw ArgumentError('Invalid layout revision.');
    }
  }

  final String collectionId;
  final int version;
  final List<LayoutField> fields;
  final List<SectionHeading> headings;
  final Set<String> includeExisting;
  final String? templateId;
  final int? templateVersion;
}

void validateLayout(List<LayoutField> fields, List<SectionHeading> headings) {
  final ids = fields.map((field) => field.id).toSet();
  if (ids.length != fields.length) {
    throw ArgumentError('Field IDs must be unique within a layout.');
  }
  for (final heading in headings) {
    if (!ids.add(heading.id) ||
        (heading.beforeFieldId != null &&
            !fields.any((field) => field.id == heading.beforeFieldId))) {
      throw ArgumentError(
        'Section headings require unique IDs and valid anchors.',
      );
    }
  }
}

/// Defaults are an explicit new-record operation. Historical edits resolve
/// original field definitions and do not call this helper.
Map<String, Object> initialFieldValues(Iterable<LayoutField> fields) => {
  for (final field in fields) field.id: ?field.defaultValue,
};

/// Resolves the original field meanings and applies only explicitly
/// retrospective additions. Labels and choices are from the applicable snapshot.
List<LayoutField> resolveFields(
  int creationVersion,
  Iterable<LayoutRevision> orderedRevisions,
) {
  final fields = <String, LayoutField>{};
  var hasCreationVersion = false;
  for (final revision in orderedRevisions) {
    if (revision.version == creationVersion) {
      hasCreationVersion = true;
      fields.addEntries(
        revision.fields.map((field) => MapEntry(field.id, field)),
      );
    } else if (revision.version > creationVersion) {
      for (final field in revision.fields) {
        if (revision.includeExisting.contains(field.id)) {
          fields.putIfAbsent(
            field.id,
            () => field.required
                ? field.reidentify(field.id, required: false)
                : field,
          );
        }
      }
    }
  }
  if (!hasCreationVersion) {
    throw StateError('Record creation revision is missing.');
  }
  return List.unmodifiable(fields.values);
}

class RecordingCollection {
  const RecordingCollection(
    this.id,
    this.label,
    this.layoutVersion, {
    this.deleted = false,
  });

  final String id;
  final String label;
  final int layoutVersion;
  final bool deleted;
}

class RecordingRecord {
  RecordingRecord({
    required this.id,
    required this.collectionId,
    required this.layoutVersion,
    required this.version,
    required this.deleted,
    required Map<String, Object> values,
  }) : values = Map.unmodifiable(
         values.map(
           (key, value) => MapEntry(
             key,
             value is List ? List<Object?>.unmodifiable(value) : value,
           ),
         ),
       );

  final String id;
  final String collectionId;
  final int layoutVersion;
  final int version;
  final bool deleted;
  final Map<String, Object> values;

  List<Object?> project(Iterable<LayoutField> fields) => [
    for (final field in fields)
      if (values[field.id] case final value?)
        field.definition.displayValue(value)
      else
        null,
  ];

  bool matches(String query, Iterable<LayoutField> fields) {
    final needle = query.trim().toLowerCase();
    return needle.isEmpty ||
        project(fields).whereType<Object>().any(
          (value) => value.toString().toLowerCase().contains(needle),
        );
  }
}

enum AttachmentKind { managed, link, unresolved }

class RecordingAttachment {
  RecordingAttachment({
    required this.id,
    required this.kind,
    required this.locator,
    required this.name,
    this.originalFingerprint,
  }) {
    if (id.trim().isEmpty ||
        name.trim().isEmpty ||
        (kind != AttachmentKind.unresolved && locator.trim().isEmpty)) {
      throw ArgumentError('Invalid attachment reference.');
    }
    if (kind == AttachmentKind.managed &&
        (locator.contains(r'\') ||
            locator.contains(':') ||
            locator.contains('\u0000') ||
            locator
                .split('/')
                .any((part) => part.isEmpty || part == '.' || part == '..'))) {
      throw ArgumentError('Managed attachment paths must be relative.');
    }
  }

  final String id;
  final AttachmentKind kind;
  final String locator;
  final String name;
  final String? originalFingerprint;
}
