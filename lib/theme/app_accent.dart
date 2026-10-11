import 'package:flutter/material.dart';

enum AppAccent {
  purple('purple', Color(0xFF9043CD)),
  blue('blue', Color(0xFF2563B8)),
  teal('teal', Color(0xFF007F79)),
  green('green', Color(0xFF3D7B45)),
  orange('orange', Color(0xFFA9550D)),
  red('red', Color(0xFFB63A3A)),
  pink('pink', Color(0xFFB43F77)),
  indigo('indigo', Color(0xFF4E5AB7));

  const AppAccent(this.storageValue, this.seedColor);

  final String storageValue;
  final Color seedColor;

  static AppAccent fromStorage(String? value) {
    return AppAccent.values.firstWhere(
      (accent) => accent.storageValue == value,
      orElse: () => AppAccent.purple,
    );
  }
}
