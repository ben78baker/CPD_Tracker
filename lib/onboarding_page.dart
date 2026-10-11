import 'package:flutter/material.dart';
import 'settings_store.dart';
import 'l10n/app_localizations.dart';
import 'theme/app_accent.dart';
import 'widgets/app_colour_selector.dart';
import 'widgets/branded_headers.dart';
import 'widgets/form_section_tile.dart';
import 'widgets/tactile_button.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});
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
    if (!_formKey.currentState!.validate()) return;

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
      valueListenable: SettingsStore.instance.locale,
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
                        FormSectionTile(
                          label: loc.language,
                          icon: Icons.language_rounded,
                          child: ValueListenableBuilder<Locale?>(
                            valueListenable: SettingsStore.instance.locale,
                            builder: (context, forcedLocale, _) {
                              final current = forcedLocale?.languageCode ?? '';
                              return DropdownButtonFormField<String>(
                                key: const ValueKey('onboarding-language'),
                                initialValue: current,
                                isExpanded: true,
                                onChanged: (value) async {
                                  await SettingsStore.instance.setLocaleCode(
                                    value ?? '',
                                  );
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
                          valueListenable: SettingsStore.instance.appAccent,
                          builder: (context, selected, _) => FormSectionTile(
                            key: const ValueKey('onboarding-app-colour'),
                            label: loc.chooseYourAppColour,
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
                              }
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        TactileButton(
                          onPressed: _save,
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
