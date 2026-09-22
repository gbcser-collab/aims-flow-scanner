from pathlib import Path

push=Path("lib/services/driver_push_service.dart").read_text(encoding="utf-8")
main=Path("lib/main.dart").read_text(encoding="utf-8")

checks={
    "app initializes push": "await DriverPushService.instance.initialize()" in main,
    "single-flight initialization": "Future<void>? _initializationFuture" in push,
    "startup catches local notification errors": "await _initializeLocalNotifications();" in push and "catch (error)" in push,
    "foreground events survive notification errors": "finally {" in push and "_events.add(DriverPushEvent(" in push,
    "transient firebase remains retryable": "_initialized = Firebase.apps.isNotEmpty" in push,
    "token refresh contained": "_refreshPushRegistration" in push and "await registerForPlate(plate)" in push,
    "no eager initialized poison": "if (_initialized) return;\n    _initialized = true;" not in push,
}
bad=[name for name,ok in checks.items() if not ok]
if bad:
    raise SystemExit("R94_PUSH_LIFECYCLE_FAIL: "+", ".join(bad))
print("R94_PUSH_LIFECYCLE_GUARD_PASS")
