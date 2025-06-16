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
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:provider/provider.dart';
import '../theme/theme_provider.dart';
import 'package:http/http.dart' as http;
import 'package:final_zd/theme/app_colors.dart';
import 'screens/stats_dashboard.dart';

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
  String _selectedNetworkType = 'All';
  String _selectedCarrier = 'All';
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
  final double _filterOptionHeight = 36.0;

  bool _isContinuousModeOn = false;
  Timer? _continuousTimer;
  bool _showCurrentLocationMarker = true;
  bool _isOptionsExpanded = false;

  bool _isLegendExpanded = false;
  final GlobalKey _legendButtonKey = GlobalKey();

  // Search functionality variables
  bool _isSearchExpanded = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  Timer? _searchDebounceTimer;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Animation and UI state
  bool _isInitialized = false;
  double _networkHighlightLeft = 0.0;
  double _networkHighlightWidth = 0.0;
  double _carrierHighlightLeft = 0.0;
  double _carrierHighlightWidth = 0.0;
  int _selectedIndex = 0;

  // Animation controllers
  late AnimationController _refreshController;
  late AnimationController _submitController;
  late AnimationController _fadeController;
  late final MapController _mapController;
  late final PageController _pageController;

  // Search animation controllers
  late AnimationController _searchAnimationController;
  late Animation<double> _searchAnimation;

  // Plugin Instances
  final NetworkInfo _networkInfo = NetworkInfo();
  final Connectivity _connectivity = Connectivity();
  static const MethodChannel _wifiChannel = MethodChannel(
    'com.example.final_zd.signal_analyzer/wifi_rssi',
  );

  double _navHighlightLeft = 0.0;
  double _navHighlightWidth = 0.0;

  // Add a GlobalKey for the navigation bar stack (if you don't have it already)
  final GlobalKey _navBarStackKey = GlobalKey();

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

    // Initialize search animation controller
    _searchAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _searchAnimation = CurvedAnimation(
      parent: _searchAnimationController,
      curve: Curves.easeInOutCubic,
    );

    // Search text field listener
    _searchController.addListener(_onSearchChanged);

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
    final networkIndex = _networkTypes.indexOf(_selectedNetworkType);
    final containerWidth =
        MediaQuery.of(context).size.width - 32; // Account for outer padding
    final networkItemWidth =
        (containerWidth - 8) /
        _networkTypes.length; // Account for container padding
    _networkHighlightLeft = networkIndex * networkItemWidth + 2;
    _networkHighlightWidth = networkItemWidth - 4;

    // Calculate carrier highlight with proper padding
    final carrierIndex = _carriers.indexOf(_selectedCarrier);
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
    _searchAnimationController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchDebounceTimer?.cancel();
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

  void _onSearchChanged() {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (_searchController.text.isNotEmpty) {
        _performSearch(_searchController.text);
      } else {
        setState(() {
          _searchResults.clear();
        });
      }
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;

    setState(() {
      _isSearching = true;
    });

    try {
      final encodedQuery = Uri.encodeComponent(query.trim());
      final url =
          'https://nominatim.openstreetmap.org/search?format=json&limit=5&q=$encodedQuery&countrycodes=in';

      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'ZoneDrop/1.0 (Flutter App)'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _searchResults = data
                .map(
                  (item) => {
                    'display_name': item['display_name'] as String,
                    'lat': double.parse(item['lat']),
                    'lon': double.parse(item['lon']),
                    'type': item['type'] ?? 'location',
                    'class': item['class'] ?? 'place',
                    'icon': _getLocationIcon(item['type'], item['class']),
                  },
                )
                .toList();
          });
        }
      }
    } catch (e) {
      print('Search error: $e');
      if (mounted) {
        _showCustomSnackBar(
          message: 'Search failed. Please try again.',
          icon: Icons.error_outline,
          backgroundColor: Colors.red.shade600,
          duration: const Duration(seconds: 2),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  IconData _getLocationIcon(String? type, String? className) {
    switch (type?.toLowerCase()) {
      case 'university':
      case 'college':
      case 'school':
        return Icons.school;
      case 'hospital':
        return Icons.local_hospital;
      case 'restaurant':
      case 'cafe':
        return Icons.restaurant;
      case 'hotel':
        return Icons.hotel;
      case 'shop':
      case 'mall':
        return Icons.shopping_bag;
      case 'park':
        return Icons.park;
      case 'bus_stop':
        return Icons.directions_bus;
      case 'railway':
        return Icons.train;
      default:
        if (className == 'amenity') return Icons.place_outlined;
        if (className == 'building') return Icons.business;
        if (className == 'highway') return Icons.route;
        return Icons.location_on;
    }
  }

  void _toggleSearch() {
    setState(() {
      _isSearchExpanded = !_isSearchExpanded;
    });

    if (_isSearchExpanded) {
      _searchAnimationController.forward();
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) {
          _searchFocusNode.requestFocus();
        }
      });
    } else {
      _searchAnimationController.reverse();
      _searchFocusNode.unfocus();
      _searchController.clear();
      setState(() {
        _searchResults.clear();
      });
    }
  }

  void _jumpToLocation(double lat, double lon, String name) {
    final targetLocation = LatLng(lat, lon);

    // Close search
    _toggleSearch();

    // Animate to location
    _mapController.move(targetLocation, 16.0);

    // Show success message
    _showCustomSnackBar(
      message: 'Jumped to location',
      subtitle: name.length > 50 ? '${name.substring(0, 50)}...' : name,
      icon: Icons.my_location,
      backgroundColor: Colors.green.shade600,
      duration: const Duration(seconds: 2),
    );
  }

  Widget _buildSearchButton() {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: IconButton(
        onPressed: _toggleSearch,
        icon: const Icon(Icons.search_rounded),
        style: IconButton.styleFrom(
          backgroundColor: Colors.white.withOpacity(0.2),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        tooltip: 'Search Location',
      ),
    );
  }

  Widget _buildSearchOverlay() {
    return AnimatedBuilder(
      animation: _searchAnimation,
      builder: (context, child) {
        return Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            margin: const EdgeInsets.all(16),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2 * _searchAnimation.value),
                  blurRadius: 15 * _searchAnimation.value,
                  offset: Offset(0, 8 * _searchAnimation.value),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Search input header
                Container(
                  height: 64,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      // Back button
                      IconButton(
                        onPressed: _toggleSearch,
                        icon: const Icon(Icons.arrow_back_rounded),
                        color: Colors.grey.shade700,
                        splashRadius: 24,
                      ),
                      // Search field
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          decoration: InputDecoration(
                            hintText: 'Search for places in India...',
                            hintStyle: TextStyle(color: Colors.grey.shade500),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 16,
                              horizontal: 12,
                            ),
                          ),
                          style: const TextStyle(fontSize: 16),
                          textInputAction: TextInputAction.search,
                          onSubmitted: (value) {
                            if (value.trim().isNotEmpty) {
                              _performSearch(value.trim());
                            }
                          },
                          onChanged: (value) {
                            _onSearchChanged(); // This triggers debounced search
                          },
                        ),
                      ),
                      // Search/Loading button
                      if (_isSearching)
                        Container(
                          width: 24,
                          height: 24,
                          margin: const EdgeInsets.only(right: 16),
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Theme.of(context).primaryColor,
                            ),
                          ),
                        )
                      else
                        IconButton(
                          onPressed: () {
                            final query = _searchController.text.trim();
                            if (query.isNotEmpty) {
                              _performSearch(query);
                            }
                          },
                          icon: const Icon(Icons.search_rounded),
                          color: Theme.of(context).primaryColor,
                          splashRadius: 20,
                          tooltip: 'Search',
                        ),
                      // Clear button
                      if (_searchController.text.isNotEmpty)
                        IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchResults.clear();
                            });
                          },
                          icon: const Icon(Icons.clear_rounded),
                          color: Colors.grey.shade500,
                          splashRadius: 20,
                        ),
                    ],
                  ),
                ),

                // Search results - Fixed the overflow issue here
                if (_searchResults.isNotEmpty)
                  Flexible(
                    // Changed from direct widget to Flexible
                    child: _buildSearchResultsList(),
                  )
                else if (!_isSearching && _searchController.text.isNotEmpty)
                  // Show "No results" message
                  Container(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        Icon(
                          Icons.search_off_rounded,
                          size: 48,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No results found',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Try searching for a different location',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearchResultsList() {
    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _searchResults.length,
      physics: const BouncingScrollPhysics(),
      separatorBuilder: (context, index) => Divider(
        height: 1,
        color: Colors.grey.shade200,
        indent: 16,
        endIndent: 16,
      ),
      itemBuilder: (context, index) {
        final result = _searchResults[index];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              result['icon'] as IconData,
              color: Theme.of(context).primaryColor,
              size: 20,
            ),
          ),
          title: Text(
            _getShortLocationName(result['display_name']),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            result['display_name'],
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Icon(
            Icons.arrow_forward_ios_rounded,
            size: 16,
            color: Colors.grey.shade400,
          ),
          onTap: () {
            _jumpToLocation(
              result['lat'],
              result['lon'],
              result['display_name'],
            );
          },
        );
      },
    );
  }

  String _getShortLocationName(String fullName) {
    final parts = fullName.split(',');
    if (parts.isNotEmpty) {
      return parts.first.trim();
    }
    return fullName;
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
        bool matchesNetworkType = (_selectedNetworkType == 'All')
            ? true
            : point.networkType == _selectedNetworkType;
        bool matchesCarrier = (_selectedCarrier == 'All')
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

  // Method for theme options
  Widget _buildThemeOption({
    required String title,
    required IconData icon,
    required ThemeMode value,
    required dynamic themeProvider, // Your ThemeProvider instance
  }) {
    final isSelected = themeProvider.themeMode == value;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            themeProvider.setTheme(value);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
                    : Colors.transparent,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.7),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: isSelected
                      ? Icon(
                          Icons.check_circle_rounded,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                          key: const ValueKey('selected'),
                        )
                      : Icon(
                          Icons.radio_button_unchecked_rounded,
                          size: 18,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.3),
                          key: const ValueKey('unselected'),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Enhanced Theme Section Widget
  Widget buildThemeSection(BuildContext context, dynamic themeProvider) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Row(
            children: [
              Icon(
                Icons.palette_rounded,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Theme',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Theme options using the updated method
          _buildThemeOption(
            title: 'Light',
            icon: Icons.wb_sunny_rounded,
            value: ThemeMode.light,
            themeProvider: themeProvider,
          ),
          _buildThemeOption(
            title: 'Dark',
            icon: Icons.dark_mode_rounded,
            value: ThemeMode.dark,
            themeProvider: themeProvider,
          ),
          _buildThemeOption(
            title: 'System Default',
            icon: Icons.settings_brightness_rounded,
            value: ThemeMode.system,
            themeProvider: themeProvider,
          ),
        ],
      ),
    );
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(4.0),
      height: _filterOptionHeight + 8,
      decoration: BoxDecoration(
        color: isDark
            ? Theme.of(context).colorScheme.surface
            : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Stack(
        children: [
          if (_isInitialized)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeInOutQuart,
              left: highlightLeft,
              width: highlightWidth,
              height: _filterOptionHeight,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.getPrimaryColor(context),
                      AppColors.getPrimaryColor(context).withOpacity(0.85),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.getPrimaryColor(
                        context,
                      ).withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
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
                        color: isSelected
                            ? Colors.white
                            : isDark
                            ? Colors.white70
                            : Colors.black87,
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

  Widget _buildFloatingLegend() {
    return Positioned(
      top: 16.0,
      right: 16.0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Legend Content (appears above the button)
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOutCubic,
            height: _isLegendExpanded ? null : 0,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 400),
              opacity: _isLegendExpanded ? 1.0 : 0.0,
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                constraints: const BoxConstraints(maxWidth: 200),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 20,
                      spreadRadius: 2,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Signal Strength',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        Icon(
                          Icons.signal_cellular_alt,
                          size: 18,
                          color: Colors.grey.shade600,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Gradient Bar
                    Container(
                      height: 20,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF03A9F4), // Light Blue
                            Color(0xFF2196F3), // Blue
                            Color(0xFF3F51B5), // Indigo
                            Color(0xFF00BCD4), // Cyan
                            Color(0xFF8BC34A), // Light Green
                            Color(0xFF4CAF50), // Green
                            Color(0xFFCDDC39), // Lime
                            Color(0xFFFFEB3B), // Yellow
                            Color(0xFFFF9800), // Orange
                            Color(0xFFFF5722), // Deep Orange
                            Color(0xFFF44336), // Red
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Labels
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Weak',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          'Strong',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Signal levels
                    ..._buildSignalLevels(),
                  ],
                ),
              ),
            ),
          ),

          // Toggle Button
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOutCubic,
            child: Material(
              elevation: _isLegendExpanded ? 12 : 8,
              borderRadius: BorderRadius.circular(_isLegendExpanded ? 20 : 28),
              shadowColor: Colors.black.withOpacity(0.3),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOutCubic,
                key: _legendButtonKey,
                width: _isLegendExpanded ? 120 : 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _isLegendExpanded
                        ? [
                            Theme.of(context).primaryColor,
                            Theme.of(context).primaryColor.withOpacity(0.8),
                          ]
                        : [Colors.white, Colors.grey.shade50],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(
                    _isLegendExpanded ? 20 : 28,
                  ),
                  border: Border.all(
                    color: _isLegendExpanded
                        ? Colors.transparent
                        : Colors.grey.shade300,
                    width: 1,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(
                      _isLegendExpanded ? 20 : 28,
                    ),
                    onTap: () {
                      setState(() {
                        _isLegendExpanded = !_isLegendExpanded;
                      });
                    },
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      switchInCurve: Curves.easeInOut,
                      switchOutCurve: Curves.easeInOut,
                      child: _isLegendExpanded
                          ? Row(
                              key: const ValueKey('expanded'),
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.legend_toggle,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Legend',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            )
                          : Icon(
                              key: const ValueKey('collapsed'),
                              Icons.legend_toggle_outlined,
                              color: Colors.grey.shade700,
                              size: 24,
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Add this helper method to build signal level indicators
  List<Widget> _buildSignalLevels() {
    final levels = [
      {
        'label': '0-20%',
        'color': const Color(0xFF03A9F4),
        'description': 'Very Weak',
      },
      {
        'label': '20-40%',
        'color': const Color(0xFF4CAF50),
        'description': 'Weak',
      },
      {
        'label': '40-60%',
        'color': const Color(0xFFFFEB3B),
        'description': 'Moderate',
      },
      {
        'label': '60-80%',
        'color': const Color(0xFFFF9800),
        'description': 'Strong',
      },
      {
        'label': '80-100%',
        'color': const Color(0xFFF44336),
        'description': 'Excellent',
      },
    ];

    return levels.map((level) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: level['color'] as Color,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${level['description']} (${level['label']})',
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }).toList();
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

  List<Map<String, dynamic>> _convertReadingsForStats() {
    return _allSubmittedReadings.map((reading) {
      return {
        'carrier': reading.carrier,
        'networkType': reading.networkType,
        'intensity': reading.intensity,
        'latitude': reading.latLng.latitude,
        'longitude': reading.latLng.longitude,
        'timestamp': DateTime.now()
            .millisecondsSinceEpoch, // You can modify this if you have actual timestamps
      };
    }).toList();
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    String? subtitle,
    bool isDestructive = false,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          splashColor: isDestructive
              ? Colors.red.withOpacity(0.1)
              : Theme.of(context).primaryColor.withOpacity(0.1),
          highlightColor: isDestructive
              ? Colors.red.withOpacity(0.05)
              : Theme.of(context).primaryColor.withOpacity(0.05),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 12.0,
            ),
            child: Row(
              children: [
                // Enhanced icon container
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDestructive
                        ? Colors.red.withOpacity(0.1)
                        : Theme.of(context).primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    color: isDestructive
                        ? Colors.red[600]
                        : Theme.of(context).primaryColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                // Text content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: isDestructive
                              ? Colors.red[600]
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Chevron arrow
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.4),
                ),
              ],
            ),
          ),
        ),
      ),
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
    final themeProvider = Provider.of<ThemeProvider>(context);
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
                          color: Theme.of(
                            context,
                          ).cardColor, // Instead of Colors.grey.shade100
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
                                        color:
                                            null, // Remove hardcoded color, let theme handle it
                                        size: 20,
                                      ),
                                      SizedBox(width: 12),
                                      Text(
                                        'Options',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color:
                                              null, // Remove hardcoded color, let theme handle it
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
                              color: Theme.of(
                                context,
                              ).cardColor, // Instead of Colors.white
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Theme.of(
                                  context,
                                ).dividerColor, // Instead of Colors.grey.shade200
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
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.autorenew,
                                          size: 20,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface, // Instead of Colors.black87
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Continuous Mapping',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface, // Instead of Colors.black87
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
                                      activeTrackColor:
                                          AppColors.getPrimaryColor(context),
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
                                        setState(() {
                                          _showCurrentLocationMarker = value;
                                          if (value &&
                                              _currentLocation != null) {
                                            _mapController.move(
                                              _currentLocation!,
                                              _currentZoom,
                                            ); // Move map to current location
                                          }
                                        });
                                      },
                                      activeColor: Colors.white,
                                      activeTrackColor:
                                          AppColors.getPrimaryColor(context),
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
                        mapController: _mapController,
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
                            tileProvider: FMTCStore(
                              'OSMCache',
                            ).getTileProvider(),
                            userAgentPackageName: 'com.example.final_zd',
                          ),
                          if (_filteredHeatPoints.isNotEmpty)
                            HeatMapLayer(
                              key: ValueKey(_heatmapKey),
                              heatMapDataSource: InMemoryHeatMapDataSource(
                                data: _filteredHeatPoints,
                              ),
                              heatMapOptions: HeatMapOptions(
                                minOpacity: 0.2,
                                radius: (_currentZoom < 10)
                                    ? 24
                                    : (_currentZoom < 16)
                                    ? 18
                                    : 14,
                                gradient: <double, MaterialColor>{
                                  0.0: Colors.lightBlue,
                                  0.1: Colors.blue,
                                  0.2: Colors.indigo,
                                  0.3: Colors.cyan,
                                  0.4: Colors.lightGreen,
                                  0.5: Colors.green,
                                  0.6: Colors.lime,
                                  0.7: Colors.yellow,
                                  0.8: Colors.orange,
                                  0.9: Colors.deepOrange,
                                  1.0: Colors.red,
                                },
                              ),
                            ),
                          if (_currentLocation != null &&
                              _showCurrentLocationMarker)
                            AnimatedBuilder(
                              animation: _markerAnimation,
                              builder: (context, child) {
                                final animatedPoint = _markerAnimation.value;
                                return MarkerLayer(
                                  markers: [
                                    Marker(
                                      point: animatedPoint,
                                      width: 12.0,
                                      height: 12.0,
                                      alignment: Alignment.center,
                                      child: const Center(
                                        child: Icon(
                                          Icons.my_location,
                                          color: Colors.black,
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                        ],
                      ),

                      _buildFloatingLegend(),

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
                                    : AppColors.getPrimaryColor(context),
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
      StatsDashboardScreen(readings: _convertReadingsForStats()),
    ];

    return Scaffold(
      key:
          _scaffoldKey, // Make sure _scaffoldKey is declared in your _HomeScreenState
      drawer: Drawer(
        backgroundColor: Theme.of(context).drawerTheme.backgroundColor,
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
                        AppColors.getPrimaryColor(context),
                        AppColors.getPrimaryColor(context).withOpacity(0.8),
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
                  // Enhanced menu items with subtitles
                  _buildDrawerItem(
                    icon: Icons.info_outline_rounded,
                    title: 'About App',
                    subtitle: 'Learn more about this app',
                    onTap: () {
                      Navigator.pop(context);
                      _showAboutDialog();
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.settings_rounded,
                    title: 'Settings',
                    subtitle: 'Customize your experience',
                    onTap: () {
                      Navigator.pop(context);
                      _showSettingsDialog();
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.help_outline_rounded,
                    title: 'Help & Support',
                    subtitle: 'Get assistance when needed',
                    onTap: () {
                      Navigator.pop(context);
                      _showHelpDialog();
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.delete_sweep_rounded,
                    title: 'Clear Data',
                    subtitle: 'Reset all saved information',
                    isDestructive: true,
                    onTap: () {
                      Navigator.pop(context);
                      _showClearDataDialog();
                    },
                  ),

                  const SizedBox(height: 16),

                  // Enhanced Theme Section
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12.0),
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceVariant.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.outline.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Section header
                        Row(
                          children: [
                            Icon(
                              Icons.palette_rounded,
                              size: 18,
                              color: AppColors.getPrimaryColor(context),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Theme',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Theme options using the new method
                        _buildThemeOption(
                          title: 'Light',
                          icon: Icons.wb_sunny_rounded,
                          value: ThemeMode.light,
                          themeProvider: themeProvider,
                        ),
                        _buildThemeOption(
                          title: 'Dark',
                          icon: Icons.dark_mode_rounded,
                          value: ThemeMode.dark,
                          themeProvider: themeProvider,
                        ),
                        _buildThemeOption(
                          title: 'System Default',
                          icon: Icons.settings_brightness_rounded,
                          value: ThemeMode.system,
                          themeProvider: themeProvider,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  _buildDrawerItem(
                    icon: Icons.share_rounded,
                    title: 'Share App',
                    subtitle: 'Tell others about this app',
                    onTap: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text(
                            'Share functionality coming soon!',
                          ),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
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
                AppColors.getPrimaryColor(context),
                AppColors.getPrimaryColor(context).withOpacity(0.8),
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
              // Remove the Stack wrapper and simplify
              _buildSearchButton(),
              Container(
                margin: const EdgeInsets.only(left: 8, right: 16),
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
      body: Stack(
        children: [
          // Your existing PageView
          PageView(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _selectedIndex = index;
              });
              _updateNavHighlight(index);
            },
            children: _widgetOptions,
          ),
          // Search overlay
          if (_isSearchExpanded)
            Positioned.fill(
              child: GestureDetector(
                onTap: _toggleSearch, // Close search when tapping outside
                child: Container(
                  color: Colors.black.withOpacity(0.3),
                  child: GestureDetector(
                    onTap:
                        () {}, // Prevent closing when tapping on search widget
                    child: _buildSearchOverlay(),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        padding: const EdgeInsets.all(8.0),
        height: 74.0,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor, // Instead of Colors.grey.shade200
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
                    color: AppColors.getPrimaryColor(context),
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.getPrimaryColor(context).withOpacity(0.4),
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
