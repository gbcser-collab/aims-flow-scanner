#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path("lib")
errors = []

def find_matching_paren(text: str, open_index: int) -> int:
    depth = 0
    quote = None
    escape = False
    for i in range(open_index, len(text)):
        ch = text[i]
        if quote is not None:
            if escape:
                escape = False
                continue
            if ch == "\\":
                escape = True
                continue
            if ch == quote:
                quote = None
            continue
        if ch in ("'", '"'):
            quote = ch
            continue
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                return i
    return -1

def top_level_color_value(segment: str):
    open_index = segment.find("(")
    close_index = len(segment) - 1
    i = open_index + 1
    dp = db = dr = 0
    quote = None
    escape = False

    while i < close_index:
        ch = segment[i]
        if quote is not None:
            if escape:
                escape = False
                i += 1
                continue
            if ch == "\\":
                escape = True
                i += 1
                continue
            if ch == quote:
                quote = None
            i += 1
            continue
        if ch in ("'", '"'):
            quote = ch
            i += 1
            continue
        if ch == "(":
            dp += 1
            i += 1
            continue
        if ch == ")":
            dp -= 1
            i += 1
            continue
        if ch == "[":
            db += 1
            i += 1
            continue
        if ch == "]":
            db -= 1
            i += 1
            continue
        if ch == "{":
            dr += 1
            i += 1
            continue
        if ch == "}":
            dr -= 1
            i += 1
            continue

        if dp == db == dr == 0 and segment.startswith("color:", i):
            start = i + len("color:")
            while start < close_index and segment[start].isspace():
                start += 1
            j = start
            p = b = r = 0
            q = None
            esc = False
            while j < close_index:
                c = segment[j]
                if q is not None:
                    if esc:
                        esc = False
                    elif c == "\\":
                        esc = True
                    elif c == q:
                        q = None
                    j += 1
                    continue
                if c in ("'", '"'):
                    q = c
                elif c == "(":
                    p += 1
                elif c == ")":
                    if p == 0:
                        break
                    p -= 1
                elif c == "[":
                    b += 1
                elif c == "]":
                    b -= 1
                elif c == "{":
                    r += 1
                elif c == "}":
                    r -= 1
                elif c == "," and p == b == r == 0:
                    break
                j += 1
            return segment[start:j].strip()
        i += 1
    return None

for path in sorted(ROOT.rglob("*.dart")):
    text = path.read_text(encoding="utf-8")

    pos = 0
    while True:
        pos = text.find("TextStyle(", pos)
        if pos < 0:
            break
        open_index = pos + len("TextStyle")
        close_index = find_matching_paren(text, open_index)
        if close_index < 0:
            errors.append(f"{path}: unterminated TextStyle")
            break
        segment = text[pos:close_index + 1]
        value = top_level_color_value(segment)
        if value is not None and value != "Colors.white":
            line = text.count("\n", 0, pos) + 1
            errors.append(
                f"{path}:{line}: TextStyle color must be Colors.white, found {value}"
            )
        pos = close_index + 1

    for marker in ("foregroundColor:",):
        pos = 0
        while True:
            pos = text.find(marker, pos)
            if pos < 0:
                break
            start = pos + len(marker)
            while start < len(text) and text[start].isspace():
                start += 1
            end = start
            while end < len(text) and text[end] not in ",\n)":
                end += 1
            value = text[start:end].strip()
            if value and value != "Colors.white":
                line = text.count("\n", 0, pos) + 1
                errors.append(
                    f"{path}:{line}: foregroundColor must be Colors.white, found {value}"
                )
            pos = max(end, pos + 1)

main = Path("lib/main.dart").read_text(encoding="utf-8")
if "themeMode: ThemeMode.dark" not in main:
    errors.append("lib/main.dart: Flow operational theme must stay dark")
if "bodyColor: Colors.white" not in main or "displayColor: Colors.white" not in main:
    errors.append("lib/main.dart: global text theme must stay white")

if errors:
    print("R105 WHITE TEXT GUARD FAILED")
    for error in errors:
        print(" -", error)
    sys.exit(1)

print("R105 WHITE TEXT GUARD PASS")
