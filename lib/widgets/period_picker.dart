// lib/widgets/period_picker.dart
import 'package:flutter/material.dart';
import 'package:cpd_tracker/utils/date_utils.dart';
import 'date_button.dart';
import 'package:intl/intl.dart';

String formatDate(DateTime date, String format) {
  return DateFormat(format).format(date);
}

/// A simple bottom sheet with From/To date pickers and an OK/Cancel bar.
/// Returns a DateTimeRange if confirmed, or null if cancelled.
Future<DateTimeRange?> showPeriodPicker({
  required BuildContext context,
  required DateTime initialFrom,
  required DateTime initialTo,
  String dateFormat = 'dd/MM/yyyy',
}) {
  return showModalBottomSheet<DateTimeRange>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      DateTime from = initialFrom;
      DateTime to = initialTo;

      return StatefulBuilder(
        builder: (ctx, setState) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 8),
              Center(
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(
                      ctx,
                      DateTimeRange(
                        start: dateOnly(initialFrom),
                        end: dateOnly(initialTo),
                      ),
                    );
                  },
                  icon: const Icon(Icons.select_all),
                  label: const Text('Share All'),
                ),
              ),
              const SizedBox(height: 12),
              const Center(
                child: Text(
                  'Select Period',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Column(
                    children: [
                      DateButton(
                        date: from,
                        label: "From",
                        onChanged: (d) => setState(() => from = d),
                      ),
                      const SizedBox(height: 4),
                      Text(formatDate(from, dateFormat)),
                    ],
                  ),
                  Column(
                    children: [
                      DateButton(
                        date: to,
                        label: "To",
                        onChanged: (d) => setState(() => to = d),
                      ),
                      const SizedBox(height: 4),
                      Text(formatDate(to, dateFormat)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    child: const Text("Cancel"),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    child: const Text("OK"),
                    onPressed: () {
                      if (from.isAfter(to)) {
                        // Swap to keep order
                        final tmp = from;
                        from = to;
                        to = tmp;
                      }
                      Navigator.pop(ctx, DateTimeRange(start: dateOnly(from), end: dateOnly(to)));
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}