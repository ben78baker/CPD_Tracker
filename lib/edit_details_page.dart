import 'package:flutter/material.dart';
import 'settings_store.dart';
import 'l10n/app_localizations.dart';

class EditDetailsPage extends StatefulWidget {
  const EditDetailsPage({super.key});
  @override
  State<EditDetailsPage> createState() => _EditDetailsPageState();
}

class _EditDetailsPageState extends State<EditDetailsPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _company = TextEditingController();
  final _address = TextEditingController();
  final _email = TextEditingController();

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await SettingsStore.instance.loadProfile();
      _name.text = profile['name'] ?? '';
      _company.text = profile['company'] ?? '';
      _address.text = profile['address'] ?? '';
      _email.text = profile['email'] ?? '';
    } catch (e) {
      debugPrint('[EditDetails] Failed to load profile: $e');
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      await SettingsStore.instance.saveProfile(
        name: _name.text.trim(),
        company: _company.text.trim(),
        address: _address.text.trim(),
        email: _email.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.couldNotSaveDetails),
        ),
      );
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _company.dispose();
    _address.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(loc.editPersonalDetails)),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(loc.editPersonalDetails)),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
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
                  final ok = RegExp(r'^.+@.+\..+$').hasMatch(t);
                  return ok ? null : loc.enterValidEmail;
                },
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(onPressed: _save, child: Text(loc.save)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
