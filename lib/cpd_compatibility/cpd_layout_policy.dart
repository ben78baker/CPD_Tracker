import '../recording_engine/models.dart';

const cpdActiveFieldLimit = 20;

/// The existing CPD adapter binds these fields on every record. Title and
/// details are alternative sources of activity text and evidence is optional;
/// the bindings still need to be present for standard editing and exports.
const cpdFieldKinds = {
  'cpd.activityDate': FieldKind.date,
  'cpd.title': FieldKind.text,
  'cpd.details': FieldKind.text,
  'cpd.creditedDuration': FieldKind.duration,
  'cpd.evidence': FieldKind.attachments,
};

Map<String, String> cpdFieldBindings(Iterable<LayoutField> fields) {
  final bindings = <String, String>{};
  for (final field in fields) {
    final id = field.definition.id;
    if (!cpdFieldKinds.containsKey(id)) continue;
    if (cpdFieldKinds[id] != field.definition.kind ||
        bindings.containsKey(id)) {
      throw StateError('A CPD field binding is ambiguous.');
    }
    bindings[id] = field.id;
  }
  if (bindings.length != cpdFieldKinds.length) {
    throw StateError('The layout is missing a protected CPD field.');
  }
  return bindings;
}

void checkCpdLayoutEdit(List<LayoutField> current, List<LayoutField> draft) {
  if (draft.length > cpdActiveFieldLimit) {
    throw ArgumentError('The layout exceeds the CPD field limit.');
  }
  final before = cpdFieldBindings(current);
  final after = cpdFieldBindings(draft);
  final previous = {for (final field in current) field.id: field};
  final next = {for (final field in draft) field.id: field};
  for (final entry in before.entries) {
    final old = previous[entry.value]!;
    final changed = next[after[entry.key]]!;
    if (old.id != changed.id ||
        old.required != changed.required ||
        old.format != changed.format ||
        changed.defaultValue != old.defaultValue ||
        !old.canReviseAs(changed) ||
        old.definition.version != changed.definition.version) {
      throw ArgumentError('A protected CPD field changed meaning.');
    }
  }
}
