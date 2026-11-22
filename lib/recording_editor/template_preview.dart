import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../recording_engine/models.dart';
import 'record_form.dart';
import 'strings.dart';

/// Both the editor preview and the future pre-purchase route use this
/// memory-only page. It takes values and sample labels, with no write API.
class SandboxFormPage extends StatefulWidget {
  const SandboxFormPage({
    super.key,
    required this.title,
    required this.fields,
    this.headings = const [],
    this.example = const {},
    this.interactive = true,
    this.sampleAttachmentLabel,
  });

  final String title;
  final List<LayoutField> fields;
  final List<SectionHeading> headings;
  final Map<String, Object> example;
  final bool interactive;
  final String? sampleAttachmentLabel;

  @override
  State<SandboxFormPage> createState() => _SandboxFormPageState();
}

class _SandboxFormPageState extends State<SandboxFormPage> {
  late final _values = <String, Object>{...widget.example};
  static const _sampleEvidence = 'preview.sample';

  @override
  Widget build(BuildContext context) {
    final s = editorStrings(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: BoundedList(
        children: [
          if (widget.interactive)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(s.editorPreviewNotice),
            ),
          RecordingForm(
            fields: widget.fields,
            headings: widget.headings,
            values: _values,
            sampleAttachmentId: widget.interactive ? _sampleEvidence : null,
            attachmentLabels: {
              _sampleEvidence:
                  widget.sampleAttachmentLabel ?? s.editorSampleFile,
            },
            onChanged: !widget.interactive
                ? null
                : (id, value) => setState(() {
                    if (value == null) {
                      _values.remove(id);
                    } else {
                      _values[id] = value;
                    }
                  }),
          ),
        ],
      ),
    );
  }
}

/// Metadata and sample data are authored for this recipe version. This
/// presentation contract has no store, entitlement, file or activation APIs.
class TemplatePreviewExample {
  TemplatePreviewExample(this.label, Map<String, Object> values)
    : values = Map.unmodifiable(
        values.map(
          (key, value) => MapEntry(
            key,
            value is List ? List<Object?>.unmodifiable(value) : value,
          ),
        ),
      );
  final String label;
  final Map<String, Object> values;
}

class TemplatePreviewPage extends StatelessWidget {
  TemplatePreviewPage({
    super.key,
    required this.template,
    required this.profession,
    required this.country,
    required this.professionalBody,
    required this.scheme,
    required this.reviewed,
    required Iterable<String> featuresAndLimits,
    required Iterable<TemplatePreviewExample> examples,
    this.sampleReport,
    this.onReportError,
    this.sampleAttachmentLabel,
    this.arrangementPreview,
    this.footer,
  }) : examples = List.unmodifiable(examples),
       featuresAndLimits = List.unmodifiable(featuresAndLimits) {
    final fields = {for (final field in template.fields) field.id: field};
    for (final example in this.examples) {
      for (final entry in example.values.entries) {
        final field = fields[entry.key];
        if (field == null) {
          throw ArgumentError('A preview example refers to another layout.');
        }
        field.definition.validate(entry.value);
      }
    }
  }

  final TemplateVersion template;
  final String profession;
  final String country;
  final String professionalBody;
  final String scheme;
  final DateTime reviewed;
  final List<String> featuresAndLimits;
  final List<TemplatePreviewExample> examples;
  final Future<Uint8List> Function(
    TemplateVersion template,
    TemplatePreviewExample example,
  )?
  sampleReport;
  final String? sampleAttachmentLabel;
  final Widget Function(BuildContext, Object)? onReportError;
  final WidgetBuilder? arrangementPreview;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final s = editorStrings(context);
    final displayDate = MaterialLocalizations.of(
      context,
    ).formatFullDate(reviewed);
    final language = Localizations.localeOf(context).toLanguageTag();
    return Scaffold(
      appBar: AppBar(title: Text(s.editorTemplateDetails)),
      body: BoundedList(
        children: [
          Text(
            template.localizedLabel(language),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(template.localizedDescription(language)),
          ),
          for (final (label, value) in [
            (s.editorProfession, profession),
            (s.editorCountry, country),
            (s.editorBody, professionalBody),
            (s.editorScheme, scheme),
            (s.editorVersion, template.version.toString()),
            (s.editorReviewed, displayDate),
          ])
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(label),
              subtitle: Text(value),
            ),
          for (final item in featuresAndLimits)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(item),
            ),
          if (footer case final Widget actions) ...[
            actions,
            const SizedBox(height: 12),
          ],
          FilledButton.icon(
            icon: const Icon(Icons.edit_note),
            label: Text(s.editorTry),
            onPressed: () => _open(
              context,
              (_) => SandboxFormPage(
                title: s.editorTry,
                fields: template.fields,
                headings: template.headings,
                example: initialFieldValues(template.fields),
                sampleAttachmentLabel: sampleAttachmentLabel,
              ),
            ),
          ),
          if (arrangementPreview case final builder?)
            OutlinedButton.icon(
              icon: const Icon(Icons.tune),
              label: Text(s.p6TryArrangement),
              onPressed: () => _open(context, builder),
            ),
          for (final example in examples)
            ListTile(
              leading: const Icon(Icons.assignment_outlined),
              title: Text(example.label),
              subtitle: Text(s.editorExample),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(
                context,
                (_) => SandboxFormPage(
                  title: example.label,
                  fields: template.fields,
                  headings: template.headings,
                  example: example.values,
                  sampleAttachmentLabel: sampleAttachmentLabel,
                  interactive: false,
                ),
              ),
            ),
          if (sampleReport case final buildReport? when examples.isNotEmpty)
            OutlinedButton.icon(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: Text(s.editorExamplePdf),
              onPressed: () => _open(
                context,
                (_) => Scaffold(
                  appBar: AppBar(title: Text(s.editorExamplePdf)),
                  body: PdfPreview(
                    build: (_) => buildReport(template, examples.first),
                    onError: onReportError,
                    initialPageFormat: PdfPageFormat.a4,
                    allowPrinting: false,
                    allowSharing: false,
                    canChangePageFormat: false,
                    canChangeOrientation: false,
                    canDebug: false,
                    useActions: false,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _open(BuildContext context, WidgetBuilder builder) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: builder));
}

class BoundedList extends StatelessWidget {
  const BoundedList({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: ListView(padding: const EdgeInsets.all(16), children: children),
    ),
  );
}
