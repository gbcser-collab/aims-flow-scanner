from __future__ import annotations

import os
from typing import Any

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from pydantic import BaseModel
from fastapi.responses import JSONResponse

from .extractor import DocumentExtractor, DocumentIngestError, DocumentPasswordRequired
from .freight_parser import FreightOrderParser
from .job_activation import JobActivationError, activate_tracking_job


app = FastAPI(
    title="AIMS Flow Document Intelligence",
    version="1.3.0",
    docs_url="/docs" if os.getenv("AIMS_DOCINTEL_DOCS", "0") == "1" else None,
    redoc_url=None,
)

extractor = DocumentExtractor()
parser = FreightOrderParser()


@app.get("/health")
def health() -> dict:
    return {"ok": True, "service": "aims-flow-document-intelligence", "version": "1.3.0"}


@app.post("/v1/document/parse")
async def parse_document(
    file: UploadFile = File(...),
    password: str | None = Form(default=None),
    include_raw_text: bool = Form(default=False),
) -> JSONResponse:
    try:
        data = await file.read()
        extracted = extractor.extract(data, file.filename or "document", password=password)
        order = parser.parse(extracted.full_text)
    except DocumentPasswordRequired as exc:
        raise HTTPException(status_code=422, detail={"code": "password_required", "message": str(exc)})
    except DocumentIngestError as exc:
        raise HTTPException(status_code=422, detail={"code": "document_unreadable", "message": str(exc)})
    except Exception:
        raise HTTPException(
            status_code=500,
            detail={"code": "document_processing_failed", "message": "A dokumentum feldolgozása sikertelen."},
        )

    return JSONResponse(
        {
            "ok": True,
            "document": extracted.to_dict(include_page_text=include_raw_text),
            "freightOrder": order.to_dict(include_raw_text=include_raw_text),
            "driverJob": order.to_driver_payload(),
        }
    )


class JobActivationRequest(BaseModel):
    plate: str
    driverJob: dict[str, Any]
    approved: bool = False


@app.post("/v1/job/activate")
def activate_job(payload: JobActivationRequest) -> JSONResponse:
    if not payload.approved:
        raise HTTPException(
            status_code=422,
            detail={
                "code": "human_approval_required",
                "message": "A kinyert fuvaradatokat adminnak jóvá kell hagynia aktiválás előtt.",
            },
        )
    if len(payload.plate.strip()) < 4:
        raise HTTPException(status_code=422, detail={"code": "invalid_plate"})

    try:
        result = activate_tracking_job(
            plate=payload.plate,
            driver_job=payload.driverJob,
        )
    except JobActivationError as exc:
        raise HTTPException(
            status_code=502,
            detail={"code": "tracking_activation_failed", "message": str(exc)},
        )

    return JSONResponse({"ok": True, "tracking": result})
