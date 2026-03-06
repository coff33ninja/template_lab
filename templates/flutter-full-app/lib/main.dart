import "package:flutter/material.dart";

void main() {
  runApp(const FullApp());
}

class FullApp extends StatelessWidget {
  const FullApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "{{project_name}}",
      home: const Scaffold(body: Center(child: Text("Start building"))),
    );
  }
}
