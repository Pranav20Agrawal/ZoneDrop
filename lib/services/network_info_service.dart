import 'dart:io';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:flutter/foundation.dart';

class NetworkInfoService {
  static const MethodChannel _wifiChannel = MethodChannel(
    'com.example.final_zd.signal_analyzer/wifi_rssi',
  );

  static const MethodChannel _signalChannel = MethodChannel(
    'com.example.final_zd/signal',
  );

  final Connectivity _connectivity = Connectivity();
  final NetworkInfo _networkInfo = NetworkInfo();

  static Future<Map<String, dynamic>?> getSignalInfo() async {
    try {
      final result = await _signalChannel.invokeMethod('getSignalInfo');
      return Map<String, dynamic>.from(result);
    } on PlatformException catch (e) {
      print("Failed to get signal info: '${e.message}'.");
      return null;
    }
  }

  Future<Map<String, dynamic>> getNetworkSignalInfo() async {
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
        final Map<dynamic, dynamic>? signalInfo = await getSignalInfo();

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

  Future<int?> _getWifiRssiNative() async {
    try {
      final int? rssi = await _wifiChannel.invokeMethod('getWifiRssi');
      return rssi;
    } on PlatformException catch (e) {
      debugPrint("Failed to get WiFi RSSI: '${e.message}'");
      return null;
    }
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
        networkType == '5G') {
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
}
