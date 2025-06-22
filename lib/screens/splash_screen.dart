import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'home_screen.dart';
import 'package:final_zd/theme/app_colors.dart'; // Import your new app_colors.dart

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final Duration _navigationBuffer = const Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();
  }

  void _navigateToHome(LottieComposition composition) async {
    final Duration totalSplashDuration =
        composition.duration + _navigationBuffer;
    await Future.delayed(totalSplashDuration);

    if (mounted) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 500),
          pageBuilder: (context, animation, secondaryAnimation) =>
              const HomeScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Set a solid background color that matches the screenshot
      backgroundColor:
          AppColors.aquaHaze, // Changed to a color from your new palette
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Lottie.asset(
              'assets/splash_animation.json', // Path to your Lottie animation file
              onLoaded: (composition) {
                _navigateToHome(composition);
              },
              width: 250, // Increased size for prominence
              height: 250,
              fit: BoxFit.contain,
              repeat: false, // Play only once
              animate: true,
              errorBuilder: (context, error, stackTrace) {
                return Text(
                  'Error loading animation',
                  style: Theme.of(
                    context,
                  ).textTheme.headlineMedium?.copyWith(color: Colors.red),
                );
              },
            ),
            const SizedBox(
              height: 10,
            ), // Reduced spacing to move "ZoneDrop" text slightly up
            Text(
              'ZoneDrop', // Your app's name
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: AppColors
                    .shark, // Changed text color to a new palette color
                letterSpacing: 2,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20), // Spacing before the loading animation
            // New Lottie loading animation
            Lottie.asset(
              'assets/splash_loading.json', // Path to your loading animation file
              width: 80, // Adjust size as needed for a subtle loading indicator
              height: 80,
              fit: BoxFit.contain,
              repeat: true, // This animation should repeat indefinitely
              animate: true,
              errorBuilder: (context, error, stackTrace) {
                return const SizedBox.shrink(); // Hide if loading animation fails
              },
            ),
          ],
        ),
      ),
    );
  }
}
