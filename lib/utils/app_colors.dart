import 'package:flutter/material.dart';

class AppColors {
  // Background
  static const Color background = Color(0xFF070B1F);

  // Main Gradients
  static const Color pink = Color(0xFFFF4D9D);
  static const Color purple = Color(0xFF8B5CF6);
  static const Color blue = Color(0xFF3B82F6);

  // Glass
  static const Color glass = Color.fromRGBO(255, 255, 255, 0.08);
  static const Color glassBorder = Color.fromRGBO(255, 255, 255, 0.18);

  // Text
  static const Color white = Colors.white;
  static const Color grey = Color(0xFFB6B8C5);

  // Loading
  static const Color progressBg = Color(0x22FFFFFF);

  // Shadows
  static const Color glowPink = Color(0x66FF4D9D);
  static const Color glowBlue = Color(0x663B82F6);

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [
      pink,
      purple,
      blue,
    ],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF070B1F),
      Color(0xFF131B3D),
      Color(0xFF090F23),
    ],
  );
}