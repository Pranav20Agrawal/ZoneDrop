package com.example.final_zd

import android.content.Context
import android.net.wifi.WifiManager
import android.os.Build
import android.telephony.*
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.util.Log

class MainActivity : FlutterActivity() {
    private val CELLULAR_CHANNEL = "com.example.final_zd/signal"
    private val WIFI_CHANNEL = "com.example.final_zd.signal_analyzer/wifi_rssi"
    private val TAG = "SignalAnalyzer"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CELLULAR_CHANNEL).setMethodCallHandler {
            call, result ->
            if (call.method == "getSignalInfo") {
                val info = getSignalInfo()
                if (info != null) {
                    result.success(info)
                } else {
                    result.error("UNAVAILABLE", "Signal information not available", null)
                }
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIFI_CHANNEL).setMethodCallHandler {
            call, result ->
            if (call.method == "getWifiRssi") {
                val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                val wifiInfo = wifiManager.connectionInfo
                val rssi = wifiInfo.rssi // dBm
                result.success(rssi)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun getSignalInfo(): Map<String, Any>? {
        val connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

        val network = connectivityManager.activeNetwork ?: return null
        val capabilities = connectivityManager.getNetworkCapabilities(network) ?: return null

        // Wi-Fi
        if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
            val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            val wifiInfo = wifiManager.connectionInfo

            val ssid = wifiInfo.ssid
            val rssi = wifiInfo.rssi // dBm

            return mapOf(
                "networkType" to "Wi-Fi",
                "carrier" to ssid.replace("\"", ""), // Remove quotes from SSID
                "signalStrengthDbm" to rssi,
                "signalStatus" to "$rssi dBm" // Wi-Fi always provides dBm if connected
            )
        }

        // Mobile Network
        if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) {
            val telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager

            val networkTypeName = when (telephonyManager.dataNetworkType) {
                TelephonyManager.NETWORK_TYPE_LTE -> "4G"
                TelephonyManager.NETWORK_TYPE_NR -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) "5G" else "Unknown"
                }
                TelephonyManager.NETWORK_TYPE_HSPAP,
                TelephonyManager.NETWORK_TYPE_UMTS -> "3G"
                TelephonyManager.NETWORK_TYPE_GPRS,
                TelephonyManager.NETWORK_TYPE_EDGE -> "2G"
                else -> "Unknown"
            }

            // Get carrier name
            val carrierName = telephonyManager.networkOperatorName ?: "Unknown Carrier"

            var dbm = -1 // Default to -1 (unknown)
            var signalStatusMessage = "No numeric signal (fallback)." // Default status message

            try {
                val cellInfoList = telephonyManager.allCellInfo
                for (cellInfo in cellInfoList) {
                    if (cellInfo.isRegistered) {
                        Log.d(TAG, "Found registered cellInfo: $cellInfo")
                        dbm = when (cellInfo) {
                            is CellInfoLte -> cellInfo.cellSignalStrength.dbm
                            is CellInfoNr -> {
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                    cellInfo.cellSignalStrength.dbm
                                } else {
                                    Log.w(TAG, "CellInfoNr not available on API < Q. Cannot get NR signal.")
                                    -1
                                }
                            }
                            is CellInfoWcdma -> cellInfo.cellSignalStrength.dbm
                            is CellInfoGsm -> cellInfo.cellSignalStrength.dbm
                            is CellInfoCdma -> cellInfo.cellSignalStrength.dbm
                            else -> {
                                Log.w(TAG, "Unknown CellInfo type: ${cellInfo.javaClass.simpleName}. Cannot get dBm.")
                                -1
                            }
                        }
                        if (dbm != -1) { // If dBm was successfully retrieved from CellInfo
                            signalStatusMessage = "$dbm dBm"
                        } else {
                            signalStatusMessage = "No numeric signal (from registered cell, dBm -1)."
                        }
                        Log.d(TAG, "Registered cell signal strength: $signalStatusMessage")
                        break // Found the registered cell, no need to check others
                    }
                }
            } catch (e: SecurityException) {
                Log.e(TAG, "SecurityException: Insufficient permissions to access CellInfo. " +
                           "Ensure ACCESS_FINE_LOCATION and READ_PHONE_STATE are granted.", e)
                dbm = -9999 // Indicate a permission error
                signalStatusMessage = "Permission error: ${e.message}"
            } catch (e: Exception) {
                Log.e(TAG, "Error getting cell info: ${e.message}", e)
                dbm = -9999 // Indicate a general error
                signalStatusMessage = "Error: ${e.message}"
            }

            // If dBm is still -1 or -9999 (from errors), keep the fallback status message
            // Otherwise, it's already set to the actual dBm value
            if (dbm == -1 || dbm == -9999) {
                 // No valid dBm was found. The signalStatusMessage will reflect this.
                 // We don't try SignalStrength.getDbm() directly anymore as it's less reliable
                 // and often causes issues.
            }


            return mapOf(
                "networkType" to networkTypeName,
                "carrier" to carrierName,
                "signalStrengthDbm" to dbm,
                "signalStatus" to signalStatusMessage
            )
        }

        return null // If neither Wi-Fi nor Cellular is active
    }
}