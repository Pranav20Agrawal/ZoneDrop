import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class LocationService {
  Future<void> checkLocationServices() async {
    final isEnabled = await Geolocator.isLocationServiceEnabled();
    if (!isEnabled) {
      debugPrint(
        "⚠️ Location services are disabled. Wi-Fi info may not be available.",
      );
    }
  }

  Future<void> requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.phone,
    ].request();

    if (statuses[Permission.location]!.isDenied ||
        statuses[Permission.phone]!.isDenied) {
      debugPrint("❌ Required permissions denied.");
    }
  }

  Future<Position?> determinePosition({
    required BuildContext context,
    required VoidCallback onDenied,
    required VoidCallback onDeniedForever,
  }) async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      showLocationServiceAlertDialog(context);
      return null;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        showLocationPermissionAlertDialog(
          context,
          'Location permissions are denied',
        );
        onDenied();
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      showLocationPermissionAlertDialog(
        context,
        'Location permissions are permanently denied. Please enable them in app settings.',
      );
      onDeniedForever();
      return null;
    }

    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (e) {
      debugPrint('❌ Error getting location: $e');
      return null;
    }
  }

  void showLocationServiceAlertDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.location_off, color: Colors.orange),
              SizedBox(width: 8),
              Text("Location Services Disabled"),
            ],
          ),
          content: const Text(
            'Please enable location services to use this app.',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text("OK"),
              onPressed: () {
                Navigator.of(context).pop();
                Geolocator.openLocationSettings();
              },
            ),
          ],
        );
      },
    );
  }

  void showLocationPermissionAlertDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.location_disabled, color: Colors.red),
              SizedBox(width: 8),
              Text("Location Permission Denied"),
            ],
          ),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              child: const Text("OK"),
              onPressed: () {
                Navigator.of(context).pop();
                Geolocator.openAppSettings();
              },
            ),
          ],
        );
      },
    );
  }

  Future<bool> ensureLocationPermission() async {
    final status = await Permission.location.status;
    return status.isGranted || status.isLimited;
  }
}
