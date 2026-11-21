enum ReportBranding { standard, subtle, attribution, none }

typedef DocumentField = ({String label, String value});
typedef DocumentActivity = ({
  String title,
  String status,
  List<DocumentField> fields,
});
typedef DocumentReference = ({String label, String? url});

/// An activity document prepared for the recipient. The same data can be fed
/// to different presentation backends without changing report calculations.
class ActivityDocumentData {
  const ActivityDocumentData({
    required this.title,
    required this.appName,
    required this.attribution,
    required this.documentTag,
    required this.summaryTitle,
    required this.metadata,
    required this.summary,
    required this.activities,
    required this.evidenceTitle,
    required this.evidence,
    required this.continued,
    required this.pageOf,
    this.summaryColumns = const [],
    this.summaryRows = const [],
    this.branding = ReportBranding.subtle,
  });

  final String title,
      appName,
      attribution,
      documentTag,
      summaryTitle,
      evidenceTitle;
  final List<String> metadata, summary, summaryColumns;
  final List<List<String>> summaryRows;
  final List<DocumentActivity> activities;
  final List<DocumentReference> evidence;
  final String Function(String) continued;
  final String Function(int, int) pageOf;
  final ReportBranding branding;

  String get footer => [
    switch (branding) {
      ReportBranding.standard || ReportBranding.subtle => appName,
      ReportBranding.attribution => attribution,
      ReportBranding.none => '',
    },
    documentTag,
  ].where((value) => value.isNotEmpty).join(' · ');
}
