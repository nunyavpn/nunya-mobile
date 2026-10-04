// Show an honest empty state until the native VPN service can report its actual state.
import 'package:flutter/material.dart';

void main() => runApp(const NunyaApp());

class NunyaApp extends StatelessWidget {
  const NunyaApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Nunya',
    theme: ThemeData(useMaterial3: true),
    darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
    home: const Scaffold(
      body: SafeArea(
        child: Center(child: Text('VPN setup is not available yet.')),
      ),
    ),
  );
}
