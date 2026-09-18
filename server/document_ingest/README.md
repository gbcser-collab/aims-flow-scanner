# AIMS Flow Document Intelligence v1.2

A freight-order ingest layer for AIMS Flow. It is intentionally separate from the stable Android scanner core.

## Goal

Turn heterogeneous dispatcher/customer attachments into one validated freight-order JSON model before the job is sent to the driver.

### Supported input families

- PDF with embedded/selectable text
- scanned/image-only PDF
- hybrid PDF (embedded text + scanned pages)
- rotated scanned PDF (OCR fallback checks rotations when recognition is weak)
- structurally damaged PDF when pikepdf can normalize it
- password protected PDF when the caller supplies the password
- AcroForm field values in PDFs
- DOCX
- DOCM (OOXML text only; macros are never executed)
- legacy DOC via isolated LibreOffice conversion
- RTF / ODT via isolated LibreOffice conversion
- JPG / PNG / TIFF / WEBP via OCR
- TXT / CSV

No parser can truthfully guarantee every malformed, DRM-protected or cryptographically locked document on earth. This service therefore fails closed: unreadable or low-confidence documents are not silently dispatched.

## Extraction strategy

1. Detect type from magic bytes / OOXML structure, not only extension.
2. Extract native text first.
3. On weak or image-heavy PDF pages, run OCR.
4. Merge OCR and embedded text without duplicating lines.
5. Normalize Word formats into readable text.
6. Parse the normalized text into a template-independent freight model.
7. Return a confidence score and `requiresReview` flag.
8. Only the operational `driverJob` payload is intended for the driver app.

## Freight fields

- reference
- customer
- one or more pickup stops
- one or more delivery stops
- company / address / date / time window / contact per stop
- cargo description
- pieces / pallets
- gross weight
- vehicle requirement
- operational notes

The parser contains labels for HU / EN / DE / PL / CZ / SK / FR / LT style documents and is designed so more aliases can be added without touching the Android app.

## API

Run:

```bash
cd server/document_ingest
pip install -r requirements.txt
uvicorn aims_docintel.api:app --host 127.0.0.1 --port 8091
```

Parse:

```bash
curl -F "file=@order.pdf" http://127.0.0.1:8091/v1/document/parse
```

Password protected PDF:

```bash
curl -F "file=@order.pdf" -F "password=secret" http://127.0.0.1:8091/v1/document/parse
```

The response contains:

- `document`: extraction diagnostics
- `freightOrder`: admin-side normalized data
- `driverJob`: operational payload safe for the driver workflow

## Production dependencies

OCR requires Tesseract. Default language request:

`hun+eng+deu+pol+slk+ces+fra+lit`

The extractor automatically uses the subset actually installed. Legacy DOC/RTF/ODT requires LibreOffice/soffice.

Environment variables:

- `AIMS_DOC_MAX_BYTES` (default 25 MB)
- `AIMS_OCR_LANGS`
- `AIMS_LIBREOFFICE_BIN`
- `AIMS_PDF_OCR_SCALE` (default 2.4)
- `AIMS_DOCINTEL_DOCS=1` to enable FastAPI docs

## Safety and dispatch rule

The result must not be auto-dispatched when:

- pickup or delivery is missing,
- stop confidence is low,
- overall `requiresReview=true`,
- the document could not be decrypted/read.

This is deliberate. AIMS Flow should show the extracted fields to the admin, allow correction, then create the connected freight order and send it to the driver.

## CLI

```bash
python -m aims_docintel.cli ./order.docx --raw
```
