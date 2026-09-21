package hu.logisticaims.aims_flow_scanner

import android.app.role.RoleManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.telephony.TelephonyManager
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "hu.logisticaims.aims_flow/hands_free"
    private var handsFreeChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        handsFreeChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        )

        handsFreeChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    try {
                        val intent = Intent(this, AimsHandsFreeService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    } catch (error: Throwable) {
                        result.error("hands_free_start_failed", error.message, null)
                    }
                }

                "stop" -> {
                    stopService(Intent(this, AimsHandsFreeService::class.java))
                    result.success(true)
                }

                "isRunning" -> result.success(AimsHandsFreeService.running)

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

                "requestAssistantRole" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            val roleManager = getSystemService(RoleManager::class.java)
                            if (roleManager != null &&
                                roleManager.isRoleAvailable(RoleManager.ROLE_ASSISTANT)
                            ) {
                                if (!roleManager.isRoleHeld(RoleManager.ROLE_ASSISTANT)) {
                                    startActivity(
                                        roleManager.createRequestRoleIntent(
                                            RoleManager.ROLE_ASSISTANT
                                        )
                                    )
                                }
                                result.success(true)
                            } else {
                                startActivity(Intent(Settings.ACTION_VOICE_INPUT_SETTINGS))
                                result.success(true)
                            }
                        } else {
                            startActivity(Intent(Settings.ACTION_VOICE_INPUT_SETTINGS))
                            result.success(true)
                        }
                    } catch (error: Throwable) {
                        result.error("assistant_role_failed", error.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }

        if (intent?.action == Intent.ACTION_ASSIST) {
            handsFreeChannel?.invokeMethod("assistantInvoked", null)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.action == Intent.ACTION_ASSIST) {
            handsFreeChannel?.invokeMethod("assistantInvoked", null)
        }
    }
}