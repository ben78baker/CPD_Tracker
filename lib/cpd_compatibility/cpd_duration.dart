const cpdMaxEntryHours = 999;
const cpdMaxCreditedMinutes = cpdMaxEntryHours * 60 + 59;

/// Validate new or changed CPD credit. Historical reads and imports retain
/// their original minute count, and generic duration fields have no CPD limit.
void checkCpdCreditedDuration(Object? value) {
  if (value == null) return;
  if (value is! int || value < 0 || value > cpdMaxCreditedMinutes) {
    throw ArgumentError.value(
      value,
      'credited duration',
      'Expected whole minutes from 0 to $cpdMaxCreditedMinutes.',
    );
  }
}
