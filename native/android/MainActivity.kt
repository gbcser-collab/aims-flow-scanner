package hu.logisticaims.aims_flow_scanner

import android.content.Context
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache

/** The active location service owns the running engine beyond the UI lifetime. */
class MainActivity : FlutterFragmentActivity() {
    companion object { const val ENGINE_ID = "aims_flow_workday" }

    override fun provideFlutterEngine(context: Context): FlutterEngine? =
        FlutterEngineCache.getInstance().get(ENGINE_ID)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (!flutterEngine.plugins.has(FlowRuntimePlugin::class.java)) {
            flutterEngine.plugins.add(FlowRuntimePlugin())
        }
        FlutterEngineCache.getInstance().put(ENGINE_ID, flutterEngine)
    }

    override fun shouldDestroyEngineWithHost(): Boolean {
        val plugin = flutterEngine?.plugins?.get(FlowRuntimePlugin::class.java) as? FlowRuntimePlugin
        return plugin?.trackingActive != true
    }

    override fun onDestroy() {
        if (shouldDestroyEngineWithHost()) {
            FlutterEngineCache.getInstance().remove(ENGINE_ID)
        }
        super.onDestroy()
    }
}
