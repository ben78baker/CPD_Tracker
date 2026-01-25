import 'package:flutter/material.dart';
import 'settings_store.dart';
import 'l10n/app_localizations.dart';

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
          appBar: AppBar(title: Text(loc.welcome)),
          body: SafeArea(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              loc.language,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          ValueListenableBuilder<Locale?>(
                            valueListenable: SettingsStore.instance.locale,
                            builder: (context, forcedLocale, _) {
                              final current = forcedLocale?.languageCode ?? '';
                              return DropdownButton<String>(
                                value: current,
                                onChanged: (v) async {
                                  await SettingsStore.instance.setLocaleCode(
                                    v ?? '',
                                  );
                                },
                                items: [
                                  DropdownMenuItem(
                                    value: '',
                                    child: Text(loc.followSystemLanguage),
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
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    loc.setupYourDetails,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(labelText: loc.nameOptional),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _company,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(labelText: loc.companyOptional),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _address,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(labelText: loc.addressOptional),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(labelText: loc.emailOptional),
                    validator: (v) {
                      final t = v?.trim() ?? '';
                      if (t.isEmpty) return null;
                      return RegExp(r'^.+@.+\..+$').hasMatch(t)
                          ? null
                          : loc.enterValidEmail;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _profession,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: loc.firstProfessionRequired,
                      hintText: loc.professionExample,
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? loc.enterProfession
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    loc.weekStartsOn,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    initialValue: _weekStart,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
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
                        child: Text(
                          loc.monday,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'sunday',
                        child: Text(
                          loc.sunday,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'saturday',
                        child: Text(
                          loc.saturday,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _weekStart = v);
                    },
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _save,
                      child: Text(loc.continueLabel),
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
