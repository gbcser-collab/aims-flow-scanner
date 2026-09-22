from pathlib import Path

p=Path("lib/services/driver_api_service.dart")
text=p.read_text(encoding="utf-8")

required=[
    "_decodeResponse(http.Response response)",
    "body['ok'] != true",
    "DriverApiException(502, 'invalid_json_response')",
    "invalid_jobs_response",
    "invalid_messages_response",
]
for needle in required:
    if needle not in text:
        raise SystemExit(f"R94_RESPONSE_CONTRACT_FAIL missing: {needle}")

if "_decode(response)" in text:
    raise SystemExit("R94_RESPONSE_CONTRACT_FAIL legacy permissive decoder still used")

if text.count("{") != text.count("}"):
    raise SystemExit("R94_RESPONSE_CONTRACT_FAIL Dart brace imbalance")

print("R94_RESPONSE_CONTRACT_GUARD_PASS")


smart=Path("lib/services/smart_document_service.dart").read_text(encoding="utf-8")
for needle in (
    "final documentId = body['documentId']?.toString().trim() ?? '';",
    "final state = body['state']?.toString().trim() ?? '';",
    "documentId.isEmpty || state != 'uploaded'",
    "invalid_smart_document_success_response",
):
    if needle not in smart:
        raise SystemExit(f"R94_RESPONSE_CONTRACT_FAIL smart document missing: {needle}")

print("R94_SMART_DOCUMENT_RESPONSE_CONTRACT_PASS")
