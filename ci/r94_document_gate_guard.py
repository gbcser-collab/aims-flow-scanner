from pathlib import Path

review=Path("lib/screens/scan_review_screen.dart").read_text(encoding="utf-8")
scanner=Path("lib/screens/scanner_screen.dart").read_text(encoding="utf-8")
smart=Path("lib/screens/smart_document_scanner_screen.dart").read_text(encoding="utf-8")
shell=Path("lib/screens/driver_shell_screen.dart").read_text(encoding="utf-8")
backend=Path("server/aims-tracking/driver_job_document.php").read_text(encoding="utf-8")

checks={
    "review returns exact id": "Navigator.of(context).pop(saved.id)" in review,
    "normal scanner result mode": "returnDocumentIdOnSave" in scanner and "push<String>" in scanner,
    "smart scanner result mode": "returnCmrDocumentIdOnSave" in smart and "push<String>" in smart,
    "shell exact linker": "_linkCmrDocumentToJob" in shell,
    "shell normal exact mode": "returnDocumentIdOnSave: true" in shell,
    "shell smart exact mode": "returnCmrDocumentIdOnSave: true" in shell,
    "no heuristic linker": "_linkNewestCmrToJob" not in shell and "scanStartedAt" not in shell,
    "pending gate remains open": "_isServerBackedCmrState(_jobCmrStates[job.id])" in shell,
    "backend blocks unsynced docs": "document_not_synced" in backend,
}
bad=[name for name,ok in checks.items() if not ok]
if bad:
    raise SystemExit("R94_DOCUMENT_GATE_FAIL: "+", ".join(bad))
print("R94_DOCUMENT_GATE_GUARD_PASS")
