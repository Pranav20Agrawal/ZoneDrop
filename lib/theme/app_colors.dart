// lib/theme/app_colors.dart
import 'package:flutter/material.dart';

// Utility function to create a MaterialColor from a single Color
MaterialColor createMaterialColor(Color color) {
  List<double> strengths = <double>[0.05];
  Map<int, Color> swatches = {};
  final int r = color.red, g = color.green, b = color.blue;

  for (int i = 1; i < 10; i++) {
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

// Your enhanced color palette
class AppColors {
  // Light theme colors
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

  // Dark theme specific colors - Updated with your custom palette
  static const Color darkBackground = Color(0xFF1B1A55); // Deep base
  static const Color darkSurface = Color(0xFF402E7A); // From your palette
  static const Color darkSurfaceVariant = Color(0xFF4C3BCF); // Vibrant mid-tone
  static const Color darkOnSurface = Color(
    0xFF3DC2EC,
  ); // Bright cyan for contrast text/icons
  static const Color darkOnSurfaceVariant = Color(
    0xFF4B70F5,
  ); // Lighter blue variant
  static const Color darkOutline = Color(
    0xFF3DC2EC,
  ); // Cyan as highlight outline
  static const Color darkCardColor = Color(
    0xFF2B275A,
  ); // Slightly lighter than background
  static const Color darkPrimary = Color(0xFF4B70F5); // Primary action color
  static const Color darkSecondary = Color(0xFF4C3BCF); // Secondary color
  static const Color darkAccent = Color(
    0xFF3DC2EC,
  ); // Accent for highlights/badges

  // Material color swatches
  static final MaterialColor curiousBlueSwatch = createMaterialColor(
    curiousBlue,
  );
  static final MaterialColor jordyBlueSwatch = createMaterialColor(jordyBlue);
  static final MaterialColor sharkSwatch = createMaterialColor(shark);
  static final MaterialColor doveGraySwatch = createMaterialColor(doveGray);
  static final MaterialColor darkPrimarySwatch = createMaterialColor(
    darkPrimary,
  );

  // Utility methods for theme-aware colors
  static Color getBackgroundColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkBackground
        : aquaHaze;
  }

  static Color getSurfaceColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkSurface
        : Colors.white;
  }

  static Color getCardColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkCardColor
        : Colors.white;
  }

  static Color getOnSurfaceColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkOnSurface
        : shark;
  }

  static Color getPrimaryColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkPrimary
        : curiousBlue;
  }

  static Color getSecondaryColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkSecondary
        : tropicalBlue;
  }
}
