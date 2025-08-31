import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _name.text = prefs.getString('user_name') ?? '';
    _company.text = prefs.getString('company') ?? '';
    _address.text = prefs.getString('address') ?? '';
    _email.text = prefs.getString('email') ?? '';
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _name.dispose();
    _company.dispose();
    _address.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', _name.text.trim());
    await prefs.setString('company', _company.text.trim());
    await prefs.setString('address', _address.text.trim());
    await prefs.setString('email', _email.text.trim());
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Details')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Update your details',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name (optional)'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _company,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Company (optional)'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _address,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Address (optional)'),
                maxLines: 2,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email (optional)'),
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) return null;
                  return RegExp(r'^.+@.+\..+$').hasMatch(t)
                      ? null
                      : 'Enter a valid email';
                },
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
                  child: const Text('Save'),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}