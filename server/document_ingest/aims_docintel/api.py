from __future__ import annotations

import os

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import JSONResponse

from .extractor import DocumentExtractor, DocumentIngestError, DocumentPasswordRequired
from .freight_parser import FreightOrderParser


app = FastAPI(
    title="AIMS Flow Document Intelligence",
    version="1.2.0",
    docs_url="/docs" if os.getenv("AIMS_DOCINTEL_DOCS", "0") == "1" else None,
    redoc_url=None,
)

extractor = DocumentExtractor()
parser = FreightOrderParser()


@app.get("/health")
def health() -> dict:
    return {"ok": True, "service": "aims-flow-document-intelligence", "version": "1.2.0"}


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
