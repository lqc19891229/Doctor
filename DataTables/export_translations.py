#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from __future__ import annotations
import csv, re, sys, zipfile, xml.etree.ElementTree as ET
from pathlib import Path

SHEET_ORDER = ["UI", "Herbs", "Formulas", "Diseases", "NPC"]
EXPECTED_HEADER = ["keys", "zh_CN", "en"]
NS_MAIN = {"x": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
PKG_REL = {"p": "http://schemas.openxmlformats.org/package/2006/relationships"}
PLACEHOLDER_RE = re.compile(r"%(?:[-+0 #]*\d*(?:\.\d+)?)?[sdif]")

def column_index(ref):
    letters = re.match(r"[A-Z]+", ref).group(0)
    n = 0
    for ch in letters:
        n = n * 26 + ord(ch) - 64
    return n - 1

def shared_strings(zf):
    path = "xl/sharedStrings.xml"
    if path not in zf.namelist():
        return []
    root = ET.fromstring(zf.read(path))
    return ["".join(t.text or "" for t in si.findall(".//x:t", NS_MAIN))
            for si in root.findall("x:si", NS_MAIN)]

def sheet_paths(zf):
    wb = ET.fromstring(zf.read("xl/workbook.xml"))
    rels_root = ET.fromstring(zf.read("xl/_rels/workbook.xml.rels"))
    rels = {r.attrib["Id"]: r.attrib["Target"]
            for r in rels_root.findall("p:Relationship", PKG_REL)}
    result = {}
    for s in wb.find("x:sheets", NS_MAIN).findall("x:sheet", NS_MAIN):
        rid = s.attrib["{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id"]
        target = rels[rid].lstrip("/")
        if not target.startswith("xl/"):
            target = "xl/" + target
        result[s.attrib["name"]] = target
    return result

def cell_text(cell, shared):
    t = cell.attrib.get("t", "")
    if t == "inlineStr":
        return "".join(x.text or "" for x in cell.findall(".//x:t", NS_MAIN))
    v = cell.find("x:v", NS_MAIN)
    raw = "" if v is None or v.text is None else v.text
    if t == "s":
        return shared[int(raw)] if raw else ""
    return raw

def read_sheet(zf, path, shared):
    root = ET.fromstring(zf.read(path))
    data = root.find("x:sheetData", NS_MAIN)
    out = []
    if data is None:
        return out
    for row in data.findall("x:row", NS_MAIN):
        vals = ["", "", ""]
        for c in row.findall("x:c", NS_MAIN):
            ref = c.attrib.get("r", "")
            if not ref:
                continue
            idx = column_index(ref)
            if 0 <= idx <= 2:
                vals[idx] = cell_text(c, shared)
        out.append(vals)
    return out

def ph(s):
    return PLACEHOLDER_RE.findall(s or "")

def main():
    xlsx = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("translations_managed.xlsx")
    out_csv = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("translations.csv")
    if not xlsx.exists():
        print("ERROR: workbook not found:", xlsx)
        return 1

    all_rows, seen, warnings = [], {}, []
    with zipfile.ZipFile(xlsx, "r") as zf:
        shared = shared_strings(zf)
        paths = sheet_paths(zf)

        missing = [x for x in SHEET_ORDER if x not in paths]
        if missing:
            print("ERROR: missing sheets:", ", ".join(missing))
            return 1

        for sheet in SHEET_ORDER:
            rows = read_sheet(zf, paths[sheet], shared)
            if not rows or rows[0] != EXPECTED_HEADER:
                print(f"ERROR: {sheet} header must be {EXPECTED_HEADER}")
                return 1

            count = 0
            for row_no, row in enumerate(rows[1:], 2):
                key, zh, en = row
                if not key and not zh and not en:
                    continue
                if not key or not zh or not en:
                    print(f"ERROR: incomplete row: {sheet} row {row_no}")
                    return 1
                if key in seen:
                    print(f"ERROR: duplicate key {key}: {seen[key]} and {sheet} row {row_no}")
                    return 1
                seen[key] = f"{sheet} row {row_no}"
                if sorted(ph(zh)) != sorted(ph(en)):
                    warnings.append(f"{sheet} row {row_no} {key}: zh={ph(zh)} en={ph(en)}")
                all_rows.append([key, zh, en])
                count += 1
            print(f"{sheet}: {count} rows")

    with out_csv.open("w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(EXPECTED_HEADER)
        w.writerows(all_rows)

    print(f"\nExported {len(all_rows)} rows -> {out_csv}")
    if warnings:
        print("\nWARNING: placeholder differences:")
        for x in warnings:
            print(" -", x)
    else:
        print("Placeholder check: OK")
    print("\nReplace res://Localization/translations.csv and Reimport it in Godot.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
