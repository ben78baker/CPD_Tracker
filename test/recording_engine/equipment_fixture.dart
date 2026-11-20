import 'package:cpd_tracker/recording_engine/models.dart';

TemplateVersion equipmentTemplate(int version) => TemplateVersion(
  id: 'equipment-service',
  version: version,
  label: 'Equipment maintenance',
  fields: [
    _field('asset', 'Equipment ID', FieldKind.text, required: true),
    _field('technician', 'Technician', FieldKind.text),
    _field('inspection', 'Inspection date', FieldKind.date),
    _field('next', 'Next inspection due', FieldKind.date),
    _field('location', 'Location', FieldKind.text),
    _field('notes', 'Service notes', FieldKind.text, multiline: true),
    LayoutField(
      id: 'result',
      required: true,
      definition: FieldDefinition(
        id: 'result',
        version: version,
        label: 'Inspection result',
        kind: FieldKind.choice,
        choices: {
          'pass': version == 1 ? 'Passed' : 'Ready to use',
          if (version == 1) 'monitor': 'Monitor',
          'fail': 'Out of service',
        },
      ),
    ),
    _field('evidence', 'Evidence', FieldKind.attachments),
  ],
);

LayoutField _field(
  String id,
  String label,
  FieldKind kind, {
  bool required = false,
  bool multiline = false,
}) => LayoutField(
  id: id,
  required: required,
  definition: FieldDefinition(
    id: id,
    version: 1,
    label: label,
    kind: kind,
    multiline: multiline,
  ),
);
