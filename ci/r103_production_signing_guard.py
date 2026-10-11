from pathlib import Path

workflow = Path(".github/workflows/aims-flow-driver.yml").read_text(encoding="utf-8")

required = [
    "id-token: write",
    "audience=aims-flow-signing",
    "https://logistic-aims.hu/api/aims-signing/material.php",
    'signingConfigs.getByName("release")',
    "AIMS_SIGN_CERT_SHA256",
    "Unexpected AIMS production certificate fingerprint",
    "PRODUCTION-SIGNED",
]
for needle in required:
    if needle not in workflow:
        raise SystemExit(f"R103 signing guard missing: {needle}")

if "signingConfigs.getByName(\"debug\")' in text:" not in workflow:
    raise SystemExit("R103 signing guard missing runtime debug-signing rejection")

for forbidden in [
    "keytool -genkeypair",
    "signing-password.oaep",
    "aims-flow-release.p12\n            AIMS-Flow",
]:
    if forbidden in workflow:
        raise SystemExit(f"R103 signing guard found forbidden release pattern: {forbidden}")

if "aims-flow-release.p12" in workflow.split("path: |")[-1]:
    raise SystemExit("R103 signing guard: private keystore must never be uploaded as an artifact")

if not any(
    name in workflow
    for name in (
        "AIMS-Flow-R103-PRODUCTION-SIGNED",
        "AIMS-Flow-R104-PRODUCTION-SIGNED",
        "AIMS-Flow-R105-PRODUCTION-SIGNED",
    )
):
    raise SystemExit("Production signing guard missing a versioned production artifact")

print("Persistent production signing guard: PASS")
