// lib/models/heatmap_point.dart (or wherever you're storing models)

import 'package:latlong2/latlong.dart';
import 'package:flutter_map_heatmap/flutter_map_heatmap.dart';

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
