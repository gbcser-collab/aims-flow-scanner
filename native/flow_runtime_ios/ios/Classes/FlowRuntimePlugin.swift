import Flutter
import UIKit
import Network
import CoreLocation
import UserNotifications

public final class FlowRuntimePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private var monitor: NWPathMonitor?
    private var sink: FlutterEventSink?
    private var generation = UUID()
    private var lastPath: String?
    private var lastOnline = false
    private var trackingActive = false

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = FlowRuntimePlugin()
        let methods = FlutterMethodChannel(name: "hu.logisticaims.aims_flow/hands_free", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: methods)
        let events = FlutterEventChannel(name: "hu.logisticaims.aims_flow/connectivity", binaryMessenger: registrar.messenger())
        events.setStreamHandler(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "setTrackingActive":
            trackingActive = (call.arguments as? [String: Any])?["active"] as? Bool ?? false
            // Geolocator owns the sole Core Location session.
            result(nil)
        case "trackingReadiness":
            let active = trackingActive
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                DispatchQueue.main.async {
                    result([
                        "platform": "ios",
                        "trackingActive": active,
                        "powerSave": ProcessInfo.processInfo.isLowPowerModeEnabled,
                        "backgroundRefreshAvailable": UIApplication.shared.backgroundRefreshStatus == .available,
                        "notifications": settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional,
                        "locationEnabled": CLLocationManager.locationServicesEnabled()
                    ])
                }
            }
        case "openAppSettings", "openBatterySettings":
            guard let url = URL(string: UIApplication.openSettingsURLString) else {
                result(false); return
            }
            UIApplication.shared.open(url, options: [:]) { result($0) }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        stopMonitor()
        sink = events
        let current = generation
        let next = NWPathMonitor()
        monitor = next
        next.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let interfaces: [NWInterface.InterfaceType] = [.wifi, .cellular, .wiredEthernet, .other]
            let signature = interfaces.map { path.usesInterfaceType($0) ? "1" : "0" }.joined()
                + "\(path.isExpensive)-\(path.isConstrained)"
            DispatchQueue.main.async {
                guard let self = self, self.generation == current, let sink = self.sink else { return }
                // A Wi-Fi/cellular handoff can stay 'satisfied' throughout.
                if online && self.lastOnline && self.lastPath != signature { sink(false) }
                if online != self.lastOnline || self.lastPath != signature { sink(online) }
                self.lastOnline = online
                self.lastPath = signature
            }
        }
        next.start(queue: DispatchQueue(label: "hu.logisticaims.flow.network"))
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        stopMonitor()
        return nil
    }

    private func stopMonitor() {
        generation = UUID()
        monitor?.cancel()
        monitor = nil
        sink = nil
        lastPath = nil
        lastOnline = false
    }

    deinit { monitor?.cancel() }
}
