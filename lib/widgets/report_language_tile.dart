import 'package:flutter/material.dart';

import '../cpd_compatibility/report_locale.dart';
import '../l10n/app_localizations.dart';

class ReportLanguageTile extends StatelessWidget {
  const ReportLanguageTile({
    super.key,
    required this.language,
    required this.onChanged,
  });
  final ReportLanguage language;
  final ValueChanged<ReportLanguage> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context)!;
    String label(ReportLanguage choice) => choice == ReportLanguage.app
        ? s.reportFollowAppLanguage
        : choice.nativeName;
    return ListTile(
      leading: const Icon(Icons.translate_rounded),
      title: Text(s.reportLanguage),
      subtitle: Text(label(language)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final selected = await showModalBottomSheet<ReportLanguage>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (context) => SafeArea(
            child: FractionallySizedBox(
              heightFactor: 0.75,
              child: ListView(
                children: [
                  for (final choice in ReportLanguage.values)
                    ListTile(
                      title: Text(label(choice)),
                      selected: choice == language,
                      trailing: choice == language
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () => Navigator.pop(context, choice),
                    ),
                ],
              ),
            ),
          ),
        );
        if (selected != null && context.mounted) onChanged(selected);
      },
    );
  }
}
