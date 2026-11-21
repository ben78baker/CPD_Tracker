import 'dart:math' as math;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// A shared PDF text block that gives each subsequent page its activity title.
class ContinuingPdfText extends pw.RichText {
  ContinuingPdfText({
    required super.text,
    required this.continuationLabel,
    required this.continuationStyle,
  }) : super(overflow: pw.TextOverflow.span);

  final String continuationLabel;
  final pw.TextStyle continuationStyle;

  pw.Text? _label;
  double _contentHeight = 0;
  double _labelGap = 0;

  @override
  void layout(
    pw.Context context,
    pw.BoxConstraints constraints, {
    bool parentUsesSize = false,
  }) {
    final textContext = saveContext() as pw.RichTextContext;
    final isContinuation =
        textContext.spanStart > 0 || textContext.startOffset != 0;

    _label = isContinuation
        ? pw.Text(
            continuationLabel,
            maxLines: 2,
            overflow: pw.TextOverflow.clip,
            style: continuationStyle,
          )
        : null;
    _labelGap = _label == null ? 0 : 6;

    var labelHeight = 0.0;
    if (_label != null) {
      _label!.layout(
        context,
        constraints.copyWith(maxHeight: double.infinity),
        parentUsesSize: true,
      );
      labelHeight = _label!.box!.height;
    }

    final reservedHeight = labelHeight + _labelGap;
    super.layout(
      context,
      constraints.copyWith(
        minHeight: 0,
        maxHeight: math.max(0, constraints.maxHeight - reservedHeight),
      ),
      parentUsesSize: parentUsesSize,
    );

    _contentHeight = box!.height;
    box = PdfRect(
      box!.left,
      box!.bottom,
      box!.width,
      _contentHeight + reservedHeight,
    );
  }

  @override
  void paint(pw.Context context) {
    final outerBox = box!;
    final label = _label;
    if (label != null) {
      label.box = PdfRect(
        outerBox.left,
        outerBox.bottom + _contentHeight + _labelGap,
        label.box!.width,
        label.box!.height,
      );
      label.paint(context);
    }

    box = PdfRect(
      outerBox.left,
      outerBox.bottom,
      outerBox.width,
      _contentHeight,
    );
    super.paint(context);
    box = outerBox;
  }
}
