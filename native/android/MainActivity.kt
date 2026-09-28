package hu.logisticaims.aims_flow_scanner

import android.content.Context
import android.provider.Settings
import android.telephony.TelephonyManager
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "hu.logisticaims.aims_flow/hands_free"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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
