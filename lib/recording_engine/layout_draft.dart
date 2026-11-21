import 'models.dart';

/// A disposable working copy. Save through the repository with [baseVersion]
/// as the expected version to prevent stale edits from overwriting a layout.
class LayoutDraft {
  LayoutDraft(LayoutRevision revision, {this.maxActiveFields})
    : collectionId = revision.collectionId,
      baseVersion = revision.version,
      _fields = revision.fields.toList(),
      _headings = revision.headings.toList();

  final String collectionId;
  final int baseVersion;
  final int? maxActiveFields;
  final List<LayoutField> _fields;
  final List<SectionHeading> _headings;
  final _includeExisting = <String>{};

  int get activeFieldCount => _fields.length;
  List<LayoutField> get fields => List.unmodifiable(_fields);
  List<SectionHeading> get headings => List.unmodifiable(_headings);
  Set<String> get includeExisting => Set.unmodifiable(_includeExisting);

  void add(LayoutField field, {bool applyToExisting = false}) {
    final maximum = maxActiveFields;
    if (maximum != null && activeFieldCount >= maximum) {
      throw ArgumentError('The layout exceeds the active field limit.');
    }
    validateLayout([..._fields, field], _headings);
    _fields.add(field);
    if (applyToExisting) _includeExisting.add(field.id);
  }

  /// The destination is the tile's index in the resulting order.
  void move(String id, int destination) {
    RangeError.checkValidIndex(destination, _fields);
    final field = _fields.removeAt(_index(id));
    _fields.insert(destination, field);
  }

  void configure(LayoutField field) {
    final index = _index(field.id);
    if (!_fields[index].canReviseAs(field)) {
      throw ArgumentError('Use a new field ID for a semantic replacement.');
    }
    _fields[index] = field;
  }

  /// Replace a field in place for future records. Earlier revisions still
  /// reference the original identity and values.
  void replace(String id, LayoutField replacement) {
    if (id == replacement.id) {
      throw ArgumentError('A replacement needs a new field ID.');
    }
    final index = _index(id);
    final fields = [..._fields]..[index] = replacement;
    final headings = [
      for (final heading in _headings)
        if (heading.beforeFieldId == id)
          SectionHeading(
            heading.id,
            heading.label,
            beforeFieldId: replacement.id,
          )
        else
          heading,
    ];
    validateLayout(fields, headings);
    _fields[index] = replacement;
    _headings
      ..clear()
      ..addAll(headings);
    _includeExisting.remove(id);
  }

  void retire(String id) {
    _fields.removeAt(_index(id));
    _includeExisting.remove(id);
    // Remove headings anchored to the retired field from this draft.
    _headings.removeWhere((heading) => heading.beforeFieldId == id);
  }

  void setHeadings(Iterable<SectionHeading> headings) {
    final pending = headings.toList();
    validateLayout(_fields, pending);
    _headings
      ..clear()
      ..addAll(pending);
  }

  int _index(String id) {
    final index = _fields.indexWhere((field) => field.id == id);
    if (index < 0) throw ArgumentError.value(id, 'id', 'Unknown field');
    return index;
  }
}
