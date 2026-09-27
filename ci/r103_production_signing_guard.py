from pathlib import Path

workflow = Path(".github/workflows/aims-flow-driver.yml").read_text(encoding="utf-8")

required = [
    "id-token: write",
    "audience=aims-flow-signing",
    "https://logistic-aims.hu/api/aims-signing/material.php",
    'signingConfigs.getByName("release")',
    "AIMS_SIGN_CERT_SHA256",
    "Unexpected AIMS production certificate fingerprint",
    "AIMS-Flow-R103-PRODUCTION-SIGNED",
]
for needle in required:
    if needle not in workflow:
        raise SystemExit(f"R103 signing guard missing: {needle}")

for forbidden in [
    "keytool -genkeypair",
    'signingConfigs.getByName("debug")',
    "signing-password.oaep",
    "aims-flow-release.p12\n            AIMS-Flow",
]:
    if forbidden in workflow:
        raise SystemExit(f"R103 signing guard found forbidden release pattern: {forbidden}")

if "aims-flow-release.p12" in workflow.split("path: |")[-1]:
    raise SystemExit("R103 signing guard: private keystore must never be uploaded as an artifact")

print("R103 persistent production signing guard: PASS")
