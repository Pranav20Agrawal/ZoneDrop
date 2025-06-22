// lib/main.dart
import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';
import 'package:final_zd/theme/app_colors.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:provider/provider.dart';
import 'theme/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FMTCObjectBoxBackend().initialise();
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      title: 'ZoneDrop',
      themeMode: themeProvider.themeMode,

      // LIGHT THEME
      theme: ThemeData(
        primaryColor: AppColors.darkPrimary,
        primaryColorLight: AppColors.darkSecondary,
        primaryColorDark: AppColors.shark,
        colorScheme:
            ColorScheme.fromSwatch(
              primarySwatch: AppColors.curiousBlueSwatch,
              accentColor: AppColors.tropicalBlue,
              backgroundColor: AppColors.aquaHaze,
              cardColor: Colors.white,
              errorColor: Colors.red,
              brightness: Brightness.light,
            ).copyWith(
              onPrimary: Colors.white,
              onSecondary: AppColors.shark,
              onSurface: AppColors.shark,
              onBackground: AppColors.shark,
              onError: Colors.white,
              surface: Colors.white,
              outline: AppColors.silverSand,
              surfaceVariant: AppColors.aquaHaze,
            ),
        scaffoldBackgroundColor: AppColors.aquaHaze,
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.curiousBlue,
          foregroundColor: Colors.white,
          elevation: 4,
          centerTitle: true,
          titleTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        drawerTheme: const DrawerThemeData(backgroundColor: Colors.white),
        textTheme: TextTheme(
          displayLarge: TextStyle(color: AppColors.shark, fontSize: 57),
          displayMedium: TextStyle(color: AppColors.shark, fontSize: 45),
          displaySmall: TextStyle(color: AppColors.shark, fontSize: 36),
          headlineLarge: TextStyle(color: AppColors.shark, fontSize: 32),
          headlineMedium: TextStyle(
            color: AppColors.shark,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
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
        ).apply(bodyColor: AppColors.shark, displayColor: AppColors.shark),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.curiousBlue,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            textStyle: const TextStyle(fontSize: 18),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: AppColors.curiousBlue),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.curiousBlue,
            side: BorderSide(color: AppColors.curiousBlue, width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            textStyle: const TextStyle(fontSize: 18),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.aquaHaze,
          hoverColor: AppColors.tropicalBlue.withOpacity(0.2),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(color: AppColors.silverSand, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(color: AppColors.curiousBlue, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 16,
            horizontal: 16,
          ),
          hintStyle: TextStyle(color: AppColors.doveGray.withOpacity(0.6)),
          labelStyle: TextStyle(color: AppColors.doveGray),
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          selectedItemColor: AppColors.curiousBlue,
          unselectedItemColor: AppColors.silverChalice,
          elevation: 8,
          type: BottomNavigationBarType.fixed,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      // DARK THEME - Complete Implementation
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: AppColors.darkPrimary,
        primaryColorLight: AppColors.jordyBlue,
        primaryColorDark: AppColors.darkAccent,
        colorScheme:
            ColorScheme.fromSwatch(
              primarySwatch: AppColors.curiousBlueSwatch,
              accentColor: AppColors.tropicalBlue,
              backgroundColor: AppColors.darkBackground,
              cardColor: AppColors.darkCardColor,
              errorColor: Colors.redAccent,
              brightness: Brightness.dark,
            ).copyWith(
              onPrimary: Colors.white,
              onSecondary: Colors.white70,
              onSurface: Colors.white,
              onBackground: Colors.white,
              onError: Colors.white,
              surface: AppColors.darkSurface,
              outline: AppColors.darkOutline,
              surfaceVariant: AppColors.darkSurfaceVariant,
            ),
        scaffoldBackgroundColor: AppColors.darkBackground,
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.darkPrimary,
          foregroundColor: Colors.white,
          elevation: 4,
          centerTitle: true,
          titleTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        drawerTheme: const DrawerThemeData(
          backgroundColor: AppColors.darkSurface,
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(color: Colors.white, fontSize: 57),
          displayMedium: TextStyle(color: Colors.white, fontSize: 45),
          displaySmall: TextStyle(color: Colors.white, fontSize: 36),
          headlineLarge: TextStyle(color: Colors.white, fontSize: 32),
          headlineMedium: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
          headlineSmall: TextStyle(color: Colors.white, fontSize: 24),
          titleLarge: TextStyle(color: Colors.white, fontSize: 22),
          titleMedium: TextStyle(color: Colors.white, fontSize: 16),
          titleSmall: TextStyle(color: Colors.white, fontSize: 14),
          bodyLarge: TextStyle(color: Colors.white70, fontSize: 16),
          bodyMedium: TextStyle(color: Colors.white70, fontSize: 14),
          bodySmall: TextStyle(color: Colors.white70, fontSize: 12),
          labelLarge: TextStyle(color: Colors.white, fontSize: 14),
          labelMedium: TextStyle(color: Colors.white70, fontSize: 12),
          labelSmall: TextStyle(color: Colors.white70, fontSize: 11),
        ).apply(bodyColor: Colors.white, displayColor: Colors.white),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.darkPrimary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            textStyle: const TextStyle(fontSize: 18),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: AppColors.darkSecondary),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.darkSecondary,
            side: BorderSide(color: AppColors.darkSecondary, width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            textStyle: const TextStyle(fontSize: 18),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.darkSurfaceVariant,
          hoverColor: AppColors.tropicalBlue.withOpacity(0.2),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(color: AppColors.darkOutline, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide(color: AppColors.darkSecondary, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 16,
            horizontal: 16,
          ),
          hintStyle: TextStyle(color: AppColors.darkOnSurfaceVariant),
          labelStyle: TextStyle(color: AppColors.darkOnSurface),
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: AppColors.darkSurface,
          selectedItemColor: AppColors.darkPrimary,
          unselectedItemColor: AppColors.darkOnSurfaceVariant,
          elevation: 8,
          type: BottomNavigationBarType.fixed,
        ),
        cardTheme: CardThemeData(
          color: AppColors.darkCardColor,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        // Additional dark theme properties
        iconTheme: IconThemeData(color: AppColors.darkOnSurface),
        primaryIconTheme: const IconThemeData(color: Colors.white),
        dividerColor: AppColors.darkOutline,
        switchTheme: SwitchThemeData(
          thumbColor: MaterialStateProperty.resolveWith<Color>((states) {
            if (states.contains(MaterialState.selected)) {
              return Colors.white;
            }
            return AppColors.darkOnSurfaceVariant;
          }),
          trackColor: MaterialStateProperty.resolveWith<Color>((states) {
            if (states.contains(MaterialState.selected)) {
              return AppColors.darkPrimary;
            }
            return AppColors.darkOutline;
          }),
        ),
      ),

      home: const SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
