# AIMS Flow production signing baseline

R103 establishes the production signing identity for AIMS Flow.

- Certificate subject: CN=AIMS Flow, OU=Software, O=Logistic-AIMS Kft, C=HU
- Certificate SHA-256: 4caf49e8d7e973389fdb0958bf3de110f6d1206f9a4cf1595e0be00529114607
- Key algorithm: RSA 4096
- Baseline version: 1.5.9+25
- Baseline APK: AIMS-Flow-R103.apk
- APK SHA-256: d412566db3f804800bdcdca44c6fcd4dfd007871936a06fcecf5432c543191a6

Future Android releases MUST reuse this signing identity.
Do not generate a new release key for normal upgrades.
The owner backup is stored outside this repository.
