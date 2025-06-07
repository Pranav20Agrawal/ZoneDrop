// lib/theme/app_colors.dart
import 'package:flutter/material.dart';

// Utility function to create a MaterialColor from a single Color
MaterialColor createMaterialColor(Color color) {
  List<double> strengths = <double>[0.05];
  Map<int, Color> swatches = {};
  final int r = color.red, g = color.green, b = color.blue;

  for (int i = 0; i < 10; i++) {
    strengths.add(0.1 * i);
  }

  for (var strength in strengths) {
    final double ds = 0.5 - strength;
    swatches[(strength * 1000).round()] = Color.fromRGBO(
      r + ((ds < 0 ? r : (255 - r) * ds)).round(),
      g + ((ds < 0 ? g : (255 - g) * ds)).round(),
      b + ((ds < 0 ? b : (255 - b) * ds)).round(),
      1,
    );
  }
  return MaterialColor(color.value, swatches);
}

// Your new color palette
class AppColors {
  static const Color curiousBlue = Color(0xFF288DE3);
  static const Color jordyBlue = Color(0xFF7CBCF0);
  static const Color aquaHaze = Color(0xFFEDF2F5);
  static const Color tropicalBlue = Color(0xFFB8DAF7);
  static const Color doveGray = Color(0xFF646464);
  static const Color shark = Color(0xFF191D1F);
  static const Color silverChalice = Color(0xFFA4A4A4);
  static const Color friarGray = Color(0xFF747473);
  static const Color silverSand = Color(0xFFC7C8CA);
  static const Color pumice = Color(0xFFB3B4B3);

  // You can also create MaterialColor swatches for your primary colors if needed
  static final MaterialColor curiousBlueSwatch = createMaterialColor(
    curiousBlue,
  );
  static final MaterialColor jordyBlueSwatch = createMaterialColor(jordyBlue);
  static final MaterialColor sharkSwatch = createMaterialColor(shark);
  static final MaterialColor doveGraySwatch = createMaterialColor(doveGray);
}
