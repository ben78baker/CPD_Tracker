import 'package:cpd_tracker/l10n/app_localizations.dart';
import 'package:cpd_tracker/widgets/share_format_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('offers both PDF modes, ZIP and CSV with clear wording', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                selected = await showShareFormatSheet(context);
              },
              child: const Text('Open formats'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open formats'));
    await tester.pumpAndSettle();

    expect(find.text('CSV (editable)'), findsOneWidget);
    expect(find.text('PDF without embedded evidence'), findsOneWidget);
    expect(
      find.text('Professional record with an evidence list'),
      findsOneWidget,
    );
    expect(find.text('PDF with photographic evidence'), findsOneWidget);
    expect(
      find.text('Adds supported photos on dedicated evidence pages'),
      findsOneWidget,
    );
    expect(find.text('PDF + original attachments (ZIP)'), findsOneWidget);
    expect(
      find.text('Text-only PDF and original supporting files'),
      findsOneWidget,
    );

    await tester.tap(find.text('PDF with photographic evidence'));
    await tester.pumpAndSettle();
    expect(selected, 'pdf_evidence');
  });
}
