import 'package:flutter/material.dart';

const green = Color(0xFF16B77D);
const amber = Color(0xFFE08A26);
const blue = Color(0xFF2487F3);
const red = Color(0xFFE84D5B);

/// The app's neutral colours for the current theme, shared by Home and the sheets it opens.
extension Tones on BuildContext {
  bool get dark => Theme.of(this).brightness == Brightness.dark;
  Color get surface => dark ? const Color(0xFF172235) : Colors.white;
  Color get subtle => dark ? const Color(0xFF9AABBE) : const Color(0xFF66778A);
  Color get line => dark ? const Color(0xFF29374B) : const Color(0xFFE2E9EC);
  Color get tile => dark ? const Color(0xFF1A283B) : const Color(0xFFF4F7F8);
}
