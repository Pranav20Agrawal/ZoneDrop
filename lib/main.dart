import 'package:flutter/material.dart';
import 'splash_screen.dart';
import 'package:final_zd/theme/app_colors.dart'; // Import your new app_colors.dart

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // You can remove the createMaterialColor function from here if it's already in app_colors.dart
  // Keeping it in app_colors.dart makes more sense for color management.
  /*
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
  */

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ZoneDrop',
      theme: ThemeData(
        // NEW Color Scheme Definition (using your provided palette)
        // Primary colors for interactive elements, app bar, etc.
        primaryColor:
            AppColors.curiousBlue, // A strong blue for primary actions
        primaryColorLight: AppColors.jordyBlue, // Lighter shade of primary
        primaryColorDark: AppColors
            .shark, // Darker shade for text/icons on primary, or very dark elements
        // Accent color for secondary interactive elements, progress bars, etc.
        colorScheme:
            ColorScheme.fromSwatch(
              primarySwatch:
                  AppColors.curiousBlueSwatch, // Use the MaterialColor swatch
              accentColor: AppColors.tropicalBlue, // A distinct secondary blue
              backgroundColor:
                  AppColors.aquaHaze, // Light background for general UI
              cardColor: Colors.white, // Card backgrounds
              errorColor: Colors.red, // Error messages
              brightness: Brightness.light,
            ).copyWith(
              // Define other scheme colors explicitly if needed
              onPrimary: Colors.white, // Text/icons on primary color
              onSecondary: AppColors.shark, // Text/icons on accent color
              onSurface: AppColors.shark, // Text/icons on surface (e.g., cards)
              onBackground: AppColors.shark, // Text/icons on background
              onError: Colors.white, // Text/icons on error color
              surface: Colors.white, // Surface color (e.g., cards)
            ),

        scaffoldBackgroundColor:
            AppColors.aquaHaze, // Background of most screens
        // AppBar Theme
        appBarTheme: AppBarTheme(
          backgroundColor:
              AppColors.curiousBlue, // Use primary blue for app bar
          foregroundColor: Colors.white, // White text/icons on app bar
          elevation: 4, // Subtle shadow for depth
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),

        // Text Theme
        textTheme:
            TextTheme(
              displayLarge: TextStyle(color: AppColors.shark, fontSize: 57),
              displayMedium: TextStyle(color: AppColors.shark, fontSize: 45),
              displaySmall: TextStyle(color: AppColors.shark, fontSize: 36),
              headlineLarge: TextStyle(color: AppColors.shark, fontSize: 32),
              headlineMedium: TextStyle(
                color: AppColors.shark,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ), // Adjusted for app name
              headlineSmall: TextStyle(color: AppColors.shark, fontSize: 24),
              titleLarge: TextStyle(color: AppColors.shark, fontSize: 22),
              titleMedium: TextStyle(color: AppColors.shark, fontSize: 16),
              titleSmall: TextStyle(color: AppColors.shark, fontSize: 14),
              bodyLarge: TextStyle(color: AppColors.doveGray, fontSize: 16),
              bodyMedium: TextStyle(color: AppColors.doveGray, fontSize: 14),
              bodySmall: TextStyle(color: AppColors.doveGray, fontSize: 12),
              labelLarge: TextStyle(color: AppColors.shark, fontSize: 14),
              labelMedium: TextStyle(color: AppColors.doveGray, fontSize: 12),
              labelSmall: TextStyle(color: AppColors.doveGray, fontSize: 11),
            ).apply(
              bodyColor: AppColors.shark, // Default text color
              displayColor:
                  AppColors.shark, // Default text color for display styles
            ),

        // Button Themes
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.curiousBlue, // Primary button color
            foregroundColor: Colors.white, // Text color on primary button
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            textStyle: const TextStyle(fontSize: 18),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.curiousBlue, // Text button color
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.curiousBlue, // Text color
            side: BorderSide(
              color: AppColors.curiousBlue,
              width: 1.5,
            ), // Border color
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            textStyle: const TextStyle(fontSize: 18),
          ),
        ),

        // Input Decoration Theme (for text fields)
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.aquaHaze, // Light background for input fields
          hoverColor: AppColors.tropicalBlue.withOpacity(0.2), // Subtle hover
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15), // Rounded input fields
            borderSide: BorderSide.none, // No border by default
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(
              color: AppColors.silverSand,
              width: 1,
            ), // Light border
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(
              color: AppColors.curiousBlue, // Primary color border when focused
              width: 2,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 16,
            horizontal: 16,
          ),
          hintStyle: TextStyle(
            color: AppColors.doveGray.withOpacity(0.6),
          ), // Lighter hint text
          labelStyle: TextStyle(color: AppColors.doveGray),
        ),

        // Bottom Navigation Bar Theme
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: Colors.white, // White background for the bar
          selectedItemColor:
              AppColors.curiousBlue, // Primary blue for selected item
          unselectedItemColor: AppColors.silverChalice, // Gray for unselected
          elevation: 8, // Subtle shadow
          type: BottomNavigationBarType.fixed, // Ensure consistent spacing
        ),

        // Card Theme
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      home: const SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
