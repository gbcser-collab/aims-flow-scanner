package hu.logisticaims.aims_flow_scanner

import android.app.Activity
import android.app.ActivityManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.telephony.TelephonyManager
import android.view.WindowManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/** Application-owned callbacks keep working when the Activity is detached.
 * No Activity is retained after detach; no hidden location or boot restart. */
class FlowRuntimePlugin : FlutterPlugin, ActivityAware {
    private lateinit var context: Context
    private var activity: Activity? = null
    private var methods: MethodChannel? = null
    private var events: EventChannel? = null
    private var sink: EventChannel.EventSink? = null
    private var callback: ConnectivityManager.NetworkCallback? = null
    private val main = Handler(Looper.getMainLooper())
    var trackingActive = false
        private set

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        events = EventChannel(binding.binaryMessenger, "hu.logisticaims.aims_flow/connectivity").also {
            it.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) { startNetwork(events) }
                override fun onCancel(arguments: Any?) { stopNetwork() }
            })
        }
        methods = MethodChannel(binding.binaryMessenger, "hu.logisticaims.aims_flow/hands_free").also {
            it.setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "setTrackingActive" -> {
                            trackingActive = call.argument<Boolean>("active") == true
                            result.success(true)
                        }
                        "trackingReadiness" -> {
                            val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
                            val notifications = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                            val manager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                            result.success(mapOf(
                                "batteryOptimized" to !power.isIgnoringBatteryOptimizations(context.packageName),
                                "powerSave" to power.isPowerSaveMode,
                                "notifications" to notifications.areNotificationsEnabled(),
                                "backgroundRestricted" to (Build.VERSION.SDK_INT >= 28 && manager.isBackgroundRestricted)
                            ))
                        }
                        "openBatterySettings" -> {
                            val host = activity
                            if (host == null) result.success(false) else {
                                host.startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                                result.success(true)
                            }
                        }
                        "openAppSettings" -> {
                            val host = activity
                            if (host == null) result.success(false) else {
                                host.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                    Uri.parse("package:${context.packageName}")))
                                result.success(true)
                            }
                        }
                        "networkCountry" -> {
                            val tel = context.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
                            result.success(mapOf("network" to tel?.networkCountryIso?.trim()?.uppercase().orEmpty(),
                                "sim" to tel?.simCountryIso?.trim()?.uppercase().orEmpty()))
                        }
                        "applyNightBrightnessCap" -> {
                            val host = activity
                            if (host == null) result.success(null) else {
                                val cap = (call.argument<Double>("cap") ?: 0.35).toFloat().coerceIn(0.05f, 1f)
                                val brightness = Settings.System.getInt(context.contentResolver,
                                    Settings.System.SCREEN_BRIGHTNESS, 128).coerceIn(1, 255) / 255f
                                val target = minOf(brightness, cap)
                                val params = host.window.attributes
                                params.screenBrightness = target
                                host.window.attributes = params
                                result.success(target.toDouble())
                            }
                        }
                        "resetAppBrightness" -> {
                            activity?.let { host ->
                                val params = host.window.attributes
                                params.screenBrightness = WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                                host.window.attributes = params
                            }
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: RuntimeException) {
                    result.error("flow_platform_error", error.message, null)
                }
            }
        }
    }

    private fun startNetwork(target: EventChannel.EventSink) {
        stopNetwork()
        sink = target
        val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        fun emit(online: Boolean) { main.post { if (sink === target) target.success(online) } }
        val listener = object : ConnectivityManager.NetworkCallback() {
            // A default-network handoff is not an outage. Report validated capabilities.
            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
                emit(capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                    capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED))
            }
            override fun onLost(network: Network) {
                val caps = manager.getNetworkCapabilities(manager.activeNetwork)
                emit(caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true)
            }
        }
        callback = listener
        try { manager.registerDefaultNetworkCallback(listener) }
        catch (error: RuntimeException) {
            stopNetwork()
            target.error("network_monitor_unavailable", error.message, null)
        }
    }

    private fun stopNetwork() {
        sink = null
        val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        callback?.let { try { manager.unregisterNetworkCallback(it) } catch (_: RuntimeException) {} }
        callback = null
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopNetwork()
        methods?.setMethodCallHandler(null)
        events?.setStreamHandler(null)
        activity = null
    }
    override fun onAttachedToActivity(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivity() { activity = null }
    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { activity = binding.activity }
}
