import 'package:flutter/material.dart';

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: Center(
        child: Text(
          'HELLO FROM FLUTTER',
          style: TextStyle(fontSize: 24),
        ),
      ),
    ),
  ));
}