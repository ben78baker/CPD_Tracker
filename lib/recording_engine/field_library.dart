import 'models.dart';

class LibraryFieldVersion {
  LibraryFieldVersion({
    required this.source,
    required this.prototype,
    required this.category,
    required this.description,
    Map<String, String> descriptionTranslations = const {},
    Iterable<String> keywords = const [],
    Iterable<String> tags = const [],
    this.reference,
  }) : descriptionTranslations = Map.unmodifiable(descriptionTranslations),
       keywords = List.unmodifiable(keywords),
       tags = Set.unmodifiable(tags) {
    if (category.trim().isEmpty ||
        description.trim().isEmpty ||
        prototype.source != null) {
      throw ArgumentError(
        'A library item needs standalone catalogue metadata.',
      );
    }
  }

  final LibrarySource source;
  final LayoutField prototype;
  final String category;
  final String description;
  final Map<String, String> descriptionTranslations;
  final List<String> keywords;
  final Set<String> tags;
  final String? reference;

  String localizedDescription(String? locale) =>
      localize(description, descriptionTranslations, locale);

  LayoutField instantiate(String fieldId) => LayoutField(
    id: fieldId,
    definition: prototype.definition,
    required: prototype.required,
    labelOverride: prototype.labelOverride,
    helpText: prototype.helpText,
    placeholder: prototype.placeholder,
    format: prototype.format,
    source: source,
    defaultValue: prototype.defaultValue,
  );
}

/// The installed catalogue offers the latest revisions and retains exact
/// versions for hosts that choose to ship them.
class FieldLibrary {
  FieldLibrary(
    Iterable<LibraryFieldVersion> versions, {
    required Map<String, Map<String, String>> categories,
  }) : _categories = Map.unmodifiable(
         categories.map(
           (id, labels) =>
               MapEntry(id, Map<String, String>.unmodifiable(labels)),
         ),
       ) {
    for (final entry in versions) {
      if (!_categories.containsKey(entry.category)) {
        throw ArgumentError('Unknown field category: ${entry.category}');
      }
      final source = entry.source;
      final versions = _entries.putIfAbsent(source.id, () => {});
      if (versions.containsKey(source.version)) {
        throw ArgumentError('Duplicate library version: ${source.id}');
      }
      versions[source.version] = entry;
      final previous = _latest[source.id];
      if (previous == null || previous.source.version < source.version) {
        _latest[source.id] = entry;
      }
    }
  }

  final Map<String, Map<String, String>> _categories;
  final _entries = <String, Map<int, LibraryFieldVersion>>{};
  final _latest = <String, LibraryFieldVersion>{};

  Iterable<String> get categoryIds => _categories.keys;
  String categoryLabel(String id, {String? locale}) {
    final names = _categories[id] ?? const <String, String>{};
    return localize(names['en'] ?? id, names, locale);
  }

  LibraryFieldVersion? load(String id, int version) => _entries[id]?[version];

  List<LibraryFieldVersion> search(
    String query, {
    String? locale,
    String? category,
    String? tag,
  }) {
    final terms = query.toLowerCase().trim().split(RegExp(r'\s+'));
    return [
      for (final entry in _latest.values)
        if ((category == null || entry.category == category) &&
            (tag == null || entry.tags.contains(tag)) &&
            terms.every(_searchText(entry, locale).contains))
          entry,
    ];
  }

  String _searchText(LibraryFieldVersion entry, String? locale) => [
    entry.prototype.localizedLabel(locale),
    entry.prototype.label,
    entry.localizedDescription(locale),
    entry.description,
    entry.category,
    categoryLabel(entry.category, locale: locale),
    ...entry.keywords,
    ...entry.tags,
  ].join(' ').toLowerCase();
}
