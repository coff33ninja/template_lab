import "package:flutter/material.dart";

import "screens/home_screen.dart";

void main() {
  runApp(const ExperimentApp());
}

class ExperimentApp extends StatelessWidget {
  const ExperimentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "{{project_name}}",
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}
