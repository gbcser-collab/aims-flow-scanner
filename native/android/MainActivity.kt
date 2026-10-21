package hu.logisticaims.aims_flow_scanner

import android.content.Context
import android.provider.Settings
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.telephony.TelephonyManager
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "hu.logisticaims.aims_flow/hands_free"

    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var networkSink: EventChannel.EventSink? = null
    private var networkChannel: EventChannel? = null

    private fun stopNetworkMonitor() {
        networkSink = null
        val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        networkCallback?.let { callback ->
            try { manager?.unregisterNetworkCallback(callback) } catch (_: RuntimeException) {}
        }
        networkCallback = null
    }

    private fun startNetworkMonitor(sink: EventChannel.EventSink) {
        stopNetworkMonitor()
        networkSink = sink
        val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        if (manager == null) { sink.success(false); return }
        val validated = mutableSetOf<Network>()
        fun emit(online: Boolean) {
            runOnUiThread { if (networkSink === sink) sink.success(online) }
        }
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                // Wait for capabilities; availability alone also includes captive portals.
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    validated.clear()
                    emit(false)
                }
            }
            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
                val usable = capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                    capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
                if (usable) validated.add(network) else validated.remove(network)
                emit(validated.isNotEmpty())
            }
            override fun onLost(network: Network) {
                validated.remove(network)
                emit(validated.isNotEmpty())
            }
        }
        networkCallback = callback
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                manager.registerDefaultNetworkCallback(callback)
            } else {
                manager.registerNetworkCallback(
                    NetworkRequest.Builder().addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).build(),
                    callback
                )
            }
        } catch (error: RuntimeException) {
            stopNetworkMonitor()
            sink.error("network_monitor_unavailable", error.message, null)
        }
    }

    override fun onDestroy() {
        stopNetworkMonitor()
        networkChannel?.setStreamHandler(null)
        networkChannel = null
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        networkChannel = EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "hu.logisticaims.aims_flow/connectivity"
        ).also { channel ->
            channel.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    startNetworkMonitor(events)
                }
                override fun onCancel(arguments: Any?) { stopNetworkMonitor() }
            })
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "networkCountry" -> {
                    try {
                        val telephony = getSystemService(
                            Context.TELEPHONY_SERVICE
                        ) as? TelephonyManager
                        val network = telephony
                            ?.networkCountryIso
                            ?.trim()
                            ?.uppercase()
                            .orEmpty()
                        val sim = telephony
                            ?.simCountryIso
                            ?.trim()
                            ?.uppercase()
                            .orEmpty()
                        result.success(
                            mapOf(
                                "network" to network,
                                "sim" to sim
                            )
                        )
                    } catch (error: Throwable) {
                        result.error(
                            "network_country_failed",
                            error.message,
                            null
                        )
                    }
                }

                "applyNightBrightnessCap" -> {
                    try {
                        val cap = (call.argument<Double>("cap") ?: 0.35)
                            .toFloat()
                            .coerceIn(0.05f, 1.0f)
                        val systemBrightness = Settings.System.getInt(
                            contentResolver,
                            Settings.System.SCREEN_BRIGHTNESS,
                            128
                        ).coerceIn(1, 255) / 255f
                        val target = minOf(systemBrightness, cap)
                        runOnUiThread {
                            val params = window.attributes
                            params.screenBrightness = target
                            window.attributes = params
                        }
                        result.success(target.toDouble())
                    } catch (error: Throwable) {
                        result.error(
                            "brightness_cap_failed",
                            error.message,
                            null
                        )
                    }
                }

                "resetAppBrightness" -> {
                    try {
                        runOnUiThread {
                            val params = window.attributes
                            params.screenBrightness =
                                WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                            window.attributes = params
                        }
                        result.success(true)
                    } catch (error: Throwable) {
                        result.error(
                            "brightness_reset_failed",
                            error.message,
                            null
                        )
                    }
                }

                else -> result.notImplemented()
            }
        }
    }
}

