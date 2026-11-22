import 'package:flutter/material.dart';
import 'settings_store.dart';
import 'l10n/app_localizations.dart';
import 'theme/app_accent.dart';
import 'widgets/app_colour_selector.dart';
import 'widgets/branded_headers.dart';
import 'widgets/form_section_tile.dart';
import 'widgets/tactile_button.dart';

class OnboardingPreferences {
  const OnboardingPreferences({
    required this.locale,
    required this.accent,
    required this.initial,
    required this.save,
    required this.onContinue,
    this.showBackupHelp = false,
  });

  final ValueNotifier<Locale?> locale;
  final ValueNotifier<AppAccent> accent;
  final Map<String, String> initial;
  final Future<void> Function(String key, String value) save;
  final VoidCallback onContinue;
  final bool showBackupHelp;
}

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, this.preferences});
  final OnboardingPreferences? preferences;
  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _company = TextEditingController();
  final _address = TextEditingController();
  final _email = TextEditingController();
  final _profession = TextEditingController();

  // Onboarding choice for week start (default to device locale)
  String _weekStart = 'locale'; // 'monday' | 'sunday' | 'saturday' | 'locale'

  bool _saving = false;

  ValueNotifier<Locale?> get _locale =>
      widget.preferences?.locale ?? SettingsStore.instance.locale;
  ValueNotifier<AppAccent> get _accent =>
      widget.preferences?.accent ?? SettingsStore.instance.appAccent;

  @override
  void initState() {
    super.initState();
    final saved = widget.preferences?.initial;
    if (saved == null) return;
    _name.text = saved['name'] ?? '';
    _company.text = saved['company'] ?? '';
    _address.text = saved['address'] ?? '';
    _email.text = saved['email'] ?? '';
    _weekStart = saved['week'] ?? 'locale';
  }

  Future<void> _savePreference(String key, String value) async {
    final preferences = widget.preferences;
    if (preferences == null) return;
    try {
      await preferences.save(key, value);
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.editorSaveError),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _company.dispose();
    _address.dispose();
    _email.dispose();
    _profession.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    if (widget.preferences case final preferences?) {
      setState(() => _saving = true);
      try {
        final values = {
          'name': _name.text.trim(),
          'company': _company.text.trim(),
          'address': _address.text.trim(),
          'email': _email.text.trim(),
          'week': _weekStart,
          'locale': _locale.value?.languageCode ?? '',
          'accent': _accent.value.storageValue,
          'welcome': 'true',
        };
        for (final entry in values.entries) {
          await preferences.save(entry.key, entry.value);
        }
        if (mounted) preferences.onContinue();
      } on Exception {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.editorSaveError),
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _saving = false);
      }
      return;
    }

    try {
      // Save profile fields via SettingsStore
      await SettingsStore.instance.saveProfile(
        name: _name.text.trim(),
        company: _company.text.trim(),
        address: _address.text.trim(),
        email: _email.text.trim(),
      );

      // Persist first profession using centralized normalization + dedupe
      await SettingsStore.instance.addProfession(_profession.text);

      // Save preferred week start
      await SettingsStore.instance.setWeekStart(_weekStart);

      // Mark onboarding complete
      await SettingsStore.instance.setOnboardingComplete(true);
    } catch (e) {
      // Show a non-blocking notice; still continue to Home afterwards
      if (mounted) {
        final loc = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(loc.savedLocallyNotice)));
      }
    }

    // Navigate after work completes; avoid returning from a finally block
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/home');
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale?>(
      valueListenable: _locale,
      builder: (context, forcedLocale, _) {
        final loc = AppLocalizations.of(context)!;
        return Scaffold(
          appBar: AppBar(),
          body: SafeArea(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: EdgeInsets.zero,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                children: [
                  BrandedPageHeader.brand(
                    title: loc.welcome,
                    subtitle: loc.appTitle,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.preferences?.showBackupHelp ?? false) ...[
                          Text(loc.pbHelp),
                          const SizedBox(height: 12),
                        ],
                        FormSectionTile(
                          label: loc.language,
                          icon: Icons.language_rounded,
                          child: ValueListenableBuilder<Locale?>(
                            valueListenable: _locale,
                            builder: (context, forcedLocale, _) {
                              final current = forcedLocale?.languageCode ?? '';
                              return DropdownButtonFormField<String>(
                                key: const ValueKey('onboarding-language'),
                                initialValue: current,
                                isExpanded: true,
                                onChanged: (value) async {
                                  if (widget.preferences == null) {
                                    await SettingsStore.instance.setLocaleCode(
                                      value ?? '',
                                    );
                                  } else {
                                    _locale.value =
                                        value == null || value.isEmpty
                                        ? null
                                        : Locale(value);
                                    await _savePreference(
                                      'locale',
                                      value ?? '',
                                    );
                                  }
                                },
                                items: [
                                  DropdownMenuItem(
                                    value: '',
                                    child: Text(
                                      loc.followSystemLanguage,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'en',
                                    child: Text(loc.english),
                                  ),
                                  DropdownMenuItem(
                                    value: 'fr',
                                    child: Text(loc.french),
                                  ),
                                  DropdownMenuItem(
                                    value: 'de',
                                    child: Text(loc.german),
                                  ),
                                  DropdownMenuItem(
                                    value: 'es',
                                    child: Text(loc.spanish),
                                  ),
                                  DropdownMenuItem(
                                    value: 'pt',
                                    child: Text(loc.portuguese),
                                  ),
                                  DropdownMenuItem(
                                    value: 'hi',
                                    child: Text(loc.hindi),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        ValueListenableBuilder<AppAccent>(
                          valueListenable: _accent,
                          builder: (context, selected, _) => FormSectionTile(
                            key: const ValueKey('onboarding-app-colour'),
                            label: loc.chooseYourAppColour,
                            icon: Icons.palette_outlined,
                            supportingText: appAccentLabel(loc, selected),
                            child: AppColourSelector(
                              selectedAccent: selected,
                              onChanged: (accent) {
                                if (widget.preferences == null) {
                                  SettingsStore.instance.setAppAccent(accent);
                                } else {
                                  _accent.value = accent;
                                  _savePreference(
                                    'accent',
                                    accent.storageValue,
                                  );
                                }
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        FormSectionTile(
                          label: loc.setupYourDetails,
                          icon: Icons.person_outline_rounded,
                          child: Column(
                            children: [
                              TextFormField(
                                controller: _name,
                                textCapitalization: TextCapitalization.words,
                                decoration: InputDecoration(
                                  labelText: loc.nameOptional,
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextFormField(
                                controller: _company,
                                textCapitalization: TextCapitalization.words,
                                decoration: InputDecoration(
                                  labelText: loc.companyOptional,
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextFormField(
                                controller: _address,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                decoration: InputDecoration(
                                  labelText: loc.addressOptional,
                                ),
                                minLines: 1,
                                maxLines: 3,
                              ),
                              const SizedBox(height: 10),
                              TextFormField(
                                controller: _email,
                                keyboardType: TextInputType.emailAddress,
                                decoration: InputDecoration(
                                  labelText: loc.emailOptional,
                                ),
                                validator: (value) {
                                  final text = value?.trim() ?? '';
                                  if (text.isEmpty) return null;
                                  return RegExp(r'^.+@.+\..+$').hasMatch(text)
                                      ? null
                                      : loc.enterValidEmail;
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (widget.preferences == null)
                          FormSectionTile(
                            label: loc.firstProfessionRequired,
                            icon: Icons.work_outline_rounded,
                            child: TextFormField(
                              controller: _profession,
                              textCapitalization: TextCapitalization.words,
                              decoration: InputDecoration(
                                hintText: loc.professionExample,
                              ),
                              validator: (value) =>
                                  (value == null || value.trim().isEmpty)
                                  ? loc.enterProfession
                                  : null,
                            ),
                          ),
                        const SizedBox(height: 12),
                        FormSectionTile(
                          label: loc.weekStartsOn,
                          icon: Icons.calendar_view_week_outlined,
                          child: DropdownButtonFormField<String>(
                            key: const ValueKey('onboarding-week-start'),
                            initialValue: _weekStart,
                            isExpanded: true,
                            items: [
                              DropdownMenuItem(
                                value: 'locale',
                                child: Text(
                                  loc.useDeviceLocaleRecommended,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'monday',
                                child: Text(loc.monday),
                              ),
                              DropdownMenuItem(
                                value: 'sunday',
                                child: Text(loc.sunday),
                              ),
                              DropdownMenuItem(
                                value: 'saturday',
                                child: Text(loc.saturday),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _weekStart = value);
                                _savePreference('week', value);
                              }
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        TactileButton(
                          onPressed: _saving ? null : _save,
                          variant: TactileButtonVariant.primary,
                          minimumSize: const Size.fromHeight(52),
                          child: Text(loc.continueLabel),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
