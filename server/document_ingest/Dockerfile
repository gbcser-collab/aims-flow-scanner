FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    AIMS_OCR_LANGS=hun+eng+deu+pol+slk+ces+fra+lit

RUN apt-get update && apt-get install -y --no-install-recommends \
    libreoffice-writer \
    tesseract-ocr \
    tesseract-ocr-hun \
    tesseract-ocr-eng \
    tesseract-ocr-deu \
    tesseract-ocr-pol \
    tesseract-ocr-slk \
    tesseract-ocr-ces \
    tesseract-ocr-fra \
    tesseract-ocr-lit \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY aims_docintel ./aims_docintel

EXPOSE 8091
CMD ["uvicorn", "aims_docintel.api:app", "--host", "0.0.0.0", "--port", "8091"]
