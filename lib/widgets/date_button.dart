// lib/widgets/date_button.dart
import 'package:flutter/material.dart';
import '../utils/date_utils.dart';

class DateButton extends StatelessWidget {
  const DateButton({
    super.key,
    required this.date,
    required this.onChanged,
    this.label,
  });

  final DateTime date;
  final ValueChanged<DateTime> onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2000),
          lastDate: DateTime.now(),
        );
        if (picked != null) {
          onChanged(dateOnly(picked));
        }
      },
      child: Text(label ?? formatDateDMY(date)),
    );
  }
}