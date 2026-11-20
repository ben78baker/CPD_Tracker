/// Types supported by the recording foundation. Host-specific meanings are
/// expressed by bindings to field IDs, outside the recording engine.
enum FieldKind { text, date, duration, choice, multipleChoices, attachments }

class FieldDefinition {
  FieldDefinition({
    required this.id,
    required this.version,
    required this.label,
    required this.kind,
    Map<String, String> choices = const {},
    this.multiline = false,
  }) : choices = Map.unmodifiable(choices) {
    if (id.trim().isEmpty || version < 1 || label.trim().isEmpty) {
      throw ArgumentError('A field definition needs an ID, version and label.');
    }
    final selectable =
        kind == FieldKind.choice || kind == FieldKind.multipleChoices;
    if (selectable != choices.isNotEmpty ||
        choices.entries.any(
          (choice) => choice.key.trim().isEmpty || choice.value.trim().isEmpty,
        ) ||
        (multiline && kind != FieldKind.text)) {
      throw ArgumentError('Field configuration does not match its type.');
    }
  }

  final String id;
  final int version;
  final String label;
  final FieldKind kind;
  final bool multiline;

  /// Stable option ID to display label, in presentation order.
  final Map<String, String> choices;

  void validate(Object value) {
    final valid = switch (kind) {
      FieldKind.text => value is String,
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
    };
    if (!valid) throw ArgumentError('Invalid value for field definition $id.');
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
  };

  factory FieldDefinition.fromJson(Map<String, dynamic> json) =>
      FieldDefinition(
        id: json['id'] as String,
        version: json['version'] as int,
        label: json['label'] as String,
        kind: FieldKind.values.byName(json['kind'] as String),
        choices: (json['choices'] as Map).cast<String, String>(),
        multiline: json['multiline'] as bool,
      );
}

bool isCalendarDay(String value) {
  if (!RegExp(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}$').hasMatch(value)) return false;
  final date = DateTime.tryParse(value);
  return date != null &&
      date.year > 0 &&
      date.toIso8601String().startsWith(value);
}

class LayoutField {
  LayoutField({
    required this.id,
    required this.definition,
    this.required = false,
    this.labelOverride,
    this.helpText,
    this.placeholder,
  }) {
    if (id.trim().isEmpty || labelOverride?.trim().isEmpty == true) {
      throw ArgumentError('A field needs an ID and a nonblank label.');
    }
  }

  final String id;
  final FieldDefinition definition;
  final bool required;
  final String? labelOverride;
  final String? helpText;
  final String? placeholder;
  String get label => labelOverride ?? definition.label;

  Map<String, Object?> toJson() => {
    'id': id,
    'definition': definition.toJson(),
    'required': required,
    'labelOverride': labelOverride,
    'helpText': helpText,
    'placeholder': placeholder,
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
  );
}

/// An immutable recipe. Field IDs are recipe-local until the recipe is applied.
class TemplateVersion {
  TemplateVersion({
    required this.id,
    required this.version,
    required this.label,
    required Iterable<LayoutField> fields,
  }) : fields = List.unmodifiable(fields) {
    if (id.trim().isEmpty || version < 1 || label.trim().isEmpty) {
      throw ArgumentError('A template needs an ID, version and label.');
    }
    _checkFieldIds(this.fields);
  }

  final String id;
  final int version;
  final String label;
  final List<LayoutField> fields;
}

class LayoutRevision {
  LayoutRevision({
    required this.collectionId,
    required this.version,
    required Iterable<LayoutField> fields,
    Iterable<String> includeExisting = const [],
    this.templateId,
    this.templateVersion,
  }) : fields = List.unmodifiable(fields),
       includeExisting = Set.unmodifiable(includeExisting) {
    _checkFieldIds(this.fields);
    if (collectionId.trim().isEmpty ||
        version < 1 ||
        !this.includeExisting.every(
          this.fields.map((field) => field.id).contains,
        ) ||
        (templateId == null) != (templateVersion == null)) {
      throw ArgumentError('Invalid layout revision.');
    }
  }

  final String collectionId;
  final int version;
  final List<LayoutField> fields;
  final Set<String> includeExisting;
  final String? templateId;
  final int? templateVersion;
}

void _checkFieldIds(List<LayoutField> fields) {
  if (fields.map((field) => field.id).toSet().length != fields.length) {
    throw ArgumentError('Field IDs must be unique within a layout.');
  }
}

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
          fields.putIfAbsent(field.id, () => field);
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
}
