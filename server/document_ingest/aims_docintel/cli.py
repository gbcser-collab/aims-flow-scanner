from __future__ import annotations

import argparse
import json
from pathlib import Path

from .extractor import DocumentExtractor
from .freight_parser import FreightOrderParser


def main() -> int:
    ap = argparse.ArgumentParser(description="AIMS Flow document intelligence")
    ap.add_argument("document", type=Path)
    ap.add_argument("--password")
    ap.add_argument("--raw", action="store_true", help="Include extracted raw text")
    args = ap.parse_args()

    data = args.document.read_bytes()
    extracted = DocumentExtractor().extract(data, args.document.name, password=args.password)
    order = FreightOrderParser().parse(extracted.full_text)
    print(
        json.dumps(
            {
                "document": extracted.to_dict(include_page_text=args.raw),
                "freightOrder": order.to_dict(include_raw_text=args.raw),
                "driverJob": order.to_driver_payload(),
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
