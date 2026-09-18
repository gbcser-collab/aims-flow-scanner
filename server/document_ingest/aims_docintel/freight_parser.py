from __future__ import annotations

import re
from dataclasses import asdict, dataclass, field


@dataclass
class Stop:
    company: str | None = None
    address: str | None = None
    date: str | None = None
    time_window: str | None = None
    contact: str | None = None
    raw: str = ""
    confidence: float = 0.0

    def to_dict(self) -> dict:
        return {
            "company": self.company,
            "address": self.address,
            "date": self.date,
            "timeWindow": self.time_window,
            "contact": self.contact,
            "raw": self.raw,
            "confidence": round(self.confidence, 3),
        }


@dataclass
class FreightOrder:
    reference: str | None = None
    customer: str | None = None
    pickups: list[Stop] = field(default_factory=list)
    deliveries: list[Stop] = field(default_factory=list)
    cargo_description: str | None = None
    pieces: int | None = None
    pallets: int | None = None
    weight_kg: float | None = None
    vehicle_requirement: str | None = None
    notes: str | None = None
    confidence: float = 0.0
    requires_review: bool = True
    warnings: list[str] = field(default_factory=list)
    raw_text: str = ""

    def to_dict(self, include_raw_text: bool = True) -> dict:
        data = {
            "reference": self.reference,
            "customer": self.customer,
            "pickups": [stop.to_dict() for stop in self.pickups],
            "deliveries": [stop.to_dict() for stop in self.deliveries],
            "cargoDescription": self.cargo_description,
            "pieces": self.pieces,
            "pallets": self.pallets,
            "weightKg": self.weight_kg,
            "vehicleRequirement": self.vehicle_requirement,
            "notes": self.notes,
            "confidence": round(self.confidence, 3),
            "requiresReview": self.requires_review,
            "warnings": self.warnings,
        }
        if include_raw_text:
            data["rawText"] = self.raw_text
        return data

    def to_driver_payload(self) -> dict:
        """Only operational fields intended for the driver UI."""
        def driver_stop(stop: Stop) -> dict:
            return {
                "company": stop.company,
                "address": stop.address,
                "date": stop.date,
                "timeWindow": stop.time_window,
                "contact": stop.contact,
                "confidence": round(stop.confidence, 3),
            }

        return {
            "reference": self.reference,
            "pickups": [driver_stop(stop) for stop in self.pickups],
            "deliveries": [driver_stop(stop) for stop in self.deliveries],
            "cargo": {
                "description": self.cargo_description,
                "pieces": self.pieces,
                "pallets": self.pallets,
                "weightKg": self.weight_kg,
            },
            "vehicleRequirement": self.vehicle_requirement,
            "notes": self.notes,
            "confidence": round(self.confidence, 3),
            "requiresReview": self.requires_review,
        }


class FreightOrderParser:
    """
    Template-independent freight-order parser.

    It intentionally keeps a human-review gate. Unknown layouts are returned with
    lower confidence instead of silently inventing route data.
    """

    LOAD_LABELS = (
        "load", "loading", "loading place", "pickup", "pick up", "collection",
        "felrakó", "felrakóhely", "felvétel", "rakodás",
        "beladung", "ladestelle", "abholung",
        "załadunek", "zaladunek", "miejsce załadunku", "miejsce zaladunku",
        "nakládka", "nakladka", "místo nakládky", "misto nakladky",
        "nakládka", "nakladka", "miesto nakládky", "miesto nakladky",
        "chargement", "enlèvement", "enlevement",
        "pakrovimas", "paėmimas", "paemimas",
    )
    UNLOAD_LABELS = (
        "unload", "unloading", "delivery", "delivery place", "drop off", "dropoff",
        "lerakó", "lerakóhely", "kiszolgáltatás", "leadás",
        "entladung", "entladestelle", "ablieferung",
        "rozładunek", "rozladunek", "miejsce dostawy",
        "vykládka", "vykladka", "místo vykládky", "misto vykladky",
        "vykládka", "vykladka", "miesto vykládky", "miesto vykladky",
        "livraison", "déchargement", "dechargement",
        "pristatymas", "iškrovimas", "iskrovimas",
    )

    REFERENCE_LABELS = (
        "reference", "ref.", "ref ", "order no", "order number", "job no", "job number",
        "transport order", "freight order", "booking no", "shipment no",
        "megbízás", "megbízás száma", "fuvarszám", "fuvarazonosító", "referencia",
        "auftrag", "auftragsnr", "referenz",
        "zlecenie", "nr zlecenia", "referencja",
        "objednávka", "cislo objednavky", "číslo objednávky",
    )
    CUSTOMER_LABELS = (
        "customer", "client", "principal", "ordering party",
        "megrendelő", "ügyfél", "partner",
        "kunde", "auftraggeber",
        "klient", "zleceniodawca",
    )
    CARGO_LABELS = (
        "goods", "cargo", "commodity", "description of goods", "nature of goods",
        "áru", "áru megnevezése", "rakomány",
        "ware", "gut", "warenbeschreibung",
        "towar", "opis towaru",
        "marchandise", "description marchandise",
    )
    VEHICLE_LABELS = (
        "vehicle", "vehicle type", "truck", "van", "required vehicle", "equipment",
        "jármű", "járműigény", "autó", "felépítmény",
        "fahrzeug", "fahrzeugtyp",
        "pojazd", "typ pojazdu",
    )
    NOTES_LABELS = (
        "note", "notes", "remark", "remarks", "instruction", "instructions",
        "megjegyzés", "utasítás",
        "bemerkung", "hinweis",
        "uwagi", "instrukcje",
    )

    DATE_PATTERNS = (
        re.compile(r"\b(?:0?[1-9]|[12]\d|3[01])[./-](?:0?[1-9]|1[0-2])[./-](?:20)?\d{2}\b"),
        re.compile(r"\b20\d{2}[./-](?:0?[1-9]|1[0-2])[./-](?:0?[1-9]|[12]\d|3[01])\b"),
    )
    TIME_PATTERN = re.compile(
        r"(?<!\d)(?:[01]?\d|2[0-3])[:.]\d{2}(?![./-]\d)(?:\s*(?:-|–|—|to|bis|ig)\s*(?:[01]?\d|2[0-3])[:.]\d{2}(?![./-]\d))?\b",
        re.IGNORECASE,
    )
    PHONE_PATTERN = re.compile(r"(?<!\d)(?:\+\d{1,3}[\s./-]?)?(?:\d[\s./-]?){7,14}(?!\d)")
    EMAIL_PATTERN = re.compile(r"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b", re.IGNORECASE)

    def parse(self, raw_text: str) -> FreightOrder:
        text = self._clean(raw_text)
        lines = [line for line in text.splitlines() if line.strip()]
        order = FreightOrder(raw_text=raw_text)

        order.reference = self._label_value(lines, self.REFERENCE_LABELS)
        order.customer = self._label_value(lines, self.CUSTOMER_LABELS)
        order.cargo_description = self._label_value(lines, self.CARGO_LABELS, continuation=2)
        order.vehicle_requirement = self._label_value(lines, self.VEHICLE_LABELS, continuation=1)
        order.notes = self._label_value(lines, self.NOTES_LABELS, continuation=2)

        order.weight_kg = self._weight(text)
        order.pallets = self._count(
            text,
            r"(?:pallets?|paletta|paletták|raklap(?:ok)?|paletten|palette|palety|palet)",
        )
        order.pieces = self._count(
            text,
            r"(?:pcs|pieces|pc|db|darab|stück|stuck|szt\.?|sztuk|ks)",
        )

        segments = self._stop_segments(lines)
        for stop_type, segment in segments:
            stop = self._parse_stop(segment)
            if stop_type == "load":
                order.pickups.append(stop)
            else:
                order.deliveries.append(stop)

        if not order.pickups:
            fallback = self._stop_from_label(lines, self.LOAD_LABELS)
            if fallback:
                order.pickups.append(fallback)
        if not order.deliveries:
            fallback = self._stop_from_label(lines, self.UNLOAD_LABELS)
            if fallback:
                order.deliveries.append(fallback)

        if order.reference is None:
            order.reference = self._reference_fallback(lines)

        order.confidence = self._confidence(order)
        order.requires_review = (
            order.confidence < 0.78
            or not order.pickups
            or not order.deliveries
            or any(stop.confidence < 0.5 for stop in order.pickups + order.deliveries)
        )

        if not order.pickups:
            order.warnings.append("Felrakóhely nem azonosítható biztosan.")
        if not order.deliveries:
            order.warnings.append("Lerakóhely nem azonosítható biztosan.")
        if not order.reference:
            order.warnings.append("Fuvarreferencia nem található.")
        if order.requires_review:
            order.warnings.append("A dokumentum emberi ellenőrzést igényel kiküldés előtt.")

        return order

    def _stop_segments(self, lines: list[str]) -> list[tuple[str, list[str]]]:
        found: list[tuple[int, str]] = []
        for index, line in enumerate(lines):
            stop_type = self._heading_type(line)
            if stop_type:
                found.append((index, stop_type))

        segments: list[tuple[str, list[str]]] = []
        for pos, (start, stop_type) in enumerate(found):
            end = found[pos + 1][0] if pos + 1 < len(found) else min(len(lines), start + 10)
            segment = lines[start:end]
            if segment:
                segments.append((stop_type, segment))
        return segments

    def _heading_type(self, line: str) -> str | None:
        normalized = self._key(line)
        # Check UNLOAD first: words such as "unload" and "unloading" contain
        # "load"/"loading" and would otherwise be misclassified as pickup.
        if any(self._label_in_key(label, normalized) for label in self.UNLOAD_LABELS):
            return "unload"
        if any(self._label_in_key(label, normalized) for label in self.LOAD_LABELS):
            return "load"
        return None

    def _parse_stop(self, segment: list[str]) -> Stop:
        heading = segment[0]
        body = list(segment[1:])
        inline = self._value_after_any_label(heading, self.LOAD_LABELS + self.UNLOAD_LABELS)
        if inline:
            body.insert(0, inline)

        raw = "\n".join(segment)
        date = self._first_match(raw, self.DATE_PATTERNS)
        time_window = self.TIME_PATTERN.search(raw)
        contact = self._contact(raw)

        useful = [
            line for line in body
            if not self._looks_like_meta(line)
            and line != date
            and (time_window is None or time_window.group(0) not in line)
        ]

        address = next((line for line in useful if self._looks_like_address(line)), None)
        company = next(
            (
                line for line in useful
                if line != address
                and not self._looks_like_contact(line)
                and len(line) >= 3
            ),
            None,
        )

        if address is None and useful:
            if len(useful) >= 2:
                address = " ".join(useful[1:3])
            elif self._looks_like_address(useful[0]):
                address = useful[0]

        score = 0.15
        score += 0.28 if address else 0
        score += 0.16 if company else 0
        score += 0.18 if date else 0
        score += 0.12 if time_window else 0
        score += 0.06 if contact else 0

        return Stop(
            company=company,
            address=address,
            date=date,
            time_window=time_window.group(0).replace(".", ":") if time_window else None,
            contact=contact,
            raw=raw,
            confidence=min(1.0, score),
        )

    def _stop_from_label(self, lines: list[str], labels: tuple[str, ...]) -> Stop | None:
        for index, line in enumerate(lines):
            value = self._value_after_any_label(line, labels)
            if value:
                segment = [line] + lines[index + 1:index + 5]
                return self._parse_stop(segment)
            if any(self._label_in_key(label, self._key(line)) for label in labels):
                segment = lines[index:index + 6]
                return self._parse_stop(segment)
        return None

    def _label_value(
        self,
        lines: list[str],
        labels: tuple[str, ...],
        continuation: int = 0,
    ) -> str | None:
        for index, line in enumerate(lines):
            value = self._value_after_any_label(line, labels)
            if value:
                extras: list[str] = []
                for next_line in lines[index + 1:index + 1 + continuation]:
                    if self._heading_type(next_line) or self._looks_like_meta(next_line):
                        break
                    extras.append(next_line)
                return self._clean_inline(" ".join([value] + extras))
        return None

    def _value_after_any_label(self, line: str, labels: tuple[str, ...]) -> str | None:
        for label in sorted(labels, key=len, reverse=True):
            candidate = label.strip()
            if not candidate:
                continue
            match = re.search(
                rf"(?<!\w){re.escape(candidate)}(?!\w)",
                line,
                re.IGNORECASE,
            )
            if match is None:
                continue
            tail = line[match.end():]
            tail = re.sub(r"^[\s:;,.#|\-–—/]+", "", tail).strip()
            if len(tail) >= 2:
                return tail
        return None

    def _reference_fallback(self, lines: list[str]) -> str | None:
        for line in lines[:30]:
            for match in re.finditer(r"\b[A-Z0-9][A-Z0-9/_-]{5,30}\b", line.upper()):
                value = match.group(0)
                if any(ch.isdigit() for ch in value) and any(ch.isalpha() for ch in value):
                    if not self._looks_like_date(value):
                        return value
        return None

    def _weight(self, text: str) -> float | None:
        ton = re.search(
            r"\b(\d{1,3}(?:[.,]\d{1,3})?)\s*(?:t|ton|tons|tonne|tonnes)\b",
            text,
            re.IGNORECASE,
        )
        if ton:
            return round(float(ton.group(1).replace(",", ".")) * 1000, 3)
        kg = re.search(
            r"\b(\d{1,6}(?:[.,]\d{1,3})?)\s*(?:kg|kgs|kilogram|kilograms)\b",
            text,
            re.IGNORECASE,
        )
        return float(kg.group(1).replace(",", ".")) if kg else None

    def _count(self, text: str, unit_pattern: str) -> int | None:
        match = re.search(rf"\b(\d{{1,5}})\s*{unit_pattern}\b", text, re.IGNORECASE)
        return int(match.group(1)) if match else None

    def _contact(self, text: str) -> str | None:
        email = self.EMAIL_PATTERN.search(text)
        phone_text = text
        for pattern in self.DATE_PATTERNS:
            phone_text = pattern.sub(" ", phone_text)
        phone_text = self.TIME_PATTERN.sub(" ", phone_text)
        phone = self.PHONE_PATTERN.search(phone_text)
        values = []
        if phone:
            values.append(phone.group(0).strip())
        if email:
            values.append(email.group(0).strip())
        return " • ".join(values) if values else None

    def _first_match(self, text: str, patterns: tuple[re.Pattern, ...]) -> str | None:
        for pattern in patterns:
            match = pattern.search(text)
            if match:
                return match.group(0)
        return None

    def _confidence(self, order: FreightOrder) -> float:
        score = 0.0
        score += 0.12 if order.reference else 0
        score += 0.08 if order.customer else 0
        score += 0.26 if order.pickups else 0
        score += 0.26 if order.deliveries else 0
        score += 0.10 if order.cargo_description else 0
        score += 0.06 if order.weight_kg is not None else 0
        score += 0.05 if order.vehicle_requirement else 0
        score += 0.04 if order.pallets is not None or order.pieces is not None else 0
        if order.pickups:
            score += min(0.015, sum(s.confidence for s in order.pickups) * 0.01)
        if order.deliveries:
            score += min(0.015, sum(s.confidence for s in order.deliveries) * 0.01)
        return min(1.0, score)

    def _looks_like_address(self, line: str) -> bool:
        return bool(
            re.search(r"\b\d{3,5}\b", line)
            or re.search(
                r"\b(street|str\.?|straße|strasse|road|rd\.?|utca|út|u\.|allee|weg|ul\.?|ulica|rue|avenue|av\.?|g\.)\b",
                line,
                re.IGNORECASE,
            )
        )

    def _looks_like_contact(self, line: str) -> bool:
        return bool(self.EMAIL_PATTERN.search(line) or self.PHONE_PATTERN.search(line))

    def _looks_like_meta(self, line: str) -> bool:
        key = self._key(line)
        all_labels = (
            self.REFERENCE_LABELS + self.CUSTOMER_LABELS + self.CARGO_LABELS
            + self.VEHICLE_LABELS + self.NOTES_LABELS
        )
        return any(self._label_in_key(label, key) for label in all_labels)

    def _looks_like_date(self, value: str) -> bool:
        return any(pattern.search(value) for pattern in self.DATE_PATTERNS)

    def _label_in_key(self, label: str, key: str) -> bool:
        label_key = self._key(label)
        if not label_key:
            return False
        return re.search(
            rf"(?:^|\s){re.escape(label_key)}(?:\s|$)",
            key,
        ) is not None

    def _key(self, value: str) -> str:
        value = value.lower()
        value = value.replace("ő", "o").replace("ű", "u")
        value = value.replace("á", "a").replace("é", "e").replace("í", "i")
        value = value.replace("ó", "o").replace("ö", "o").replace("ü", "u")
        value = value.replace("ł", "l").replace("ż", "z").replace("ź", "z")
        value = value.replace("č", "c").replace("š", "s").replace("ž", "z")
        return re.sub(r"[^a-z0-9]+", " ", value).strip()

    def _clean(self, value: str) -> str:
        value = value.replace("\r", "\n").replace("\x00", " ")
        value = re.sub(r"[\t\f\v]+", " ", value)
        value = re.sub(r" +", " ", value)
        value = re.sub(r"\n{3,}", "\n\n", value)
        return "\n".join(line.strip() for line in value.splitlines()).strip()

    def _clean_inline(self, value: str) -> str:
        return re.sub(r"\s+", " ", value).strip(" :;,|-")
