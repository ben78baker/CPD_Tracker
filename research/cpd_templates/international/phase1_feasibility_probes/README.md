# Disposable Phase 1 feasibility probes

These probes support the [decision and feasibility report](../phase1_decisions_and_feasibility.md). They are small research experiments, separate from the app and its test suite. The SQLite probe uses only Python's standard library and a disposable temporary directory. The equipment probe uses Dart core only. The legacy decoder probe reads two production Dart libraries and passes only inline synthetic input.

From the project root, use a Dart SDK compatible with the checkout.

```sh
python3 research/cpd_templates/international/phase1_feasibility_probes/sqlite_contract_probe.py
dart --disable-dart-dev research/cpd_templates/international/phase1_feasibility_probes/equipment_contract_probe.dart
dart --disable-dart-dev research/cpd_templates/international/phase1_feasibility_probes/legacy_decode_probe.dart
```

Observed 20 November 2026 on host SQLite 3.51.0 and Dart 3.11.4. Two SQLite tests, six equipment checks and five legacy checks passed. These checks do not run sqflite on native devices, execute a real migration, render production exports or read an installed app’s preferences or attachment directories.
