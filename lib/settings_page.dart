import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';
import 'settings_store.dart';
import 'theme/app_accent.dart';
import 'theme/app_theme.dart';
import 'widgets/app_colour_selector.dart';
import 'widgets/branded_headers.dart';
import 'widgets/form_section_tile.dart';
import 'widgets/tactile_button.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _weekStart = 'locale';

  @override
  void initState() {
    super.initState();
    _loadWeekStart();
  }

  Future<void> _loadWeekStart() async {
    final value = await SettingsStore.instance.getWeekStart();
    if (mounted) setState(() => _weekStart = value);
  }

  String _languageName(AppLocalizations loc, String? code) {
    return switch (code) {
      'en' => loc.english,
      'fr' => loc.french,
      'de' => loc.german,
      'es' => loc.spanish,
      'pt' => loc.portuguese,
      'hi' => loc.hindi,
      _ => loc.followSystemLanguage,
    };
  }

  String _weekStartName(AppLocalizations loc) {
    return switch (_weekStart) {
      'monday' => loc.monday,
      'saturday' => loc.saturday,
      'sunday' => loc.sunday,
      _ => loc.useDeviceLocaleRecommended,
    };
  }

  Future<void> _pickLanguage() async {
    final loc = AppLocalizations.of(context)!;
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(loc.language),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ''),
            child: Text(loc.followSystemLanguage),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'en'),
            child: Text(loc.english),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'fr'),
            child: Text(loc.french),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'de'),
            child: Text(loc.german),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'es'),
            child: Text(loc.spanish),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'pt'),
            child: Text(loc.portuguese),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'hi'),
            child: Text(loc.hindi),
          ),
        ],
      ),
    );
    if (selected == null) return;
    await SettingsStore.instance.setLocaleCode(selected);
  }

  Future<void> _pickWeekStart() async {
    var choice = _weekStart;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final loc = AppLocalizations.of(ctx)!;
          return AlertDialog(
            title: Text(loc.weekStartsOn),
            content: DropdownButtonFormField<String>(
              initialValue: choice,
              isExpanded: true,
              decoration: InputDecoration(labelText: loc.weekStartsOn),
              items: [
                DropdownMenuItem(
                  value: 'locale',
                  child: Text(
                    loc.useDeviceLocaleRecommended,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DropdownMenuItem(value: 'monday', child: Text(loc.monday)),
                DropdownMenuItem(value: 'saturday', child: Text(loc.saturday)),
                DropdownMenuItem(value: 'sunday', child: Text(loc.sunday)),
              ],
              onChanged: (value) {
                if (value != null) {
                  setDialogState(() => choice = value);
                }
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(loc.cancel),
              ),
              TactileButton(
                onPressed: () => Navigator.pop(ctx, true),
                variant: TactileButtonVariant.primary,
                child: Text(loc.save),
              ),
            ],
          );
        },
      ),
    );

    if (saved != true) return;
    if (choice == 'locale') {
      await SettingsStore.instance.clearWeekStart();
    } else {
      await SettingsStore.instance.setWeekStart(choice);
    }
    if (!mounted) return;
    setState(() => _weekStart = choice);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.weekStartUpdated)),
    );
  }

  Future<void> _resetTips() async {
    await SettingsStore.instance.resetQrHint();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.tipsRestored)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            BrandedPageHeader(
              title: loc.settings,
              subtitle: loc.settingsSubtitle,
              icon: Icons.settings_outlined,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ValueListenableBuilder<Locale?>(
                    valueListenable: SettingsStore.instance.locale,
                    builder: (context, locale, _) => _SettingsRow(
                      key: const ValueKey('settings-language'),
                      icon: Icons.language_rounded,
                      title: loc.language,
                      value: _languageName(loc, locale?.languageCode),
                      onTap: _pickLanguage,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<AppAccent>(
                    valueListenable: SettingsStore.instance.appAccent,
                    builder: (context, selected, _) => FormSectionTile(
                      key: const ValueKey('settings-app-colour'),
                      label: loc.appColour,
                      icon: Icons.palette_outlined,
                      supportingText: appAccentLabel(loc, selected),
                      child: AppColourSelector(
                        selectedAccent: selected,
                        onChanged: (accent) {
                          SettingsStore.instance.setAppAccent(accent);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SettingsRow(
                    key: const ValueKey('settings-week-start'),
                    icon: Icons.calendar_view_week_outlined,
                    title: loc.weekStartsOn,
                    value: _weekStartName(loc),
                    onTap: _pickWeekStart,
                  ),
                  const SizedBox(height: 12),
                  Card(
                    key: const ValueKey('settings-reset-tips'),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            loc.resetTips,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            loc.resetTipsDescription,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 12),
                          TactileButton.icon(
                            key: const ValueKey('reset-tips-action'),
                            onPressed: _resetTips,
                            icon: const Icon(Icons.refresh_rounded),
                            label: Text(loc.resetTips),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brandColors;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        minTileHeight: 72,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: brand.accentLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: brand.outlineVariant),
          ),
          child: Icon(icon, color: brand.accentDark),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(value),
        trailing: Icon(Icons.chevron_right_rounded, color: brand.accentDark),
        onTap: onTap,
      ),
    );
  }
}
