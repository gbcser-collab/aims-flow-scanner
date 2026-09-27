from pathlib import Path

shell = Path("lib/screens/driver_shell_screen.dart").read_text(encoding="utf-8")

required = [
    "Future<void> _initializeSafely()",
    "Future<void> _initializeSyncSafely()",
    "Future<void> _maybeAnnouncePreArrivalSafely(",
    "Future<void> _updateDisplayLocationSafely(",
    "Future<void> safe(Future<void> Function() action)",
    "Widget _headerIdentity()",
    "Widget _headerControls()",
    "constraints.maxWidth < 470",
    "const AimsFlowLogo(width: 60, height: 60)",
    "scale: 1.36",
    "childAspectRatio: .90",
    "height: 38",
    "maxLines: 3",
    "FittedBox(",
    "'KOPPINTS A KÜLDÉSHEZ'",
]
for needle in required:
    if needle not in shell:
        raise SystemExit(f"R101 guard missing: {needle}")

# The old 42px header logo and one-line signal title caused the reported clipping/overflow.
if "const AimsFlowLogo(width: 42, height: 42)" in shell:
    raise SystemExit("old clipped 42px header logo still present")
if "maxLines: 1,\n                        overflow: TextOverflow.ellipsis,\n                        style: const TextStyle(\n                          color: Colors.white,\n                          fontSize: 16" in shell:
    raise SystemExit("old one-line signal title still present")

print("R101 runtime / logo / signal typography guard: PASS")
