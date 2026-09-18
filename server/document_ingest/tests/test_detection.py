import io
import zipfile

from aims_docintel.extractor import DocumentExtractor


def test_pdf_detected_by_magic_even_with_wrong_extension():
    extractor = DocumentExtractor()
    assert extractor.detect_kind(b"%PDF-1.7\n...", "order.bin") == "pdf"


def test_legacy_doc_detected_by_ole_magic():
    extractor = DocumentExtractor()
    data = bytes.fromhex("D0CF11E0A1B11AE1") + b"legacy"
    assert extractor.detect_kind(data, "order.tmp") == "doc"


def test_docx_detected_from_ooxml_structure():
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, "w") as zf:
        zf.writestr("[Content_Types].xml", "<Types/>")
        zf.writestr("word/document.xml", "<w:document xmlns:w='x'/>")
    extractor = DocumentExtractor()
    assert extractor.detect_kind(stream.getvalue(), "attachment.dat") == "docx"
