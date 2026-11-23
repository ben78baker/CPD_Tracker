/// A predefined choice is stored as its schema ID. User-entered choices carry
/// the label as recorded, with an ID only when selected from a reusable option.
typedef ChoiceSelection = ({String? id, String? text});

String cleanChoiceLabel(String value) =>
    value.trim().replaceAll(RegExp(r'\s+', unicode: true), ' ');

String choiceLabelKey(String value) => cleanChoiceLabel(value).toLowerCase();

ChoiceSelection? readChoiceSelection(Object? value) {
  if (value is String) return (id: value, text: null);
  if (value is! Map || !value.containsKey('text')) return null;
  final text = value['text'];
  final id = value['id'];
  if (text is! String ||
      text.isEmpty ||
      cleanChoiceLabel(text) != text ||
      (id != null && (id is! String || id.trim().isEmpty)) ||
      value.keys.any((key) => key != 'text' && key != 'id')) {
    return null;
  }
  return (id: id as String?, text: text);
}

Object storeChoiceSelection(ChoiceSelection choice) {
  final text = choice.text;
  if (text == null) return choice.id!;
  return <String, String>{'id': ?choice.id, 'text': text};
}
