import 'dart:convert';
import 'dart:typed_data';

import 'package:cpd_tracker/recording_reports/activity_document_data.dart';

/// A renderer experiment for shared report data. This runs in isolated
/// rehearsals. Its only resources are the supplied local font bytes.
String buildShapingProbeHtml(
  ActivityDocumentData data, {
  required String languageTag,
  required Map<String, ByteData> fonts,
}) {
  const escape = HtmlEscape();
  String esc(String value) => escape.convert(value);
  String face(String name, String family, int weight) {
    final font = fonts[name]!;
    final src = base64Encode(
      font.buffer.asUint8List(font.offsetInBytes, font.lengthInBytes),
    );
    return "@font-face{font-family:$family;src:url('data:font/ttf;base64,$src') format('truetype');font-weight:$weight}";
  }

  String link(DocumentReference reference) {
    final url = reference.url;
    final uri = url == null ? null : Uri.tryParse(url);
    if (uri == null ||
        !uri.hasAuthority ||
        !{'http', 'https'}.contains(uri.scheme)) {
      return esc(reference.label);
    }
    return '<a href="${esc(url!)}">${esc(reference.label)}</a>';
  }

  String cells(String tag, List<String> values) =>
      values.map((value) => '<$tag>${esc(value)}</$tag>').join();
  final headings = data.summaryColumns.isEmpty
      ? ''
      : '<table class="summary"><thead><tr>${cells('th', data.summaryColumns)}</tr></thead>'
            '<tbody>${data.summaryRows.map((row) => '<tr>${cells('td', row)}</tr>').join()}</tbody></table>';

  final sections = [
    for (final activity in data.activities)
      '<table class="activity"><thead><tr><th scope="col">${esc(activity.title)}</th></tr></thead>'
          '<tbody>'
          '${activity.status.isEmpty ? '' : '<tr><td class="status">${esc(activity.status)}</td></tr>'}'
          '${activity.fields.map((field) => '<tr><td><b>${esc(field.label)}</b> ${esc(field.value)}</td></tr>').join()}'
          '</tbody></table>',
  ].join();

  return '''<!doctype html>
<html lang="${esc(languageTag)}">
<head>
<meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; base-uri 'none'; style-src 'unsafe-inline'; font-src data:">
<title>${esc(data.title)}</title>
<style>
${face('Latin-Regular', 'ReportLatin', 400)}
${face('Latin-Bold', 'ReportLatin', 700)}
${face('Devanagari-Regular', 'ReportIndic', 400)}
${face('Devanagari-Bold', 'ReportIndic', 700)}
@page { size: A4; margin: 13mm 14mm; }
body { color:#182536; font: 10pt/1.47 ReportLatin,ReportIndic,sans-serif; margin:0;
       overflow-wrap: anywhere; word-break: normal; }
h1 { font-size:20pt; line-height:1.22; margin:0 0 8pt; }
h2 { font-size:12pt; margin:12pt 0 4pt; break-after:avoid; }
p { margin:3pt 0; white-space:pre-wrap; }
table { width:100%; border-collapse:collapse; table-layout:fixed; }
thead { display:table-header-group; break-inside:avoid; }
td,th { padding:2pt 4pt; text-align:start; white-space:pre-wrap; vertical-align:top; }
.summary { margin:4pt 0; }
.summary th { border-bottom:1px solid #6a7280; }
.activity { margin:10pt 0 0; }
.activity th { font-size:12pt; border-top:1px solid #9ba6b4; padding-top:6pt; }
.activity .status { color:#4a3a32; }
.activity td { orphans:2; widows:2; }
footer { border-top:1px solid #9ba6b4; padding-top:5pt; font-size:8pt; color:#465568; }
a { color:#364e67; }
</style>
</head>
<body>
<h1>${esc(data.title)}</h1>
${data.metadata.map((line) => '<p>${esc(line)}</p>').join()}
<h2>${esc(data.summaryTitle)}</h2>$headings
${data.summary.map((line) => '<p>${esc(line)}</p>').join()}
$sections
${data.evidence.isEmpty ? '' : '<h2>${esc(data.evidenceTitle)}</h2>${data.evidence.map((item) => '<p>${link(item)}</p>').join()}'}
${data.footer.isEmpty ? '' : '<footer>${esc(data.footer)}</footer>'}
</body></html>''';
}
