import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map_heatmap/flutter_map_heatmap.dart';
import 'package:geolocator/geolocator.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'dart:convert'; // for jsonEncode/jsonDecode
import 'package:shared_preferences/shared_preferences.dart';

class LatLngTween extends Tween<LatLng> {
  LatLngTween({super.begin, super.end});

  @override
  LatLng lerp(double t) {
    if (begin == null || end == null) {
      return begin ?? end ?? LatLng(0, 0); // Handle nulls gracefully
    }
    return LatLng(
      begin!.latitude + (end!.latitude - begin!.latitude) * t,
      begin!.longitude + (end!.longitude - begin!.longitude) * t,
    );
  }
}

class SignalService {
  static const platform = MethodChannel('com.example.final_zd/signal');

  static Future<Map<String, dynamic>?> getSignalInfo() async {
    try {
      final result = await platform.invokeMethod('getSignalInfo');
      return Map<String, dynamic>.from(result);
    } on PlatformException catch (e) {
      print("Failed to get signal info: '${e.message}'.");
      return null;
    }
  }
}

/// Custom WeightedLatLng class to hold additional network information
/// along with geographical coordinates and intensity.
class NetworkWeightedLatLng extends WeightedLatLng {
  final LatLng latLng;
  final double intensity;
  final String networkType;
  final String carrier;

  NetworkWeightedLatLng({
    required this.latLng,
    required this.intensity,
    required this.networkType,
    required this.carrier,
  }) : super(latLng, intensity);
}

/// The main screen widget for displaying the network signal heatmap.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  String? _selectedNetworkType = 'All';
  String? _selectedCarrier = 'All';
  final List<String> _networkTypes = ['All', '5G', '4G', 'Wi-Fi'];
  final List<String> _carriers = ['All', 'Airtel', 'Jio', 'VI', 'BSNL', 'ACT'];
  List<NetworkWeightedLatLng> _allSubmittedReadings = [];
  final List<NetworkWeightedLatLng> _heatPoints = [];
  List<WeightedLatLng> _filteredHeatPoints = [];
  double _currentZoom = 15.0;
  LatLng? _currentLocation;
  StreamSubscription<Position>? _locationSubscription;
  late final AnimationController _markerAnimationController;
  late Animation<LatLng> _markerAnimation;
  bool _isLocating = true;
  bool _isSubmitting = false;

  bool _isContinuousModeOn = false;
  Timer? _continuousTimer;
  bool _showCurrentLocationMarker = true;
  bool _isOptionsExpanded = false;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Animation and UI state
  bool _isInitialized = false;
  double _networkHighlightLeft = 0.0;
  double _networkHighlightWidth = 0.0;
  double _carrierHighlightLeft = 0.0;
  double _carrierHighlightWidth = 0.0;
  final double _filterOptionHeight = 36.0;
  int _selectedIndex = 0;

  // Animation controllers
  late AnimationController _refreshController;
  late AnimationController _submitController;
  late AnimationController _fadeController;
  late final MapController _mapController;
  late final PageController _pageController;

  // Plugin Instances
  final NetworkInfo _networkInfo = NetworkInfo();
  final Connectivity _connectivity = Connectivity();
  static const MethodChannel _wifiChannel = MethodChannel(
    'com.example.final_zd.signal_analyzer/wifi_rssi',
  );

  double _navHighlightLeft = 0.0;
  double _navHighlightWidth = 0.0;

  // Add a GlobalKey to get the size of the bottom nav bar items
  final Map<String, GlobalKey> _navKeys = {
    'Map': GlobalKey(),
    'Stats': GlobalKey(),
  };

  // Key for forcing heatmap rebuild
  Key _heatmapKey = UniqueKey();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _saveDataToPrefs();
    }
  }

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _initializeAnimations(); // Initializes refresh, submit, fade controllers
    _initializeApp(); // Checks permissions, location services, determines initial position
    _pageController = PageController(initialPage: 0);
    WidgetsBinding.instance.addObserver(this);
    _markerAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    // Initialize _markerAnimation with a default value.
    // It will be re-initialized correctly in _startLocationTracking.
    _markerAnimation = LatLngTween(
      begin: LatLng(0, 0),
      end: LatLng(0, 0),
    ).animate(_markerAnimationController);

    // Start listening for location updates
    _startLocationTracking();
    _loadDataFromPrefs();

    // No need to call _determinePosition here again if _initializeApp calls it.
    // _determinePosition(); // This is already called by _initializeApp()
  }

  void _startLocationTracking() {
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 1,
    );

    _locationSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (Position position) {
            final newLatLng = LatLng(position.latitude, position.longitude);

            setState(() {
              if (_currentLocation != null) {
                // Recreate the Animation when location changes
                _markerAnimation =
                    LatLngTween(
                      begin: _currentLocation, // Old location
                      end: newLatLng, // New location
                    ).animate(
                      CurvedAnimation(
                        parent: _markerAnimationController,
                        curve: Curves.easeInOutCubic,
                      ),
                    );

                _markerAnimationController.forward(
                  from: 0.0,
                ); // Start animation
              } else {
                // First location, just set the initial position for the animation without animating
                _markerAnimation = LatLngTween(begin: newLatLng, end: newLatLng)
                    .animate(
                      CurvedAnimation(
                        parent: _markerAnimationController,
                        curve: Curves.easeInOutCubic,
                      ),
                    );
                // No need to forward the controller, as it's the initial state
              }
              _currentLocation = newLatLng; // Update current location
              _mapController.move(
                newLatLng,
                _currentZoom,
              ); // Move map to new location
            });
          },
          onError: (e) {
            print("Location stream error: $e");
            // Handle permissions or errors gracefully here
          },
        );
  }

  // Add this method to check if a point exists at current location
  int? _findExistingPointIndex(LatLng location) {
    const double threshold = 0.0001; // ~10 meters accuracy

    for (int i = 0; i < _heatPoints.length; i++) {
      final point = _heatPoints[i];
      final distance =
          (point.latLng.latitude - location.latitude).abs() +
          (point.latLng.longitude - location.longitude).abs();

      if (distance < threshold) {
        return i;
      }
    }
    return null;
  }

  void _initializeAnimations() {
    _refreshController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _submitController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
  }

  Future<void> _initializeApp() async {
    await _checkLocationServices();
    await _requestPermissions();
    await _determinePosition();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted) {
        _calculateInitialHighlightPositions();
        _calculateInitialNavHighlightPositions();
        setState(() {
          _isInitialized = true;
        });
        _applyHeatmapFilter();
        _fadeController.forward();
      }
    });
  }

  void _calculateInitialHighlightPositions() {
    // Calculate network type highlight with proper padding
    final networkIndex = _networkTypes.indexOf(_selectedNetworkType!);
    final containerWidth =
        MediaQuery.of(context).size.width - 32; // Account for outer padding
    final networkItemWidth =
        (containerWidth - 8) /
        _networkTypes.length; // Account for container padding
    _networkHighlightLeft = networkIndex * networkItemWidth + 2;
    _networkHighlightWidth = networkItemWidth - 4;

    // Calculate carrier highlight with proper padding
    final carrierIndex = _carriers.indexOf(_selectedCarrier!);
    final carrierItemWidth = (containerWidth - 8) / _carriers.length;
    _carrierHighlightLeft = carrierIndex * carrierItemWidth + 2;
    _carrierHighlightWidth = carrierItemWidth - 4;
  }

  void _calculateInitialNavHighlightPositions() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final RenderBox? mapRenderBox =
            _navKeys['Map']!.currentContext?.findRenderObject() as RenderBox?;
        final RenderBox? navBarStackRenderBox =
            _navBarStackKey.currentContext?.findRenderObject() as RenderBox?;

        if (mapRenderBox != null && navBarStackRenderBox != null) {
          final Offset itemGlobalPosition = mapRenderBox.localToGlobal(
            Offset.zero,
          );
          final Offset stackGlobalPosition = navBarStackRenderBox.localToGlobal(
            Offset.zero,
          );

          final double highlightLeft =
              itemGlobalPosition.dx - stackGlobalPosition.dx;
          final double highlightWidth = mapRenderBox.size.width;

          final double targetHighlightWidth = highlightWidth * 0.8;
          final double horizontalAdjustment =
              (highlightWidth - targetHighlightWidth) / 2;

          setState(() {
            _navHighlightLeft = highlightLeft + horizontalAdjustment;
            _navHighlightWidth = targetHighlightWidth;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _refreshController.dispose();
    _submitController.dispose();
    _fadeController.dispose();
    _locationSubscription?.cancel(); // Cancel the subscription
    _markerAnimationController.dispose(); // Dispose the controller
    _mapController.dispose(); // Add this line to dispose the map controller
    _pageController.dispose();
    _continuousTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _checkLocationServices() async {
    final isEnabled = await Geolocator.isLocationServiceEnabled();
    if (!isEnabled) {
      debugPrint(
        "⚠️ Location services are disabled. Wi-Fi info may not be available.",
      );
    }
  }

  Future<void> _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.phone,
    ].request();

    if (statuses[Permission.location]!.isDenied ||
        statuses[Permission.phone]!.isDenied) {
      debugPrint("❌ Required permissions denied.");
    }
  }

  Future<int?> getWifiSignalStrength() async {
    try {
      final int? rssi = await _wifiChannel.invokeMethod('getWifiRssi');
      debugPrint("📶 WiFi RSSI: $rssi dBm");
      return rssi;
    } on PlatformException catch (e) {
      debugPrint("❌ Failed to get WiFi signal: ${e.message}");
      return null;
    }
  }

  Future<void> _saveDataToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> jsonList = _allSubmittedReadings.map((p) {
      return jsonEncode({
        'lat': p.latLng.latitude,
        'lng': p.latLng.longitude,
        'intensity': p.intensity,
        'networkType': p.networkType,
        'carrier': p.carrier,
      });
    }).toList();

    await prefs.setStringList('readings', jsonList);
    print('✅ Data saved: ${jsonList.length} readings');
  }

  Future<void> _loadDataFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? jsonList = prefs.getStringList('readings');

    if (jsonList != null) {
      final restoredReadings = jsonList.map((str) {
        final data = jsonDecode(str);
        return NetworkWeightedLatLng(
          latLng: LatLng(data['lat'], data['lng']),
          intensity: data['intensity'],
          networkType: data['networkType'],
          carrier: data['carrier'],
        );
      }).toList();

      setState(() {
        _allSubmittedReadings = restoredReadings;
        _heatPoints.clear();
        _heatPoints.addAll(restoredReadings);
        _applyHeatmapFilter();
      });

      print('✅ Data restored: ${_allSubmittedReadings.length} readings');
    }
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showLocationServiceAlertDialog();
      setState(() {
        _isLocating = false;
      });
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showLocationPermissionAlertDialog('Location permissions are denied');
        setState(() {
          _isLocating = false;
        });
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _showLocationPermissionAlertDialog(
        'Location permissions are permanently denied. Please enable them in app settings.',
      );
      setState(() {
        _isLocating = false;
      });
      return;
    }

    setState(() {
      _isLocating = true;
    });
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
        _isLocating = false;
      });
      print(
        'Current Location: ${_currentLocation!.latitude}, ${_currentLocation!.longitude}',
      );
    } catch (e) {
      print('Error getting location: $e');
      setState(() {
        _isLocating = false;
      });
    }
  }

  Future<void> fetchSignalInfo() async {
    try {
      final Map<String, dynamic> result = await _wifiChannel.invokeMethod(
        'getSignalInfo',
      );

      final String networkType = result['networkType'];
      final String carrier = result['carrier'];
      final int signalStrength = result['signalStrengthDbm'];

      debugPrint("📶 Network Type: $networkType");
      debugPrint("📡 Carrier: $carrier");
      debugPrint("📊 Signal Strength: $signalStrength dBm");

      final point = NetworkWeightedLatLng(
        latLng: LatLng(_currentLocation!.latitude, _currentLocation!.longitude),
        intensity: signalStrength.toDouble(),
        networkType: networkType,
        carrier: carrier,
      );
      setState(() {
        _heatPoints.add(point);
        _applyHeatmapFilter();
      });
    } on PlatformException catch (e) {
      debugPrint("❌ Error getting signal info: ${e.message}");
    }
  }

  void _startContinuousCollection() {
    _continuousTimer = Timer.periodic(
      const Duration(seconds: 1), // Adjust interval as needed
      (timer) async {
        if (_currentLocation != null) {
          final signalInfo = await _getNetworkSignalInfo();
          final String networkType = signalInfo['networkType'];
          final double signalWeight = signalInfo['signalWeight'];
          final String carrierName = signalInfo['carrierName'];

          final newReadingPoint = NetworkWeightedLatLng(
            latLng: _currentLocation!,
            intensity: signalWeight,
            networkType: networkType,
            carrier: carrierName,
          );

          setState(() {
            _allSubmittedReadings.add(newReadingPoint);
            final existingIndex = _findExistingPointIndex(_currentLocation!);
            if (existingIndex != null) {
              _heatPoints[existingIndex] = newReadingPoint;
            } else {
              _heatPoints.add(newReadingPoint);
            }
            _heatmapKey = UniqueKey();
            _applyHeatmapFilter();
          });
        }
      },
    );
    _showCustomSnackBar(
      message: 'Continuous mode activated!',
      icon: Icons.autorenew,
      backgroundColor: Colors.blueAccent,
    );
  }

  void _stopContinuousCollection() {
    _continuousTimer?.cancel();
    _showCustomSnackBar(
      message: 'Continuous mode stopped.',
      icon: Icons.pause_circle,
      backgroundColor: Colors.deepOrangeAccent,
    );
  }

  void _applyHeatmapFilter() {
    setState(() {
      _filteredHeatPoints = _heatPoints.where((point) {
        bool matchesNetworkType =
            (_selectedNetworkType == null || _selectedNetworkType == 'All')
            ? true
            : point.networkType == _selectedNetworkType;
        bool matchesCarrier =
            (_selectedCarrier == null || _selectedCarrier == 'All')
            ? true
            : point.carrier == _selectedCarrier;
        return matchesNetworkType && matchesCarrier;
      }).toList();
      _heatmapKey = UniqueKey();
    });
  }

  void _showLocationServiceAlertDialog() {
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

  Future<void> _refreshData() async {
    setState(() {
      _isLocating = true;
    });

    await _determinePosition();

    // Show refresh feedback
    if (mounted) {
      _showCustomSnackBar(
        message: 'Location Updated',
        icon: Icons.location_on,
        backgroundColor: Colors.blue.shade600,
      );
    }

    setState(() {
      _isLocating = false;
      _heatmapKey = UniqueKey();
    });
  }

  void _showLocationPermissionAlertDialog(String message) {
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

  Future<int?> _getWifiRssiNative() async {
    if (Platform.isAndroid) {
      try {
        final int? rssi = await _wifiChannel.invokeMethod('getWifiRssi');
        return rssi;
      } on PlatformException catch (e) {
        print(
          "Failed to get Wi-Fi RSSI from native: '${e.message}'. Ensure location permissions are granted.",
        );
        return null;
      }
    }
    return null;
  }

  String _normalizeCarrierName(String rawName, String networkType) {
    final lowerCaseRawName = rawName.toLowerCase();

    if (networkType == 'Wi-Fi') {
      if (lowerCaseRawName.contains('airtel')) {
        return 'Airtel';
      } else if (lowerCaseRawName.contains('jiofiber') ||
          lowerCaseRawName.contains('jio')) {
        return 'JioFiber';
      } else if (lowerCaseRawName.contains('bsnl')) {
        return 'BSNL';
      }
      return rawName;
    } else if (networkType == '4G' ||
        networkType == '3G' ||
        networkType == '5G' ||
        networkType == '2G') {
      if (lowerCaseRawName.contains('airtel')) {
        return 'Airtel';
      } else if (lowerCaseRawName.contains('jio')) {
        return 'Jio';
      } else if (lowerCaseRawName.contains('vodafone') ||
          lowerCaseRawName.contains('vi')) {
        return 'Vi';
      } else if (lowerCaseRawName.contains('bsnl')) {
        return 'BSNL';
      }
      return rawName;
    }
    return rawName;
  }

  Future<Map<String, dynamic>> _getNetworkSignalInfo() async {
    String networkType = 'Unknown';
    double signalWeight = 0.0;
    String carrierName = 'Unknown';
    int signalStrengthDbm = -999;
    String signalStatusMessage = 'Initializing...';

    try {
      final List<ConnectivityResult> connectivityResults = await _connectivity
          .checkConnectivity();
      String connectionStatus = 'none';

      if (connectivityResults.contains(ConnectivityResult.mobile)) {
        connectionStatus = 'mobile';
      } else if (connectivityResults.contains(ConnectivityResult.wifi)) {
        connectionStatus = 'wifi';
      } else if (connectivityResults.contains(ConnectivityResult.ethernet)) {
        connectionStatus = 'ethernet';
      } else if (connectivityResults.contains(ConnectivityResult.none)) {
        connectionStatus = 'none';
      }

      if (connectionStatus == 'wifi') {
        final String? wifiName = await _networkInfo.getWifiName();
        final int? wifiRssi = Platform.isAndroid
            ? await _getWifiRssiNative()
            : null;

        networkType = 'Wi-Fi';

        if (wifiName != null && wifiRssi != null) {
          String rawWifiCarrierName = wifiName.replaceAll('"', '');
          carrierName = _normalizeCarrierName(rawWifiCarrierName, networkType);
          signalStrengthDbm = wifiRssi;

          const double minWifiDbm = -85.0;
          const double maxWifiDbm = -30.0;

          double normalizedWifi =
              (signalStrengthDbm - minWifiDbm) / (maxWifiDbm - minWifiDbm);
          signalWeight = normalizedWifi.clamp(0.1, 0.9);

          signalStatusMessage = '$signalStrengthDbm dBm';
          debugPrint(
            'Wi-Fi: "$carrierName", RSSI: $signalStrengthDbm dBm, Weight: $signalWeight',
          );
        } else if (wifiName != null) {
          String rawWifiCarrierName = wifiName.replaceAll('"', '');
          carrierName = _normalizeCarrierName(rawWifiCarrierName, networkType);
          signalStrengthDbm = -999;
          signalWeight = 0.3;
          signalStatusMessage = 'RSSI unavailable, using default weight.';
          debugPrint('Wi-Fi: "$carrierName", $signalStatusMessage');
        } else {
          carrierName = 'Unknown Wi-Fi';
          signalStrengthDbm = -999;
          signalWeight = 0.1;
          signalStatusMessage = 'Wi-Fi Name/RSSI unavailable.';
          debugPrint('Wi-Fi: "$carrierName", $signalStatusMessage');
        }
      } else if (connectionStatus == 'mobile') {
        final Map<dynamic, dynamic>? signalInfo =
            await SignalService.getSignalInfo();

        if (signalInfo != null) {
          String rawNetworkType =
              signalInfo['networkType'] as String? ?? 'cellular';
          String rawCarrierName =
              signalInfo['carrier'] as String? ?? 'Unknown Carrier';
          signalStrengthDbm = signalInfo['signalStrengthDbm'] as int? ?? -999;
          signalStatusMessage =
              signalInfo['signalStatus'] as String? ?? 'Status Unavailable';

          networkType = rawNetworkType;
          carrierName = _normalizeCarrierName(rawCarrierName, networkType);

          if (signalStrengthDbm != -1 && signalStrengthDbm != -9999) {
            const double minCellularDbm = -120.0;
            const double maxCellularDbm = -80.0;

            double normalizedCellular =
                (signalStrengthDbm - minCellularDbm) /
                (maxCellularDbm - minCellularDbm);
            signalWeight = normalizedCellular.clamp(0.1, 0.9);

            debugPrint(
              'Cellular Type: $networkType, Carrier: $carrierName, dBm: $signalStrengthDbm, Weight: $signalWeight, Status: $signalStatusMessage',
            );
          } else {
            debugPrint(
              'Cellular Type: $networkType, Carrier: $carrierName, Status: $signalStatusMessage',
            );
            if (networkType == '5G') {
              signalWeight = 0.8;
            } else if (networkType == '4G') {
              signalWeight = 0.6;
            } else if (networkType == '3G') {
              signalWeight = 0.4;
            } else if (networkType == '2G') {
              signalWeight = 0.2;
            } else {
              signalWeight = 0.1;
            }
          }
        } else {
          debugPrint('SignalService failed, using default cellular values');
          networkType = 'cellular';
          carrierName = 'Unknown Carrier';
          signalStrengthDbm = -999;
          signalWeight = 0.1;
          signalStatusMessage = 'Failed to get cellular info from native.';
        }
      } else {
        debugPrint(
          'Not connected to Wi-Fi or Cellular. Connection Status: $connectionStatus',
        );
        networkType = 'None';
        carrierName = 'No Connection';
        signalStrengthDbm = -999;
        signalWeight = 0.0;
        signalStatusMessage = 'No active network connection.';
      }
    } catch (e) {
      debugPrint('Failed to get network info: $e');
      networkType = 'Error';
      signalWeight = 0.0;
      carrierName = 'Error';
      signalStrengthDbm = -999;
      signalStatusMessage = 'Error during signal fetching: $e';
    }

    return {
      'networkType': networkType,
      'signalWeight': signalWeight,
      'carrierName': carrierName,
      'signalStrengthDbm': signalStrengthDbm,
      'signalStatusMessage': signalStatusMessage,
    };
  }

  Widget _buildNavItem({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required int index,
    required bool isSelected,
    required VoidCallback onTap,
    required GlobalKey itemKey,
  }) {
    return Expanded(
      child: GestureDetector(
        key: itemKey,
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                isSelected ? activeIcon : icon,
                color: isSelected ? Colors.white : Colors.grey.shade700,
                size: isSelected ? 26.0 : 24.0,
              ),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey.shade700,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  fontSize: isSelected ? 13.0 : 12.0,
                ),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onItemTapped(int index) {
    if (_selectedIndex == index) return;

    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOutCubic,
    );
  }

  void _updateNavHighlight(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final RenderBox? selectedItemRenderBox =
          _navKeys.values.elementAt(index).currentContext?.findRenderObject()
              as RenderBox?;
      final RenderBox? navBarStackRenderBox =
          _navBarStackKey.currentContext?.findRenderObject() as RenderBox?;

      if (selectedItemRenderBox != null &&
          navBarStackRenderBox != null &&
          mounted) {
        final Offset itemGlobalPosition = selectedItemRenderBox.localToGlobal(
          Offset.zero,
        );
        final Offset stackGlobalPosition = navBarStackRenderBox.localToGlobal(
          Offset.zero,
        );

        final double highlightLeft =
            itemGlobalPosition.dx - stackGlobalPosition.dx;
        final double highlightWidth = selectedItemRenderBox.size.width;

        final double targetHighlightWidth = highlightWidth * 0.8;
        final double horizontalAdjustment =
            (highlightWidth - targetHighlightWidth) / 2;

        setState(() {
          _navHighlightLeft = highlightLeft + horizontalAdjustment;
          _navHighlightWidth = targetHighlightWidth;
        });
      }
    });
  }

  final GlobalKey _navBarStackKey = GlobalKey();

  void _onNetworkTypeSelected(String type) {
    if (_selectedNetworkType == type) return;

    setState(() {
      _selectedNetworkType = type;
    });

    final index = _networkTypes.indexOf(type);
    final containerWidth = MediaQuery.of(context).size.width - 32;
    final itemWidth = (containerWidth - 8) / _networkTypes.length;

    setState(() {
      _networkHighlightLeft = index * itemWidth + 2;
      _networkHighlightWidth = itemWidth - 4;
    });

    _applyHeatmapFilter();
  }

  void _onCarrierSelected(String carrier) {
    if (_selectedCarrier == carrier) return;

    setState(() {
      _selectedCarrier = carrier;
    });

    final index = _carriers.indexOf(carrier);
    final containerWidth = MediaQuery.of(context).size.width - 32;
    final itemWidth = (containerWidth - 8) / _carriers.length;

    setState(() {
      _carrierHighlightLeft = index * itemWidth + 2;
      _carrierHighlightWidth = itemWidth - 4;
    });

    _applyHeatmapFilter();
  }

  Widget _buildFilterRow({
    required List<String> options,
    required String? selectedValue,
    required Function(String) onTap,
    required double highlightLeft,
    required double highlightWidth,
  }) {
    return Container(
      padding: const EdgeInsets.all(4.0),
      height: _filterOptionHeight + 8,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Highlight background with smooth animation
          if (_isInitialized)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOutQuart, // Smoother curve
              left: highlightLeft,
              width: highlightWidth,
              height: _filterOptionHeight,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).primaryColor,
                      Theme.of(context).primaryColor.withOpacity(0.8),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).primaryColor.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                    BoxShadow(
                      color: Colors.white.withOpacity(0.1),
                      blurRadius: 1,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.2),
                      width: 0.5,
                    ),
                  ),
                ),
              ),
            ),
          // Filter options
          Row(
            children: options.map((option) {
              final isSelected = selectedValue == option;

              return Expanded(
                child: GestureDetector(
                  onTap: () => onTap(option),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    height: _filterOptionHeight,
                    alignment: Alignment.center,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.black87,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        fontSize: isSelected ? 14.5 : 14,
                        letterSpacing: isSelected ? 0.3 : 0,
                        shadows: isSelected
                            ? [
                                Shadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 1,
                                  offset: const Offset(0, 0.5),
                                ),
                              ]
                            : [],
                      ),
                      child: Text(option, textAlign: TextAlign.center),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  void _showCustomSnackBar({
    required String message,
    required IconData icon,
    required Color backgroundColor,
    String? subtitle,
    Duration duration = const Duration(seconds: 2),
  }) {
    // Clear existing snackbars
    ScaffoldMessenger.of(context).clearSnackBars();

    // Calculate safe area and position
    final mediaQuery = MediaQuery.of(context);
    final topPadding =
        mediaQuery.padding.top + kToolbarHeight + 16; // AppBar height + padding

    // Create overlay entry
    late OverlayEntry overlayEntry;
    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: topPadding,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 300),
            tween: Tween(begin: 0.0, end: 1.0),
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(0, -50 * (1 - value)),
                child: Opacity(
                  opacity: value,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: backgroundColor,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(icon, color: Colors.white, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                message,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (subtitle != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  subtitle,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    // Show overlay
    Overlay.of(context).insert(overlayEntry);

    // Auto-remove after duration
    Timer(duration, () {
      overlayEntry.remove();
    });
  }

  Widget _buildStatsPage() {
    // Calculate overall statistics
    final totalReadings = _allSubmittedReadings.length;
    final overallAvgSignal = totalReadings > 0
        ? (_allSubmittedReadings
                  .map((p) => p.intensity)
                  .reduce((a, b) => a + b) /
              totalReadings *
              100)
        : 0.0;

    // Count unique locations (simplified - you can enhance this with your proximity logic)
    final uniqueLocations = _heatPoints
        .map(
          (p) =>
              '${p.latLng.latitude.toStringAsFixed(4)},${p.latLng.longitude.toStringAsFixed(4)}',
        )
        .toSet()
        .length;

    // Calculate signal quality breakdown - now based on ALL readings
    Map<String, int> qualityBreakdown = {
      'Excellent': 0,
      'Good': 0,
      'Fair': 0,
      'Poor': 0,
      'Very Poor/No Signal': 0,
    };

    for (var point in _allSubmittedReadings) {
      // <--- CHANGED to _allSubmittedReadings
      final percentage = point.intensity * 100;
      if (percentage >= 80) {
        qualityBreakdown['Excellent'] = qualityBreakdown['Excellent']! + 1;
      } else if (percentage >= 60) {
        qualityBreakdown['Good'] = qualityBreakdown['Good']! + 1;
      } else if (percentage >= 40) {
        qualityBreakdown['Fair'] = qualityBreakdown['Fair']! + 1;
      } else if (percentage >= 20) {
        qualityBreakdown['Poor'] = qualityBreakdown['Poor']! + 1;
      } else {
        qualityBreakdown['Very Poor/No Signal'] =
            qualityBreakdown['Very Poor/No Signal']! + 1;
      }
    }

    // Calculate network type performance - now based on ALL readings
    Map<String, List<double>> networkStats = {};
    for (var point in _allSubmittedReadings) {
      // <--- CHANGED to _allSubmittedReadings
      if (!networkStats.containsKey(point.networkType)) {
        networkStats[point.networkType] = [];
      }
      networkStats[point.networkType]!.add(point.intensity);
    }

    // Calculate carrier performance - now based on ALL readings
    Map<String, List<double>> carrierStats = {};
    for (var point in _allSubmittedReadings) {
      // <--- CHANGED to _allSubmittedReadings
      if (!carrierStats.containsKey(point.carrier)) {
        carrierStats[point.carrier] = [];
      }
      carrierStats[point.carrier]!.add(point.intensity);
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: ListView(
        children: [
          // Overall Performance Summary
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Overall Performance Summary',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildStatRow('Total Readings', '$totalReadings'),
                  _buildStatRow(
                    'Overall Avg. Signal',
                    '${overallAvgSignal.toStringAsFixed(1)}%',
                  ),
                  _buildStatRow('Unique Locations', '$uniqueLocations'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Signal Quality Breakdown
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Signal Quality Breakdown',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...qualityBreakdown.entries.map((entry) {
                    final percentage = totalReadings > 0
                        ? (entry.value / totalReadings * 100)
                        : 0.0;
                    return _buildStatRow(
                      entry.key,
                      '${entry.value} (${percentage.toStringAsFixed(1)}%)',
                    );
                  }).toList(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Network Type Performance
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Network Type Performance',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...networkStats.entries.map((entry) {
                    final avgSignal =
                        entry.value.reduce((a, b) => a + b) /
                        entry.value.length *
                        100;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Column(
                        children: [
                          _buildStatRow(entry.key, ''),
                          Padding(
                            padding: const EdgeInsets.only(left: 16.0),
                            child: Column(
                              children: [
                                _buildStatRow(
                                  'Readings',
                                  '${entry.value.length}',
                                ),
                                _buildStatRow(
                                  'Avg. Signal',
                                  '${avgSignal.toStringAsFixed(1)}%',
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Carrier Performance
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Carrier Performance',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...carrierStats.entries.map((entry) {
                    final avgSignal =
                        entry.value.reduce((a, b) => a + b) /
                        entry.value.length *
                        100;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Column(
                        children: [
                          _buildStatRow(entry.key, ''),
                          Padding(
                            padding: const EdgeInsets.only(left: 16.0),
                            child: Column(
                              children: [
                                _buildStatRow(
                                  'Readings',
                                  '${entry.value.length}',
                                ),
                                _buildStatRow(
                                  'Avg. Signal',
                                  '${avgSignal.toStringAsFixed(1)}%',
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          if (value.isNotEmpty)
            Text(
              value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).primaryColor),
      title: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
      ),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text('About ZoneDrop'),
        content: const Text(
          'ZoneDrop is a signal analyzer app that helps you visualize network coverage in your area. Create heatmaps of signal strength and analyze network performance.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text('Settings'),
        content: const Text('Settings panel coming soon!'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text('Help & Support'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('How to use:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('• Tap "Submit Reading" to record signal strength'),
            Text('• Use filters to view specific networks'),
            Text('• Check Stats tab for detailed analytics'),
            SizedBox(height: 12),
            Text('Need help? Contact pranavagrawal.contact@gmail.com'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showClearDataDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text('Clear All Data'),
        content: const Text(
          'Are you sure you want to clear all recorded data? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                // Clear the list that stores ALL submitted readings
                _allSubmittedReadings.clear(); // <--- NEW LINE!

                // Clear the lists used for map display (if applicable)
                _heatPoints.clear();
                _filteredHeatPoints.clear();

                // Forces the heatmap layer to redraw with no data
                _heatmapKey = UniqueKey();
              });
              Navigator.pop(context); // Dismiss the dialog
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green),
                      SizedBox(width: 8),
                      Text('All data cleared successfully'),
                    ],
                  ),
                  backgroundColor: Colors.green.shade700,
                ),
              );
            },
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Define the content for each tab
    final List<Widget> _widgetOptions = <Widget>[
      // --- Map View Content ---
      _currentLocation == null && _isLocating
          ? const Center(child: CircularProgressIndicator())
          : _currentLocation == null && !_isLocating
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Could not get current location.'),
                  ElevatedButton(
                    onPressed: _determinePosition,
                    child: const Text('Try Again'),
                  ),
                ],
              ),
            )
          : Column(
              // This column contains filters and the map (now wrapped in a Stack)
              children: [
                // Network Type Filter
                Padding(
                  padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 4.0),
                  child: _buildFilterRow(
                    options: _networkTypes,
                    selectedValue: _selectedNetworkType,
                    onTap: _onNetworkTypeSelected,
                    highlightLeft: _networkHighlightLeft,
                    highlightWidth: _networkHighlightWidth,
                  ),
                ),

                // Carrier Filter
                Padding(
                  padding: const EdgeInsets.fromLTRB(16.0, 4.0, 16.0, 8.0),
                  child: _buildFilterRow(
                    options: _carriers,
                    selectedValue: _selectedCarrier,
                    onTap: _onCarrierSelected,
                    highlightLeft: _carrierHighlightLeft,
                    highlightWidth: _carrierHighlightWidth,
                  ),
                ),

                // Enhanced Button-Based Options Panel
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 4.0,
                  ),
                  child: Column(
                    children: [
                      // Options Button
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              setState(() {
                                _isOptionsExpanded = !_isOptionsExpanded;
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(
                                        Icons.tune,
                                        color: Colors.black87,
                                        size: 20,
                                      ),
                                      SizedBox(width: 12),
                                      Text(
                                        'Options',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ],
                                  ),
                                  AnimatedRotation(
                                    turns: _isOptionsExpanded ? 0.5 : 0,
                                    duration: const Duration(milliseconds: 300),
                                    child: const Icon(
                                      Icons.keyboard_arrow_down,
                                      color: Colors.black54,
                                      size: 24,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Expandable Options Content
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOutCubic,
                        height: _isOptionsExpanded ? null : 0,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 250),
                          opacity: _isOptionsExpanded ? 1.0 : 0.0,
                          child: Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.grey.shade200,
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Continuous Mapping Row
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(
                                          Icons.autorenew,
                                          size: 20,
                                          color: Colors.black87,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Continuous Mapping',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Switch(
                                      value: _isContinuousModeOn,
                                      onChanged: (value) {
                                        setState(
                                          () => _isContinuousModeOn = value,
                                        );
                                        value
                                            ? _startContinuousCollection()
                                            : _stopContinuousCollection();
                                      },
                                      activeColor: Colors.white,
                                      activeTrackColor: Theme.of(
                                        context,
                                      ).primaryColor,
                                      inactiveThumbColor: Colors.grey.shade400,
                                      inactiveTrackColor: Colors.grey.shade300,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 12),

                                // Show My Location Row
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(
                                          Icons.my_location,
                                          size: 20,
                                          color: Colors.black87,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Show My Location',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Switch(
                                      value: _showCurrentLocationMarker,
                                      onChanged: (value) {
                                        setState(
                                          () => _showCurrentLocationMarker =
                                              value,
                                        );
                                      },
                                      activeColor: Colors.white,
                                      activeTrackColor: Theme.of(
                                        context,
                                      ).primaryColor,
                                      inactiveThumbColor: Colors.grey.shade400,
                                      inactiveTrackColor: Colors.grey.shade300,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Map with Floating Submit Button
                Expanded(
                  child: Stack(
                    children: [
                      FlutterMap(
                        options: MapOptions(
                          initialCenter: _currentLocation!,
                          initialZoom: _currentZoom,
                          onPositionChanged: (position, hasGesture) {
                            if (position.zoom != null) {
                              setState(() {
                                _currentZoom = position.zoom!;
                              });
                            }
                          },
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.example.final_zd',
                          ),
                          if (_filteredHeatPoints.isNotEmpty)
                            HeatMapLayer(
                              key: ValueKey(_heatmapKey),
                              heatMapDataSource: InMemoryHeatMapDataSource(
                                data: _filteredHeatPoints,
                              ),
                              heatMapOptions: HeatMapOptions(
                                minOpacity:
                                    0.2, // This handles the overall transparency of the heatmap
                                radius: (_currentZoom < 10)
                                    ? 24
                                    : (_currentZoom < 16)
                                    ? 18
                                    : 14, // No value below 12–14!
                                gradient: <double, MaterialColor>{
                                  // Intensity (0.0 to 1.0) : Color
                                  0.0: Colors
                                      .lightBlue, // Very weak signal - light blue
                                  0.1: Colors.blue, // Weak signal - blue
                                  0.2: Colors
                                      .indigo, // Slightly stronger weak signal - darker blue

                                  0.3: Colors
                                      .cyan, // Transition from blue to green
                                  0.4: Colors
                                      .lightGreen, // Moderate signal - light green
                                  0.5: Colors.green, // Moderate signal - green

                                  0.6: Colors
                                      .lime, // Good signal - yellowish-green
                                  0.7: Colors
                                      .yellow, // **Around 60% signal equivalent will be yellow**
                                  0.8: Colors.orange, // Strong signal - orange

                                  0.9: Colors
                                      .deepOrange, // Very strong signal - deep orange
                                  1.0: Colors.red, // Excellent signal - red
                                },
                              ),
                            ),
                          // --- PLACE THE ANIMATED MARKER CODE HERE ---
                          // Your new AnimatedBuilder containing the MarkerLayer
                          if (_currentLocation != null &&
                              _showCurrentLocationMarker)
                            AnimatedBuilder(
                              animation:
                                  _markerAnimation, // Now animating _markerAnimation directly
                              builder: (context, child) {
                                final animatedPoint = _markerAnimation
                                    .value; // Get the animated point directly
                                return MarkerLayer(
                                  markers: [
                                    Marker(
                                      point:
                                          animatedPoint, // Use the animated point for smooth movement
                                      width:
                                          12.0, // Increased width/height to give the icon more space, adjust as needed
                                      height:
                                          12.0, // Match width for a consistent shape
                                      alignment: Alignment.center,
                                      child: const Center(
                                        // Use Center to perfectly center the icon within its bounds
                                        child: Icon(
                                          Icons
                                              .my_location, // The location icon
                                          color: Colors
                                              .black, // Color of the icon inside the marker
                                          size:
                                              22, // Adjusted icon size to be visible but not fill the entire marker area
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                        ],
                      ),

                      // Floating Submit Reading Button
                      if (!_isContinuousModeOn)
                        Positioned(
                          bottom: 16.0,
                          left: 16.0,
                          right: 16.0,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 500),
                            switchInCurve: Curves.elasticOut,
                            switchOutCurve: Curves.easeInBack,
                            transitionBuilder:
                                (Widget child, Animation<double> animation) {
                                  return ScaleTransition(
                                    scale: animation,
                                    child: child,
                                  );
                                },
                            child: ElevatedButton(
                              key: const ValueKey('submit_button'),
                              onPressed: _isSubmitting
                                  ? null
                                  : () async {
                                      setState(() {
                                        _isSubmitting = true;
                                      });
                                      if (_currentLocation != null) {
                                        _showCustomSnackBar(
                                          message: 'Recording signal...',
                                          icon: Icons.radio_button_checked,
                                          backgroundColor: Colors.blue.shade600,
                                          duration: const Duration(
                                            milliseconds: 1500,
                                          ),
                                        );

                                        await _determinePosition();

                                        if (!_isLocating &&
                                            _currentLocation != null) {
                                          final signalInfo =
                                              await _getNetworkSignalInfo();
                                          final String networkType =
                                              signalInfo['networkType'];
                                          final double signalWeight =
                                              signalInfo['signalWeight'];
                                          final String carrierName =
                                              signalInfo['carrierName'];

                                          final newReadingPoint =
                                              NetworkWeightedLatLng(
                                                latLng: _currentLocation!,
                                                intensity: signalWeight,
                                                networkType: networkType,
                                                carrier: carrierName,
                                              );

                                          setState(() {
                                            _allSubmittedReadings.add(
                                              newReadingPoint,
                                            );
                                            final existingIndex =
                                                _findExistingPointIndex(
                                                  _currentLocation!,
                                                );
                                            if (existingIndex != null) {
                                              _heatPoints[existingIndex] =
                                                  newReadingPoint;
                                            } else {
                                              _heatPoints.add(newReadingPoint);
                                            }
                                            _heatmapKey = UniqueKey();
                                            _applyHeatmapFilter();
                                            _isSubmitting = false;
                                          });

                                          if (mounted) {
                                            _showCustomSnackBar(
                                              message:
                                                  'Signal Recorded Successfully!',
                                              subtitle:
                                                  '$networkType ($carrierName) - ${(signalWeight * 100).toStringAsFixed(0)}% strength',
                                              icon: Icons.check_circle,
                                              backgroundColor:
                                                  Colors.green.shade600,
                                              duration: const Duration(
                                                seconds: 3,
                                              ),
                                            );
                                          }
                                        } else {
                                          setState(() => _isSubmitting = false);
                                          if (mounted) {
                                            _showCustomSnackBar(
                                              message:
                                                  'Failed to get current location to record signal.',
                                              icon: Icons.error_outline,
                                              backgroundColor:
                                                  Colors.red.shade600,
                                              duration: const Duration(
                                                seconds: 3,
                                              ),
                                            );
                                          }
                                        }
                                      } else {
                                        setState(() => _isSubmitting = false);
                                        if (mounted) {
                                          _showCustomSnackBar(
                                            message:
                                                'Cannot submit reading without current location.',
                                            icon: Icons.error_outline,
                                            backgroundColor:
                                                Colors.red.shade600,
                                            duration: const Duration(
                                              seconds: 3,
                                            ),
                                          );
                                        }
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isSubmitting
                                    ? Colors.grey.shade400
                                    : Theme.of(context).primaryColor,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30.0),
                                ),
                                elevation: _isSubmitting ? 2.0 : 8.0,
                                minimumSize: const Size(double.infinity, 56.0),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16.0,
                                ),
                              ),
                              child: _isSubmitting
                                  ? const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  Colors.white,
                                                ),
                                          ),
                                        ),
                                        SizedBox(width: 12),
                                        Text('Recording...'),
                                      ],
                                    )
                                  : const Text(
                                      'Submit Reading',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
      // --- Stats View Content (Placeholder) ---
      _buildStatsPage(),
    ];

    return Scaffold(
      key:
          _scaffoldKey, // Make sure _scaffoldKey is declared in your _HomeScreenState
      drawer: Drawer(
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drawer Header
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
                child: Container(
                  height: 240, // Increased from 185 to prevent overflow
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Theme.of(context).primaryColor,
                        Theme.of(context).primaryColor.withOpacity(0.8),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: 24,
                    horizontal: 16,
                  ),
                  child: Center(
                    // Center everything vertically
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Rectangular logo (no ClipOval)
                        SizedBox(
                          height: 100,
                          child: Image.asset(
                            'assets/logo.png', // Make sure this matches your actual path
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'ZoneDrop',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const Text(
                          'Signal Analyzer',
                          style: TextStyle(fontSize: 15, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Menu Items
              ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildDrawerItem(
                    icon: Icons.info_outline,
                    title: 'About App',
                    onTap: () {
                      Navigator.pop(context);
                      _showAboutDialog();
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.settings,
                    title: 'Settings',
                    onTap: () {
                      Navigator.pop(context);
                      _showSettingsDialog();
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.help_outline,
                    title: 'Help & Support',
                    onTap: () {
                      Navigator.pop(context);
                      _showHelpDialog();
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.delete_sweep,
                    title: 'Clear Data',
                    onTap: () {
                      Navigator.pop(context);
                      _showClearDataDialog();
                    },
                  ),
                  const Divider(),
                  _buildDrawerItem(
                    icon: Icons.share,
                    title: 'Share App',
                    onTap: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Share functionality coming soon!'),
                        ),
                      );
                    },
                  ),
                ],
              ),

              // Footer
              Container(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Version 1.0.0',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),

      // END OF DRAWER BLOCK
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Theme.of(context).primaryColor,
                Theme.of(context).primaryColor.withOpacity(0.8),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: true,
            title: const Text(
              'ZoneDrop',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 24,
                letterSpacing: 1.2,
              ),
            ),
            actions: [
              Container(
                margin: const EdgeInsets.only(right: 8),
                child: IconButton(
                  onPressed: _refreshData,
                  icon: const Icon(Icons.refresh_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.2),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  tooltip: 'Refresh Data',
                ),
              ),
            ],
            leading: Container(
              margin: const EdgeInsets.only(left: 8),
              child: IconButton(
                onPressed: () {
                  // This is correct: it uses the _scaffoldKey to open the drawer
                  _scaffoldKey.currentState?.openDrawer();
                },
                icon: const Icon(Icons.menu_rounded),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.2),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _selectedIndex = index;
          });
          _updateNavHighlight(index);
        },
        children: _widgetOptions,
      ),
      bottomNavigationBar: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        padding: const EdgeInsets.all(8.0),
        height: 74.0, // <--- ADD THIS LINE! Adjust value as needed
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 15,
              spreadRadius: 2,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          key:
              _navBarStackKey, // Ensure this key is still assigned to the Stack
          children: [
            if (_isInitialized)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOutQuart,
                left: _navHighlightLeft,
                width: _navHighlightWidth,
                height: 56.0, // This height is for the highlight pill
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor,
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).primaryColor.withOpacity(0.4),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(
                  itemKey: _navKeys['Map']!,
                  icon: Icons.map_outlined,
                  activeIcon: Icons.map,
                  label: 'Map',
                  index: 0,
                  isSelected: _selectedIndex == 0,
                  onTap: () => _onItemTapped(0),
                ),
                _buildNavItem(
                  itemKey: _navKeys['Stats']!,
                  icon: Icons.analytics_outlined,
                  activeIcon: Icons.analytics,
                  label: 'Stats',
                  index: 1,
                  isSelected: _selectedIndex == 1,
                  onTap: () => _onItemTapped(1),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
