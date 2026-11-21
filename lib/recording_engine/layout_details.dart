/// Presentation is a small list of supported controls. A photo picker still
/// stores attachment IDs and a checkbox still stores a Boolean.
enum FieldFormat { standard, checkbox, photograph }

enum TemplateOrigin { user, bundled }

class LibrarySource {
  LibrarySource(this.id, this.version) {
    if (id.trim().isEmpty || version < 1) {
      throw ArgumentError('A library source needs an ID and version.');
    }
  }

  final String id;
  final int version;

  Map<String, Object> toJson() => {'id': id, 'version': version};
  factory LibrarySource.fromJson(Map<String, dynamic> json) =>
      LibrarySource(json['id'] as String, json['version'] as int);
}

/// A separate presentation element. Null places the heading after all fields.
/// The anchor travels with a field when it is reordered.
class SectionHeading {
  SectionHeading(this.id, this.label, {this.beforeFieldId}) {
    if (id.trim().isEmpty || label.trim().isEmpty) {
      throw ArgumentError('A section heading needs an ID and label.');
    }
  }
  final String id;
  final String label;
  final String? beforeFieldId;

  Map<String, Object?> toJson() => {
    'id': id,
    'label': label,
    'beforeFieldId': beforeFieldId,
  };
  factory SectionHeading.fromJson(Map<String, dynamic> json) => SectionHeading(
    json['id'] as String,
    json['label'] as String,
    beforeFieldId: json['beforeFieldId'] as String?,
  );
}

List<SectionHeading> readHeadings(Object? json) => [
  for (final heading in (json as List?) ?? const [])
    SectionHeading.fromJson(heading as Map<String, dynamic>),
];
