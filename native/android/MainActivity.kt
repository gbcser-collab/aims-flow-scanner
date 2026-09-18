package hu.logisticaims.aims_flow_scanner

import android.app.role.RoleManager
import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
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
