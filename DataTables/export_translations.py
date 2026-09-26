#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from __future__ import annotations

import csv
import re
import sys
from copy import copy
from pathlib import Path

try:
    from openpyxl import load_workbook
except ImportError:
    print("错误：缺少 openpyxl 依赖。")
    print("请先安装：pip install openpyxl")
    raise SystemExit(1)


SHEET_ORDER = ["UI", "Herbs", "Formulas", "Diseases", "NPC"]
EXPECTED_HEADER = ["keys", "zh_CN", "en"]

SYMPTOM_KEY_PREFIX = "UI_DISEASE_SYMPTOM_"
PLACEHOLDER_RE = re.compile(r"%(?:[-+0 #]*\d*(?:\.\d+)?)?[sdif]")


def as_text(value) -> str:
    if value is None:
        return ""
    return str(value).strip()


def placeholders(value: str) -> list[str]:
    return PLACEHOLDER_RE.findall(value or "")


def find_data_xlsx(explicit_path: Path | None, managed_xlsx: Path) -> Path | None:
    """
    Locate Data.xlsx.

    Priority:
    1. Third command-line argument
    2. Same folder as translations_managed.xlsx
    3. ../DataTables/Data.xlsx relative to translations_managed.xlsx
    4. ./DataTables/Data.xlsx relative to translations_managed.xlsx
    5. Current working directory variants
    """
    if explicit_path is not None:
        return explicit_path if explicit_path.exists() else None

    candidates = [
        managed_xlsx.parent / "Data.xlsx",
        managed_xlsx.parent.parent / "DataTables" / "Data.xlsx",
        managed_xlsx.parent / "DataTables" / "Data.xlsx",
        Path("Data.xlsx"),
        Path("../DataTables/Data.xlsx"),
        Path("DataTables/Data.xlsx"),
    ]

    seen = set()
    for path in candidates:
        try:
            resolved = path.resolve()
        except OSError:
            resolved = path

        key = str(resolved)
        if key in seen:
            continue
        seen.add(key)

        if path.exists():
            return path

    return None


def validate_managed_sheets(wb) -> None:
    missing = [name for name in SHEET_ORDER if name not in wb.sheetnames]
    if missing:
        raise ValueError("翻译工作簿缺少以下工作表： " + ", ".join(missing))

    for sheet_name in SHEET_ORDER:
        ws = wb[sheet_name]
        header = [as_text(ws.cell(1, col).value) for col in range(1, 4)]
        if header != EXPECTED_HEADER:
            raise ValueError(
                f"{sheet_name} 的表头必须是 {EXPECTED_HEADER}，当前实际为 {header}"
            )


def read_disease_symptoms(data_xlsx: Path) -> list[tuple[str, list[str]]]:
    """
    Read Data.xlsx -> Disease -> DiseaseID + Symptoms.
    Symptoms uses | as the separator.
    """
    wb = load_workbook(data_xlsx, data_only=True, read_only=True)

    if "Disease" not in wb.sheetnames:
        raise ValueError(f"{data_xlsx} 缺少 Disease 工作表")

    ws = wb["Disease"]
    headers = {
        as_text(cell.value): index
        for index, cell in enumerate(ws[1], start=1)
        if as_text(cell.value)
    }

    for required in ("DiseaseID", "Symptoms"):
        if required not in headers:
            raise ValueError(f"Data.xlsx 的 Disease 工作表缺少列：{required}")

    id_col = headers["DiseaseID"]
    symptoms_col = headers["Symptoms"]

    result: list[tuple[str, list[str]]] = []
    seen_ids: set[str] = set()

    for row_no in range(2, ws.max_row + 1):
        disease_id = as_text(ws.cell(row_no, id_col).value)
        raw_symptoms = as_text(ws.cell(row_no, symptoms_col).value)

        if not disease_id:
            continue

        if disease_id in seen_ids:
            raise ValueError(
                f"Data.xlsx 的 Disease 工作表第 {row_no} 行存在重复的 DiseaseID： "
                f"{disease_id}"
            )
        seen_ids.add(disease_id)

        symptoms = [
            item.strip()
            for item in raw_symptoms.split("|")
            if item and item.strip()
        ]

        result.append((disease_id, symptoms))

    return result


def parse_symptom_key(key: str) -> tuple[str, int] | None:
    if not key.startswith(SYMPTOM_KEY_PREFIX):
        return None

    rest = key[len(SYMPTOM_KEY_PREFIX):]
    match = re.fullmatch(r"(.+)_([0-9]{2,})", rest)
    if match is None:
        return None

    return match.group(1).lower(), int(match.group(2))


def copy_row_style(source_ws, source_row: int, target_ws, target_row: int) -> None:
    for col in range(1, 4):
        source = source_ws.cell(source_row, col)
        target = target_ws.cell(target_row, col)

        if source.has_style:
            target._style = copy(source._style)
        if source.number_format:
            target.number_format = source.number_format
        target.font = copy(source.font)
        target.fill = copy(source.fill)
        target.border = copy(source.border)
        target.alignment = copy(source.alignment)
        target.protection = copy(source.protection)

    target_ws.row_dimensions[target_row].height = source_ws.row_dimensions[source_row].height


def update_table_ranges(ws) -> None:
    """
    The managed workbook uses Excel tables.
    After deleting/appending symptom rows, extend any table on this sheet to the new end row.
    """
    if ws.max_row < 1:
        return

    for table in ws.tables.values():
        # All localization tables are A:C tables.
        table.ref = f"A1:C{ws.max_row}"


def sync_disease_symptoms(managed_wb, disease_symptoms: list[tuple[str, list[str]]]) -> list[str]:
    """
    Synchronize UI_DISEASE_SYMPTOM_* rows in the Diseases sheet.

    Translation preservation priority:
    1. Same disease + same Chinese symptom
    2. Same Chinese symptom anywhere in old symptom rows
    3. Otherwise English remains blank and export stops so it can be translated

    This means reordering Symptoms in Data.xlsx will not attach the wrong English
    translation to the new _01 / _02 / _03 numbering.
    """
    ws = managed_wb["Diseases"]

    existing_by_disease_and_zh: dict[tuple[str, str], str] = {}
    existing_by_zh: dict[str, str] = {}
    symptom_rows: list[int] = []

    style_source_row: int | None = None

    for row_no in range(2, ws.max_row + 1):
        key = as_text(ws.cell(row_no, 1).value)
        parsed = parse_symptom_key(key)
        if parsed is None:
            continue

        disease_id, _index = parsed
        zh = as_text(ws.cell(row_no, 2).value)
        en = as_text(ws.cell(row_no, 3).value)

        symptom_rows.append(row_no)

        if style_source_row is None:
            style_source_row = row_no

        if zh and en:
            existing_by_disease_and_zh[(disease_id, zh)] = en
            existing_by_zh.setdefault(zh, en)

    # If the workbook has no symptom rows yet, use the last ordinary Diseases row
    # as the formatting template.
    if style_source_row is None:
        style_source_row = max(ws.max_row, 2)

    # Remove old symptom rows bottom-up.
    for row_no in reversed(symptom_rows):
        ws.delete_rows(row_no, 1)

    missing_english: list[str] = []

    for disease_id, symptoms in disease_symptoms:
        for index, zh in enumerate(symptoms, start=1):
            key = f"{SYMPTOM_KEY_PREFIX}{disease_id.upper()}_{index:02d}"

            en = existing_by_disease_and_zh.get((disease_id.lower(), zh), "")
            if not en:
                en = existing_by_zh.get(zh, "")

            target_row = ws.max_row + 1
            copy_row_style(ws, style_source_row, ws, target_row)

            ws.cell(target_row, 1).value = key
            ws.cell(target_row, 2).value = zh
            ws.cell(target_row, 3).value = en

            if not en:
                missing_english.append(f"{key} | {zh}")

    update_table_ranges(ws)
    return missing_english


def save_managed_workbook_safely(wb, path: Path) -> None:
    """
    Save through a temporary file, then replace the original.
    This reduces the risk of leaving a damaged workbook if saving is interrupted.
    """
    temp_path = path.with_name(path.stem + ".__tmp__" + path.suffix)

    try:
        wb.save(temp_path)
        temp_path.replace(path)
    finally:
        if temp_path.exists():
            try:
                temp_path.unlink()
            except OSError:
                pass


def export_csv(wb, out_csv: Path) -> tuple[int, list[str]]:
    all_rows: list[list[str]] = []
    seen: dict[str, str] = {}
    warnings: list[str] = []

    for sheet_name in SHEET_ORDER:
        ws = wb[sheet_name]
        count = 0

        for row_no in range(2, ws.max_row + 1):
            key = as_text(ws.cell(row_no, 1).value)
            zh = as_text(ws.cell(row_no, 2).value)
            en = as_text(ws.cell(row_no, 3).value)

            if not key and not zh and not en:
                continue

            if not key or not zh or not en:
                raise ValueError(
                    f"数据不完整：{sheet_name} 第 {row_no} 行 "
                    f"(key={key!r}, zh_CN={zh!r}, en={en!r})"
                )

            if key in seen:
                raise ValueError(
                    f"发现重复 key {key!r}：{seen[key]} 与 "
                    f"{sheet_name} row {row_no}"
                )

            seen[key] = f"{sheet_name} row {row_no}"

            zh_ph = placeholders(zh)
            en_ph = placeholders(en)
            if sorted(zh_ph) != sorted(en_ph):
                warnings.append(
                    f"{sheet_name} row {row_no} {key}: "
                    f"zh={zh_ph}, en={en_ph}"
                )

            all_rows.append([key, zh, en])
            count += 1

        print(f"{sheet_name}：{count} 条")

    out_csv.parent.mkdir(parents=True, exist_ok=True)

    with out_csv.open("w", encoding="utf-8-sig", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(EXPECTED_HEADER)
        writer.writerows(all_rows)

    return len(all_rows), warnings


def main() -> int:
    managed_xlsx = (
        Path(sys.argv[1])
        if len(sys.argv) > 1
        else Path("translations_managed.xlsx")
    )
    out_csv = (
        Path(sys.argv[2])
        if len(sys.argv) > 2
        else Path("translations.csv")
    )
    explicit_data_xlsx = Path(sys.argv[3]) if len(sys.argv) > 3 else None

    if not managed_xlsx.exists():
        print("错误：找不到翻译管理表：", managed_xlsx)
        return 1

    data_xlsx = find_data_xlsx(explicit_data_xlsx, managed_xlsx)
    if data_xlsx is None:
        print("错误：找不到 Data.xlsx。")
        print("请把 Data.xlsx 路径作为第三个参数传入，例如：")
        print(
            "  python export_translations.py "
            "translations_managed.xlsx translations.csv ../DataTables/Data.xlsx"
        )
        return 1

    print("翻译管理表：", managed_xlsx)
    print("疾病数据来源：", data_xlsx)
    print("输出 CSV：", out_csv)
    print()

    try:
        wb = load_workbook(managed_xlsx)
        validate_managed_sheets(wb)

        disease_symptoms = read_disease_symptoms(data_xlsx)
        symptom_count = sum(len(items) for _disease_id, items in disease_symptoms)

        print(
            f"正在同步 Disease!Symptoms： "
            f"{len(disease_symptoms)} 个疾病，{symptom_count} 条症状"
        )

        missing_english = sync_disease_symptoms(wb, disease_symptoms)

        # New Chinese symptoms need human translation before producing a game CSV.
        if missing_english:
            save_managed_workbook_safely(wb, managed_xlsx)
            print("症状已同步到 Diseases 工作表。")
            print()
            print("停止导出：发现新增症状尚未填写英文翻译。")
            print(
                "以下症状已写入 translations_managed.xlsx，但 en 列仍为空："
            )
            for item in missing_english:
                print(" -", item)
            print()
            print("请补全这些英文翻译，保存工作簿后再重新运行本脚本。")
            return 2

        # Validate and stage the CSV before changing either user-facing file.
        # A bad row must not update the workbook while leaving the game CSV stale.
        staged_csv = out_csv.with_name(out_csv.name + ".__tmp__")
        try:
            total, warnings = export_csv(wb, staged_csv)
            if warnings:
                raise ValueError("中英文占位符不一致：\n" + "\n".join(warnings))
            save_managed_workbook_safely(wb, managed_xlsx)
            staged_csv.replace(out_csv)
        finally:
            staged_csv.unlink(missing_ok=True)

        print()
        print(f"已导出 {total} 条翻译 -> {out_csv}")

        print("占位符检查：通过")

        print()
        print("下一步：将 translations.csv 替换到 res://Localization/ 下，并在 Godot 中重新导入。")
        return 0

    except PermissionError as exc:
        print("错误：", exc)
        print(
            "请先关闭 Excel/WPS 中打开的 translations_managed.xlsx，然后重新运行导出脚本。"
        )
        return 1
    except Exception as exc:
        print("错误：", exc)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
