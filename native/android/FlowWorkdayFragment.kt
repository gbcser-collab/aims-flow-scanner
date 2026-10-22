package hu.logisticaims.aims_flow_scanner

import io.flutter.embedding.android.FlutterFragment

/** Decide at detach time, after the driver has started or closed a workday.
 * FlutterFragmentActivity's builder captures its flag too early for this. */
class FlowWorkdayFragment : FlutterFragment() {
    override fun shouldDestroyEngineWithHost(): Boolean {
        val plugin = flutterEngine?.plugins?.get(FlowRuntimePlugin::class.java) as? FlowRuntimePlugin
        return plugin?.trackingActive != true
    }
}
