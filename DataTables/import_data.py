# Doctor/DataTables/import_data.py
# -*- coding: utf-8 -*-

"""
用途：
1. 读取当前脚本同目录下的 Data.xlsx
2. 解析多个 sheet：Book / Herb / Disease / Pulse / Formula / FormulaIngredient / Theory / Npc / Story / StoryLine
3. 支持用名称反查缺失 ID，减少 Excel 重复录入
4. 生成 Godot 可用的 .tres 资源文件

依赖：
    pip install openpyxl

运行方式：
    在 Doctor/DataTables 目录下执行：
        python import_data.py
"""

from __future__ import annotations

from copy import copy
from pathlib import Path
from shutil import copy2
from typing import Any
from openpyxl import load_workbook


# 当前脚本所在目录（Doctor/DataTables）
CURRENT_DIR = Path(__file__).resolve().parent
# 项目基础目录（Doctor）
BASE_DIR = CURRENT_DIR.parent
# Excel 配置表路径
EXCEL_PATH = CURRENT_DIR / "Data.xlsx"
# DetailText 根目录：用于先把 txt 正文写入 Data.xlsx
DETAIL_TEXT_DIR = CURRENT_DIR / "DetailText"
# 导入正文前自动备份 Excel，避免误覆盖无法回退
DETAIL_TEXT_BACKUP_PATH = CURRENT_DIR / "Data.backup_before_detailtext_import.xlsx"
# 导出的 Godot 资源根目录
OUTPUT_DIR = BASE_DIR / "Data"

BOOK_OUTPUT_DIR = OUTPUT_DIR / "Book"/ "Book"
HERB_OUTPUT_DIR = OUTPUT_DIR / "Herb"
DISEASE_OUTPUT_DIR = OUTPUT_DIR / "Disease"
FORMULA_OUTPUT_DIR = OUTPUT_DIR / "Formula"
STORY_OUTPUT_DIR = OUTPUT_DIR / "Story"
NPC_OUTPUT_DIR = OUTPUT_DIR / "Npc"
THEORY_BOOK_ENTRY_OUTPUT_DIR = OUTPUT_DIR / "Book" / "BookEntry" / "TheoryEntry"

HERB_BOOK_ENTRY_OUTPUT_DIR = OUTPUT_DIR / "Book" / "BookEntry" / "HerbEntry"
DISEASE_BOOK_ENTRY_OUTPUT_DIR = OUTPUT_DIR / "Book" / "BookEntry" / "DiseaseEntry"
FORMULA_BOOK_ENTRY_OUTPUT_DIR = OUTPUT_DIR / "Book" / "BookEntry" / "FormulaEntry"


BOOK_DATA_SCRIPT_PATH = "res://System/Book/Book/BookData.gd"
HERB_BOOK_DATA_SCRIPT_PATH = "res://System/Book/Book/HerbBookData.gd"
DISEASE_BOOK_DATA_SCRIPT_PATH = "res://System/Book/Book/DiseaseBookData.gd"
FORMULA_BOOK_DATA_SCRIPT_PATH = "res://System/Book/Book/FormulaBookData.gd"
THEORY_BOOK_DATA_SCRIPT_PATH = "res://System/Book/Book/TheoryBookData.gd"
CLINICAL_LOG_DATA_SCRIPT_PATH = "res://System/Book/Book/ClinicalLogData.gd"
HERB_DATA_SCRIPT_PATH = "res://System/Herb/HerbData.gd"
DISEASE_DATA_SCRIPT_PATH = "res://System/Disease/DiseaseData.gd"
FORMULA_DATA_SCRIPT_PATH = "res://System/Formula/FormulaData.gd"
FORMULA_INGREDIENT_SCRIPT_PATH = "res://System/Formula/FormulaIngredient.gd"
STORY_DATA_SCRIPT_PATH = "res://System/Story/StoryData.gd"
STORY_LINE_SCRIPT_PATH = "res://System/Story/StoryLine.gd"
NPC_DATA_SCRIPT_PATH = "res://System/Npc/NpcData.gd"

HERB_BOOK_ENTRY_SCRIPT_PATH = "res://System/Book/BookEntry/HerbBookEntryData.gd"
DISEASE_BOOK_ENTRY_SCRIPT_PATH = "res://System/Book/BookEntry/DiseaseBookEntryData.gd"
FORMULA_BOOK_ENTRY_SCRIPT_PATH = "res://System/Book/BookEntry/FormulaBookEntryData.gd"
THEORY_BOOK_ENTRY_SCRIPT_PATH = "res://System/Book/BookEntry/TheoryBookEntryData.gd"


SHEET_BOOK = "Book"
SHEET_HERB = "Herb"
SHEET_DISEASE = "Disease"
SHEET_PULSE = "Pulse"
SHEET_FORMULA = "Formula"
SHEET_FORMULA_INGREDIENT = "FormulaIngredient"
SHEET_THEORY = "Theory"
SHEET_NPC = "Npc"
SHEET_NPC_ALIASES = ["Npc", "NPC", "npc"]
SHEET_STORY = "Story"
SHEET_STORY_ALIASES = ["Story", "Stroy", "story", "stroy"]
SHEET_STORY_LINE = "StoryLine"
SHEET_STORY_LINE_ALIASES = ["StoryLine", "storyline"]

# 独立剧情工作簿的标准列。
# 新模板把剧情触发条件放在 Story sheet，把逐句台词放在 StoryLine sheet；
# StoryLine 不再重复填写 StoryID / StoryName，由同文件的 Story 行自动继承。
STORY_IMPORT_HEADERS = [
    "StoryID",
    "StoryName",
    "TriggerType",
    "TriggerScene",
    "TriggerDay",
    "Reputation",
    "EntryId",
    "NpcID",
    "TriggerNpcID",
    "ClinicNpcPortraitPath",
    "PlayOnce",
    "ReturnScene",
    "SortIndex",
]
STORY_LINE_CONTENT_HEADERS = [
    "LineIndex",
    "LineType",
    "Speaker",
    "PortraitSide",
    "PortraitPath",
    "Hide",
    "BackgroundPath",
    "Text",
]
STORY_LINE_IMPORT_HEADERS = ["StoryID", "StoryName", *STORY_LINE_CONTENT_HEADERS]

# 只在剧情 xlsx -> Data.xlsx 的内存数据中使用，不会写入 Excel 或 .tres。
# 用于携带来源单元格的格式及来源行高。
STORY_CELL_STYLES_KEY = "__story_cell_styles__"
STORY_ROW_HEIGHT_KEY = "__story_row_height__"

# StoryLine 立绘根目录。
STORY_PORTRAIT_BASE_DIR = "res://Assets/Portrait/StoryNpc"

# 说话人显示名与立绘目录名不一致时，在这里集中配置。
# 同时兼容“李东璧”和现有表格中的“李东壁”写法。
STORY_SPEAKER_NPC_ID_OVERRIDES = {
    "李东璧": "li_dong_bi",
    "李东壁": "li_dong_bi",
}


# 三类正文导入配置：文件夹名、sheet 名、匹配名称列、目标正文列
DETAIL_TEXT_IMPORT_CONFIGS = [
    {"folder_name": "药材", "sheet_name": "Herb", "name_column": "HerbName", "detail_column": "DetailText"},
    {"folder_name": "疾病", "sheet_name": "Disease", "name_column": "DiseaseName", "detail_column": "DetailText"},
    {"folder_name": "方剂", "sheet_name": "Formula", "name_column": "FormulaName", "detail_column": "DetailText"},
    {"folder_name": "说明", "sheet_name": "Theory", "name_column": "TheoryName", "detail_column": "DetailText"},
]



def decode_hash_unicode_name(text: str) -> str:
    """
    功能：兼容 zip 解压后出现的 #U4e2d#U6587 形式路径名。
    作用：让 DetailText 文件夹和 txt 文件名无论是中文原名，还是 #U 编码名，都能参与匹配。
    """
    import re

    def repl(match) -> str:
        return chr(int(match.group(1), 16))

    return re.sub(r"#U([0-9a-fA-F]{4})", repl, text)


def find_detail_text_subdir(root_dir: Path, folder_name: str) -> Path | None:
    """
    功能：查找 DetailText 子目录。
    规则：优先精确匹配中文目录名；若不存在，则兼容 #U 编码目录名。
    """
    direct_path = root_dir / folder_name
    if direct_path.exists():
        return direct_path

    if not root_dir.exists():
        return None

    for path in root_dir.iterdir():
        if path.is_dir() and decode_hash_unicode_name(path.name) == folder_name:
            return path

    return None

def normalize_detail_text(text: str) -> str:
    """
    功能：清洗 DetailText txt 正文。
    作用：去掉 BOM，统一换行符，并去掉首尾空白。
    """
    text = text.replace("\ufeff", "")
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    return text.strip()


def load_detail_text_txt_map(source_dir: Path) -> dict[str, str]:
    """
    功能：读取某个 DetailText 子目录下的所有 .txt 文件。
    返回：文件名（不带 .txt） -> 文件正文。
    """
    if not source_dir.exists():
        log(f"跳过 DetailText 导入：找不到目录 {source_dir}")
        return {}

    txt_files = sorted(source_dir.glob("*.txt"))
    if not txt_files:
        log(f"跳过 DetailText 导入：目录下没有 .txt 文件 {source_dir}")
        return {}

    txt_map: dict[str, str] = {}
    for txt_path in txt_files:
        item_name = decode_hash_unicode_name(txt_path.stem).strip()
        if not item_name:
            log(f"跳过空文件名：{txt_path.name}")
            continue
        txt_map[item_name] = normalize_detail_text(txt_path.read_text(encoding="utf-8"))
    return txt_map



def _capture_cell_style(cell) -> dict[str, Any]:
    """
    保存单元格的可移植样式。

    不直接保存 cell._style：不同工作簿的样式索引表并不相同，直接跨工作簿
    赋值可能出现字体、边框或填充错乱。分别复制各样式对象时，openpyxl 会在
    目标工作簿中正确注册它们。
    """
    return {
        "font": copy(cell.font),
        "fill": copy(cell.fill),
        "border": copy(cell.border),
        "alignment": copy(cell.alignment),
        "protection": copy(cell.protection),
        "number_format": cell.number_format,
    }


def _apply_cell_style(cell, style_data: dict[str, Any] | None) -> None:
    """把来源工作簿的单元格样式安全复制到目标单元格。"""
    if not style_data:
        return

    cell.font = copy(style_data["font"])
    cell.fill = copy(style_data["fill"])
    cell.border = copy(style_data["border"])
    cell.alignment = copy(style_data["alignment"])
    cell.protection = copy(style_data["protection"])
    cell.number_format = style_data["number_format"]


def _read_story_sheet_rows(ws, required_headers: list[str], source_name: str) -> list[dict[str, Any]]:
    """读取剧情工作簿中的一个 sheet，同时保留单元格样式和行高。"""
    sheet_rows = list(ws.iter_rows())
    if not sheet_rows:
        return []

    headers = [as_str(cell.value) for cell in sheet_rows[0]]
    missing = [name for name in required_headers if name not in headers]
    if missing:
        raise ValueError(f"剧情文件 {source_name} 的 {ws.title} sheet 缺少列：{missing}")

    rows: list[dict[str, Any]] = []
    for source_row_index, raw_row in enumerate(sheet_rows[1:], start=2):
        row: dict[str, Any] = {}
        cell_styles: dict[str, dict[str, Any]] = {}
        all_empty = True
        for i, cell in enumerate(raw_row):
            key = headers[i] if i < len(headers) else ""
            if not key:
                continue
            clean_value = normalize_cell(cell.value)
            row[key] = clean_value
            cell_styles[key] = _capture_cell_style(cell)
            if clean_value != "":
                all_empty = False

        if not all_empty:
            row[STORY_CELL_STYLES_KEY] = cell_styles
            row[STORY_ROW_HEIGHT_KEY] = ws.row_dimensions[source_row_index].height
            rows.append(row)

    return rows


def _is_story_template_file(path: Path) -> bool:
    """模板可以长期保留在剧情目录，但不会被当成正式剧情导入。"""
    decoded_stem = decode_hash_unicode_name(path.stem)
    return "模板" in decoded_stem or "模版" in decoded_stem


def _has_story_line_content(row: dict[str, Any]) -> bool:
    """只预填了 LineIndex 的占位行不导入；有台词或演出设置的行会保留。"""
    return any(as_str(row.get(header)) for header in STORY_LINE_CONTENT_HEADERS if header != "LineIndex")


def load_story_xlsx_data(source_dir: Path) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    """
    读取 DetailText/剧情 下的正式剧情工作簿。

    新格式：
    - Story sheet：一行剧情元数据。
    - StoryLine sheet：只填台词列，StoryID / StoryName 自动继承 Story 行。

    兼容旧格式：
    - 单个活动 sheet 同时含 StoryID、StoryName 和台词列。
    - 旧格式只更新 StoryLine，不覆盖 Data.xlsx 中已有的 Story 元数据。
    """
    if not source_dir.exists():
        log(f"跳过剧情导入：找不到目录 {source_dir}")
        return [], []

    xlsx_files = sorted(
        path
        for path in source_dir.glob("*.xlsx")
        if not path.name.startswith("~$") and not _is_story_template_file(path)
    )
    if not xlsx_files:
        log(f"跳过剧情导入：目录下没有 .xlsx 文件 {source_dir}")
        return [], []

    story_rows: list[dict[str, Any]] = []
    story_line_rows: list[dict[str, Any]] = []
    story_sources: dict[str, str] = {}
    line_sources: dict[tuple[str, int], str] = {}

    for xlsx_path in xlsx_files:
        wb = load_workbook(xlsx_path, data_only=True)
        source_name = decode_hash_unicode_name(xlsx_path.name)
        story_sheet_name = resolve_sheet_name(wb, SHEET_STORY, SHEET_STORY_ALIASES)
        line_sheet_name = resolve_sheet_name(wb, SHEET_STORY_LINE, SHEET_STORY_LINE_ALIASES)

        # 新版双 sheet 模板。
        if story_sheet_name in wb.sheetnames and line_sheet_name in wb.sheetnames:
            imported_story_rows = _read_story_sheet_rows(
                wb[story_sheet_name],
                STORY_IMPORT_HEADERS,
                source_name,
            )
            imported_story_rows = [
                {header: row.get(header, "") for header in STORY_IMPORT_HEADERS}
                for row in imported_story_rows
                if as_str(row.get("StoryID"))
            ]

            if not imported_story_rows:
                log(f"跳过空剧情文件：{source_name}")
                continue
            if len(imported_story_rows) > 1:
                raise ValueError(
                    f"剧情文件 {source_name} 的 Story sheet 有多条正式剧情；"
                    "新版 StoryLine 不含 StoryID，因此每个文件只能填写一条 Story"
                )

            story_row = imported_story_rows[0]
            story_id = as_str(story_row.get("StoryID"))
            story_name = as_str(story_row.get("StoryName"))
            previous_source = story_sources.get(story_id)
            if previous_source:
                raise ValueError(
                    f"剧情 StoryID 重复：{story_id} 同时出现在 {previous_source} 和 {source_name}"
                )
            story_sources[story_id] = source_name
            story_rows.append(story_row)

            imported_line_rows = _read_story_sheet_rows(
                wb[line_sheet_name],
                STORY_LINE_CONTENT_HEADERS,
                source_name,
            )
            for row in imported_line_rows:
                line_index = as_int(row.get("LineIndex"), 0)
                if line_index <= 0 or not _has_story_line_content(row):
                    continue
                line_key = (story_id, line_index)
                previous_line_source = line_sources.get(line_key)
                if previous_line_source:
                    raise ValueError(
                        f"剧情行号重复：{story_id} 第 {line_index} 行同时出现在 "
                        f"{previous_line_source} 和 {source_name}"
                    )
                line_sources[line_key] = source_name
                merged_row = {
                    "StoryID": story_id,
                    "StoryName": story_name,
                    **{header: row.get(header, "") for header in STORY_LINE_CONTENT_HEADERS},
                }

                # 新版 StoryLine 不含 StoryID / StoryName 两列：
                # 目标 A/B 使用来源 LineIndex 单元格的正文样式，目标 C:J
                # 则按同名列复制来源 A:H 的样式。
                source_styles = row.get(STORY_CELL_STYLES_KEY, {})
                fallback_style = source_styles.get("LineIndex")
                merged_row[STORY_CELL_STYLES_KEY] = {
                    "StoryID": fallback_style,
                    "StoryName": fallback_style,
                    **{
                        header: source_styles.get(header)
                        for header in STORY_LINE_CONTENT_HEADERS
                    },
                }
                merged_row[STORY_ROW_HEIGHT_KEY] = row.get(STORY_ROW_HEIGHT_KEY)
                story_line_rows.append(merged_row)
            continue

        # 旧版单 sheet 模板：每行自行携带 StoryID / StoryName。
        legacy_rows = _read_story_sheet_rows(wb.active, STORY_LINE_IMPORT_HEADERS, source_name)
        for row in legacy_rows:
            story_id = as_str(row.get("StoryID"))
            line_index = as_int(row.get("LineIndex"), 0)
            if not story_id or line_index <= 0 or not _has_story_line_content(row):
                continue
            line_key = (story_id, line_index)
            previous_line_source = line_sources.get(line_key)
            if previous_line_source:
                raise ValueError(
                    f"剧情行号重复：{story_id} 第 {line_index} 行同时出现在 "
                    f"{previous_line_source} 和 {source_name}"
                )
            line_sources[line_key] = source_name
            legacy_row = {
                header: row.get(header, "")
                for header in STORY_LINE_IMPORT_HEADERS
            }
            legacy_row[STORY_CELL_STYLES_KEY] = row.get(STORY_CELL_STYLES_KEY, {})
            legacy_row[STORY_ROW_HEIGHT_KEY] = row.get(STORY_ROW_HEIGHT_KEY)
            story_line_rows.append(legacy_row)

    # Data.xlsx 中按 StoryID 连续排列；SortIndex 只作为剧情配置数据保留，
    # 不再影响表格中的物理行顺序。
    story_rows.sort(key=lambda row: as_str(row.get("StoryID")))
    story_line_rows.sort(
        key=lambda row: (as_str(row.get("StoryID")), as_int(row.get("LineIndex"), 0))
    )
    return story_rows, story_line_rows


def load_story_xlsx_rows(source_dir: Path) -> list[dict[str, Any]]:
    """兼容旧调用方：只返回合并后的 StoryLine 行。"""
    _, story_line_rows = load_story_xlsx_data(source_dir)
    return story_line_rows


def _write_rows_to_sheet(ws, rows: list[dict[str, Any]], clear_old_rows: bool) -> None:
    """按目标表头写行，同时复制来源单元格样式和行高。"""
    headers = [as_str(cell.value) for cell in ws[1]]
    if clear_old_rows and ws.max_row > 1:
        # 只清空内容，不删除行。这样可以保留模板预设的边框、底色、
        # 数据验证和行高，同时确保数据重新从第 2 行连续写入。
        for row_index in range(2, ws.max_row + 1):
            for col_index in range(1, len(headers) + 1):
                ws.cell(row=row_index, column=col_index).value = None

    start_row = 2 if clear_old_rows else ws.max_row + 1
    for row_index, row in enumerate(rows, start=start_row):
        cell_styles = row.get(STORY_CELL_STYLES_KEY, {})
        for col_index, header in enumerate(headers, start=1):
            if header:
                target_cell = ws.cell(row=row_index, column=col_index)
                target_cell.value = row.get(header, "")
                _apply_cell_style(target_cell, cell_styles.get(header))

        # None 表示来源使用默认行高；显式设回 None 可以避免目标旧行高残留。
        ws.row_dimensions[row_index].height = row.get(STORY_ROW_HEIGHT_KEY)


def _upsert_story_rows(ws, imported_rows: list[dict[str, Any]]) -> None:
    """
    按 StoryID 合并新旧剧情，再从第 2 行连续重写。

    不能用 ws.max_row + 1 追加：Excel 中只有样式的空白行也会计入 max_row，
    会造成明明第 2 行为空，数据却从第 26 行开始写入。
    """
    if not imported_rows:
        return

    headers = [as_str(cell.value) for cell in ws[1]]
    missing = [header for header in STORY_IMPORT_HEADERS if header not in headers]
    if missing:
        raise ValueError(f"Excel 的 {ws.title} sheet 缺少列：{missing}")

    story_id_col = headers.index("StoryID") + 1
    merged_row_by_id: dict[str, dict[str, Any]] = {}

    # 先收集 Data.xlsx 中已经存在的正式剧情。
    for row_index in range(2, ws.max_row + 1):
        story_id = as_str(ws.cell(row=row_index, column=story_id_col).value)
        if not story_id:
            continue
        merged_row_by_id[story_id] = {
            header: ws.cell(row=row_index, column=col_index).value
            for col_index, header in enumerate(headers, start=1)
            if header
        }

    # 同 StoryID 的新数据覆盖旧数据；新 StoryID 自动加入。
    for row in imported_rows:
        story_id = as_str(row.get("StoryID"))
        if story_id:
            merged_row_by_id[story_id] = {
                header: row.get(header, "")
                for header in headers
                if header
            }

    compact_rows = sorted(
        merged_row_by_id.values(),
        key=lambda row: as_str(row.get("StoryID")),
    )

    # 清除包括第 26 行等旧位置中的内容，但不破坏单元格格式。
    for row_index in range(2, ws.max_row + 1):
        for col_index in range(1, len(headers) + 1):
            ws.cell(row=row_index, column=col_index).value = None

    # 所有剧情统一从第 2 行连续写回。
    for row_index, row in enumerate(compact_rows, start=2):
        for col_index, header in enumerate(headers, start=1):
            if header:
                ws.cell(row=row_index, column=col_index).value = row.get(header, "")


def import_story_xlsx_to_story_sheets(wb) -> None:
    """
    把 DetailText/剧情/*.xlsx 写入 Data.xlsx：
    - Story 元数据按 StoryID 更新/追加，避免旧格式剧情丢失触发条件。
    - StoryLine 仍按剧情目录中的正式工作簿完整重建。
    """
    source_dir = find_detail_text_subdir(DETAIL_TEXT_DIR, "剧情")
    if source_dir is None:
        log(f"跳过剧情导入：找不到目录 {DETAIL_TEXT_DIR / '剧情'}")
        return

    story_sheet_name = resolve_sheet_name(wb, SHEET_STORY, SHEET_STORY_ALIASES)
    story_line_sheet_name = resolve_sheet_name(wb, SHEET_STORY_LINE, SHEET_STORY_LINE_ALIASES)
    if story_sheet_name not in wb.sheetnames:
        raise ValueError(f"Excel 中不存在 sheet：{SHEET_STORY}")
    if story_line_sheet_name not in wb.sheetnames:
        raise ValueError(f"Excel 中不存在 sheet：{SHEET_STORY_LINE}")

    story_rows, story_line_rows = load_story_xlsx_data(source_dir)
    if not story_rows and not story_line_rows:
        return

    _upsert_story_rows(wb[story_sheet_name], story_rows)
    if story_line_rows:
        _write_rows_to_sheet(wb[story_line_sheet_name], story_line_rows, clear_old_rows=True)

    log(
        "剧情 xlsx -> Data.xlsx 写入完成，"
        f"Story 更新/新增：{len(story_rows)} 条，StoryLine 导入：{len(story_line_rows)} 行"
    )


def import_story_xlsx_to_storyline_sheet(wb) -> None:
    """兼容旧调用方；实际会同时同步 Story 与 StoryLine。"""
    import_story_xlsx_to_story_sheets(wb)

def find_sheet_column_index(ws, column_name: str) -> int:
    """
    功能：在 sheet 表头中查找指定列名。
    返回：openpyxl 使用的 1-based 列索引。
    """
    header_row = next(ws.iter_rows(min_row=1, max_row=1, values_only=True))
    for index, value in enumerate(header_row, start=1):
        if value == column_name:
            return index
    raise ValueError(f"{ws.title} sheet 缺少 {column_name} 列")


def import_detail_text_for_one_sheet(wb, config: dict[str, str]) -> None:
    """
    功能：把一个分类的 txt 正文写入对应 sheet 的 DetailText 列。
    匹配规则：txt 文件名 = sheet 中的名称列。
    """
    folder_name = config["folder_name"]
    sheet_name = config["sheet_name"]
    name_column = config["name_column"]
    detail_column = config["detail_column"]

    source_dir = find_detail_text_subdir(DETAIL_TEXT_DIR, folder_name)
    if source_dir is None:
        log(f"跳过 DetailText 导入：找不到目录 {DETAIL_TEXT_DIR / folder_name}")
        return

    txt_map = load_detail_text_txt_map(source_dir)
    if not txt_map:
        return

    if sheet_name not in wb.sheetnames:
        raise ValueError(f"Excel 中不存在 sheet：{sheet_name}")

    ws = wb[sheet_name]
    name_col = find_sheet_column_index(ws, name_column)
    detail_col = find_sheet_column_index(ws, detail_column)

    matched_count = 0
    missing_txt_names: list[str] = []
    unused_txt_names = set(txt_map.keys())

    for row_index in range(2, ws.max_row + 1):
        item_name = ws.cell(row=row_index, column=name_col).value
        item_name = str(item_name).strip() if item_name is not None else ""
        if not item_name:
            continue
        if item_name in txt_map:
            ws.cell(row=row_index, column=detail_col).value = txt_map[item_name]
            matched_count += 1
            unused_txt_names.discard(item_name)
        else:
            missing_txt_names.append(item_name)

    log(f"{sheet_name} DetailText 写入完成，成功匹配：{matched_count} 条")

    if missing_txt_names:
        log(f"{sheet_name} 中以下 {name_column} 没有找到同名 txt：")
        for name in missing_txt_names:
            print(f" - {name}")

    if unused_txt_names:
        log(f"{folder_name} 文件夹中以下 txt 没有匹配到 {sheet_name}：")
        for name in sorted(unused_txt_names):
            print(f" - {name}")


def import_detail_text_txt_to_excel() -> None:
    """
    功能：正式导出 .tres 前，先把 DetailText 目录中的 txt 正文写入 Data.xlsx。
    范围：药材、疾病、方剂、说明、剧情。
    """
    if not DETAIL_TEXT_DIR.exists():
        log(f"未找到 DetailText 目录，跳过 txt 正文导入：{DETAIL_TEXT_DIR}")
        return

    copy2(EXCEL_PATH, DETAIL_TEXT_BACKUP_PATH)
    log(f"已备份 Data.xlsx：{DETAIL_TEXT_BACKUP_PATH.name}")

    wb = load_workbook(EXCEL_PATH)
    for config in DETAIL_TEXT_IMPORT_CONFIGS:
        import_detail_text_for_one_sheet(wb, config)

    import_story_xlsx_to_story_sheets(wb)

    wb.save(EXCEL_PATH)
    log("DetailText txt -> Data.xlsx 导入完成")


def log(msg: str) -> None:
    """
    功能：统一输出脚本运行日志。
    作用：
    1. 方便在控制台快速定位导入流程执行到哪一步。
    2. 出现报错或数据异常时，便于排查问题。
    """
    print(f"[import_data] {msg}")


def ensure_dir(path: Path) -> None:
    """
    功能：确保目标目录存在。
    作用：
    1. 在写入文件前自动创建缺失目录。
    2. 避免因为目录不存在导致写文件失败。
    """
    path.mkdir(parents=True, exist_ok=True)


def write_text_file(path: Path, content: str) -> None:
    """
    功能：以 UTF-8 编码写入文本文件。
    作用：
    1. 统一项目内所有 .tres 文件的输出方式。
    2. 写入前自动确保父目录存在。
    """
    ensure_dir(path.parent)
    path.write_text(content, encoding="utf-8")


def normalize_cell(value: Any) -> Any:
    """
    统一清洗 Excel 单元格值。
    None -> ""
    str -> 去掉首尾空格
    """
    if value is None:
        return ""
    if isinstance(value, str):
        return value.strip()
    return value


def as_str(value: Any) -> str:
    """
    功能：将输入值安全转换为字符串。
    作用：
    1. 避免 None 参与字符串拼接时报错。
    2. 统一去除首尾空格，减少 Excel 输入不规范影响。
    """
    if value is None:
        return ""
    return str(value).strip()


def normalize_inactive_portrait_mode(value: Any) -> str:
    """
    功能：把 StoryLine 的 Hide 列转换为本句结束后的立绘状态。
    规则：
    1. 支持 hide / dim / normal，忽略大小写和首尾空格。
    2. Hide 留空或填写未知值时返回 dim，兼容旧剧情。
    """
    mode = as_str(value).lower()
    if mode in ("hide", "dim", "normal"):
        return mode
    return "dim"


def get_first_value(row: dict[str, Any], column_names: list[str]) -> Any:
    """
    功能：按多个候选列名读取同一个字段。
    作用：兼容 Excel 表头中带空格或不带空格的写法，例如 Portrait Before / PortraitBefore。
    """
    for column_name in column_names:
        if column_name in row:
            value = row.get(column_name)
            if as_str(value):
                return value
    return ""


def normalize_npc_type(value: Any) -> str:
    """
    功能：统一 NPC 类型文本。
    作用：支持 random / story，也兼容中文策划填写。
    """
    text = as_str(value).lower()
    mapping = {
        "random": "random",
        "随机": "random",
        "story": "story",
        "剧情": "story",
    }
    return mapping.get(text, text)


def is_valid_resource_path(path_text: Any) -> bool:
    """
    功能：检查导出到 .tres 的资源路径是否是 Godot res:// 路径。
    注意：这里只校验路径格式，不检查文件是否真实存在。
    """
    text = as_str(path_text)
    return not text or text.startswith("res://")


def get_npc_portrait_base_dir(npc_type: str) -> str:
    """
    功能：根据 NPC 类型返回立绘所在目录。
    random -> res://Assets/Portrait/RandomNpc
    story  -> res://Assets/Portrait/StoryNpc
    """
    if npc_type == "story":
        return "res://Assets/Portrait/StoryNpc"
    return "res://Assets/Portrait/RandomNpc"


def get_npc_portrait_before_path(npc_id: str, npc_type: str) -> str:
    """
    功能：根据 NpcID 和 NpcType 自动生成治疗前立绘路径。
    random -> res://Assets/Portrait/RandomNpc/{NpcID}_before.png
    story  -> res://Assets/Portrait/StoryNpc/{NpcID}/{NpcID}_before.png
    """
    base_dir = get_npc_portrait_base_dir(npc_type)
    if npc_type == "story":
        return f"{base_dir}/{npc_id}/{npc_id}_before.png"
    return f"{base_dir}/{npc_id}_before.png"


def get_npc_portrait_after_path(npc_id: str, npc_type: str) -> str:
    """
    功能：根据 NpcID 和 NpcType 自动生成治疗后立绘路径。
    random -> res://Assets/Portrait/RandomNpc/{NpcID}_after.png
    story  -> res://Assets/Portrait/StoryNpc/{NpcID}/{NpcID}_after.png
    """
    base_dir = get_npc_portrait_base_dir(npc_type)
    if npc_type == "story":
        return f"{base_dir}/{npc_id}/{npc_id}_after.png"
    return f"{base_dir}/{npc_id}_after.png"


def get_story_npc_id_from_portrait_path(path_text: Any) -> str:
    """
    功能：从完整 StoryNpc 立绘路径中提取角色目录名。
    示例：
    res://Assets/Portrait/StoryNpc/li_dong_bi/li_dong_bi_sad.png
    -> li_dong_bi
    """
    clean_path = as_str(path_text)
    path_prefix = f"{STORY_PORTRAIT_BASE_DIR}/"
    if not clean_path.startswith(path_prefix):
        return ""

    relative_path = clean_path[len(path_prefix):]
    return relative_path.split("/", 1)[0].strip()


def build_story_speaker_npc_id_map(
    npc_map: dict[str, dict[str, Any]],
    story_line_map: dict[str, list[dict[str, Any]]],
) -> dict[str, str]:
    """
    功能：建立 StoryLine Speaker -> 立绘目录名映射。
    优先级：
    1. Npc sheet 中 NpcType=story 的 NpcName / NpcID。
    2. StoryLine 已填写的完整 StoryNpc PortraitPath。
    3. STORY_SPEAKER_NPC_ID_OVERRIDES 中的显式覆盖。
    """
    result: dict[str, str] = {}

    for npc_id, row in npc_map.items():
        if normalize_npc_type(row.get("NpcType")) != "story":
            continue

        npc_name = as_str(row.get("NpcName"))
        if npc_name:
            result[npc_name] = npc_id
        result[npc_id] = npc_id

    # 现有完整路径反映实际立绘目录，可兼容 NpcID 与立绘目录名不同的角色。
    for rows in story_line_map.values():
        for row in rows:
            speaker = as_str(row.get("Speaker"))
            portrait_npc_id = get_story_npc_id_from_portrait_path(row.get("PortraitPath"))
            if speaker and portrait_npc_id:
                result[speaker] = portrait_npc_id

    # 显式覆盖最后应用，确保角色别名始终指向预期目录。
    result.update(STORY_SPEAKER_NPC_ID_OVERRIDES)
    return result


def resolve_story_portrait_path(
    portrait_path_value: Any,
    speaker: Any,
    speaker_npc_id_map: dict[str, str],
) -> str:
    """
    功能：把 StoryLine.PortraitPath 转换成完整 Godot 资源路径。
    规则：
    1. 已填写 res:// 完整路径时原样保留。
    2. 留空时使用角色默认立绘：{NpcID}.png。
    3. 填写 smail / sad 等表情名时使用：{NpcID}_{表情名}.png。
    4. subtitle 没有 Speaker 且 PortraitPath 为空时，不写入立绘。
    """
    clean_value = as_str(portrait_path_value)
    if clean_value.startswith("res://"):
        return clean_value

    speaker_name = as_str(speaker)
    if not speaker_name:
        return ""

    npc_id = as_str(speaker_npc_id_map.get(speaker_name))
    if not npc_id:
        return ""

    portrait_base = f"{STORY_PORTRAIT_BASE_DIR}/{npc_id}/{npc_id}"
    if not clean_value:
        return f"{portrait_base}.png"

    variant = clean_value.strip().strip("_")
    if variant.lower().endswith(".png"):
        variant = variant[:-4].rstrip("_")
    if not variant:
        return f"{portrait_base}.png"
    return f"{portrait_base}_{variant}.png"


def as_float(value: Any, default: float = 0.0) -> float:
    """
    功能：将输入值安全转换为浮点数。
    作用：
    1. 用于读取 Excel 中的数值列。
    2. 转换失败时返回默认值，避免脚本中断。
    """
    if value in ("", None):
        return default
    try:
        return float(value)
    except Exception:
        return default


def as_int(value: Any, default: int = 0) -> int:
    """
    功能：将输入值安全转换为整数。
    作用：
    1. 用于排序、索引等必须为整数的字段。
    2. 兼容 Excel 中可能出现的 1.0 这类数值。
    """
    if value in ("", None):
        return default
    try:
        return int(float(value))
    except Exception:
        return default


def get_unlock_required_experience_points(row: dict[str, Any]) -> int:
    """
    功能：读取医书条目自动解锁所需累计心得。
    作用：
    1. 只从 Experience 列读取数值。
    2. 空值默认 -1，表示不参与心得自动解锁。
    3. 不再兼容 Thoughts 或更早的旧列名，避免表头混用。
    """
    return as_int(row.get("Experience"), -1)


def as_bool(value: Any, default: bool = True) -> bool:
    """
    功能：将 Excel 单元格内容转换为布尔值。
    作用：
    1. 支持 true/false、1/0、yes/no、是/否 等常见写法。
    2. 保证导入配置字段时结果统一为 Python bool。
    """
    text = as_str(value).lower()
    if text in ("true", "1", "yes", "y", "是"):
        return True
    if text in ("false", "0", "no", "n", "否"):
        return False
    return default


def split_multi_value(value: Any, sep: str = "|") -> list[str]:
    """
    功能：按指定分隔符拆分 Excel 中的多值字段。
    作用：
    1. 将形如 A|B|C 的单元格内容转成列表。
    2. 常用于 ID 列表、标签列表、多选字段等。
    """
    text = as_str(value)
    if not text:
        return []
    return [part.strip() for part in text.split(sep) if part and part.strip()]


def unique_keep_order(values: list[str]) -> list[str]:
    """
    功能：对字符串列表去重，并保留原有顺序。
    作用：
    1. 避免重复 ID 写入资源文件。
    2. 保留策划表中原始配置顺序，避免逻辑顺序被打乱。
    """
    seen: set[str] = set()
    result: list[str] = []
    for value in values:
        text = as_str(value)
        if not text or text in seen:
            continue
        seen.add(text)
        result.append(text)
    return result


def format_godot_string(value: Any) -> str:
    """
    功能：将普通字符串格式化为 Godot .tres 可用的字符串字面量。
    作用：
    1. 处理反斜杠、双引号、换行等特殊字符。
    2. 避免生成的 .tres 文件语法错误。
    """
    text = as_str(value)
    text = text.replace("\\", "\\\\")
    text = text.replace('"', '\\"')
    text = text.replace("\n", "\\n")
    return f'"{text}"'


def format_godot_string_array(values: list[str]) -> str:
    """
    功能：将 Python 字符串列表转换为 Godot 的 Array[String] 文本。
    作用：
    1. 用于写入 .tres 中的字符串数组字段。
    2. 保证导出的数组格式符合 Godot 资源规范。
    """
    parts = ", ".join(format_godot_string(v) for v in values)
    return f"Array[String]([{parts}])"


def safe_filename(name: str) -> str:
    """
    功能：生成可用于文件输出的安全文件名。
    作用：
    1. 防止空 ID 导致输出文件名非法。
    2. 在导出资源时强制要求关键标识存在。
    """
    text = as_str(name)
    if not text:
        raise ValueError("文件名为空，请检查 ID 字段")
    return text


def normalize_unit(unit_text: Any) -> str:
    """
    将单位统一转成项目内使用值。
    支持：fen / qian / liang / jin
    """
    text = as_str(unit_text).lower()
    mapping = {
        "fen": "fen",
        "分": "fen",
        "qian": "qian",
        "钱": "qian",
        "liang": "liang",
        "两": "liang",
        "jin": "jin",
        "斤": "jin",
    }
    return mapping.get(text, text)


def normalize_book_type(book_type_text: Any) -> str:
    """
    功能：统一书籍类型字段的文本格式。
    作用：
    1. 兼容 Excel 中不同写法。
    2. 保证后续逻辑判断只使用项目内部标准值。
    """
    text = as_str(book_type_text).lower()
    mapping = {
        "herb": "herb",
        "disease": "disease",
        "formula": "formula",
        "clinical_log": "clinical_log",
        "clinicallog": "clinical_log",
        "clinical-log": "clinical_log",
        "theory": "theory",
        "理论": "theory",
    }
    return mapping.get(text, text)



def resolve_sheet_name(wb, preferred_name: str, aliases: list[str] | None = None) -> str:
    """
    功能：兼容 Story / Stroy、StoryLine / storyline 等大小写或拼写差异。
    返回实际存在的 sheet 名。
    """
    names = aliases or [preferred_name]
    for name in names:
        if name in wb.sheetnames:
            return name
    lower_map = {name.lower(): name for name in wb.sheetnames}
    for name in names:
        found = lower_map.get(name.lower())
        if found:
            return found
    return preferred_name

def build_row_dicts(ws) -> list[dict[str, Any]]:
    """
    功能：将一个 Excel sheet 读取为字典列表。
    作用：
    1. 第一行作为字段名，后续每一行转为一条字典数据。
    2. 自动跳过空行，便于后续统一处理。
    """
    rows = list(ws.iter_rows(values_only=True))
    if not rows:
        return []

    headers = [as_str(cell) for cell in rows[0]]
    result: list[dict[str, Any]] = []

    for row in rows[1:]:
        if row is None:
            continue

        row_dict: dict[str, Any] = {}
        all_empty = True

        for i, value in enumerate(row):
            key = headers[i] if i < len(headers) else ""
            if not key:
                continue

            clean_value = normalize_cell(value)
            row_dict[key] = clean_value

            if clean_value != "":
                all_empty = False

        if not all_empty:
            result.append(row_dict)

    return result


def load_excel_data(excel_path: Path) -> dict[str, list[dict[str, Any]]]:
    """
    功能：读取 Excel 文件中的核心数据表。
    作用：
    1. 校验必需的 6 个 sheet 是否存在。
    2. 将每个 sheet 转为统一的字典列表结构返回。
    """
    if not excel_path.exists():
        raise FileNotFoundError(f"找不到 Excel 文件：{excel_path}")

    wb = load_workbook(excel_path, data_only=True)

    npc_sheet_name = resolve_sheet_name(wb, SHEET_NPC, SHEET_NPC_ALIASES)
    story_sheet_name = resolve_sheet_name(wb, SHEET_STORY, SHEET_STORY_ALIASES)
    story_line_sheet_name = resolve_sheet_name(wb, SHEET_STORY_LINE, SHEET_STORY_LINE_ALIASES)

    # 必须存在的工作表，缺一不可
    required_sheets = [
        SHEET_BOOK,
        SHEET_HERB,
        SHEET_DISEASE,
        SHEET_PULSE,
        SHEET_FORMULA,
        SHEET_FORMULA_INGREDIENT,
        SHEET_THEORY,
        npc_sheet_name,
        story_sheet_name,
        story_line_sheet_name,
    ]

    missing = [name for name in required_sheets if name not in wb.sheetnames]
    if missing:
        raise ValueError(f"Data.xlsx 缺少 sheet：{missing}；当前需要：{required_sheets}")

    return {
        SHEET_BOOK: build_row_dicts(wb[SHEET_BOOK]),
        SHEET_HERB: build_row_dicts(wb[SHEET_HERB]),
        SHEET_DISEASE: build_row_dicts(wb[SHEET_DISEASE]),
        SHEET_PULSE: build_row_dicts(wb[SHEET_PULSE]),
        SHEET_FORMULA: build_row_dicts(wb[SHEET_FORMULA]),
        SHEET_FORMULA_INGREDIENT: build_row_dicts(wb[SHEET_FORMULA_INGREDIENT]),
        SHEET_THEORY: build_row_dicts(wb[SHEET_THEORY]),
        SHEET_NPC: build_row_dicts(wb[npc_sheet_name]),
        SHEET_STORY: build_row_dicts(wb[story_sheet_name]),
        SHEET_STORY_LINE: build_row_dicts(wb[story_line_sheet_name]),
    }


def build_index(raw_data: dict[str, list[dict[str, Any]]]) -> dict[str, Any]:
    """
    功能：根据原始表数据建立各种索引映射。
    作用：
    1. 让后续查找 Book、Herb、Disease、Formula 更高效。
    2. 支持名称反查 ID，减少 Excel 重复填写。
    """
    book_map: dict[str, dict[str, Any]] = {}
    herb_map: dict[str, dict[str, Any]] = {}
    disease_map: dict[str, dict[str, Any]] = {}
    disease_name_to_id: dict[str, str] = {}
    pulse_map: dict[str, dict[str, Any]] = {}
    formula_map: dict[str, dict[str, Any]] = {}
    formula_name_to_id: dict[str, str] = {}
    formula_ingredient_map: dict[str, list[dict[str, Any]]] = {}
    theory_map: dict[str, dict[str, Any]] = {}
    npc_map: dict[str, dict[str, Any]] = {}
    story_map: dict[str, dict[str, Any]] = {}
    story_line_map: dict[str, list[dict[str, Any]]] = {}

    # 建立 BookID -> 行数据 映射
    for row in raw_data[SHEET_BOOK]:
        book_id = as_str(row.get("BookID"))
        if book_id:
            book_map[book_id] = row

    # 建立 HerbID -> 行数据 映射
    for row in raw_data[SHEET_HERB]:
        herb_id = as_str(row.get("HerbID"))
        if herb_id:
            herb_map[herb_id] = row

    # 建立 DiseaseID -> 行数据 映射，同时建立 DiseaseName -> DiseaseID 反查表
    for row in raw_data[SHEET_DISEASE]:
        disease_id = as_str(row.get("DiseaseID"))
        disease_name = as_str(row.get("DiseaseName"))
        if disease_id:
            disease_map[disease_id] = row
        if disease_name and disease_id:
            disease_name_to_id[disease_name] = disease_id

    # 脉象表优先使用 DiseaseID 关联；若未填写则尝试用 DiseaseName 反查
    for row in raw_data[SHEET_PULSE]:
        disease_id = as_str(row.get("DiseaseID"))
        disease_name = as_str(row.get("DiseaseName"))

        if not disease_id and disease_name:
            disease_id = disease_name_to_id.get(disease_name, "")

        if disease_id:
            pulse_map[disease_id] = row

    # 建立 FormulaID -> 行数据 映射，同时建立 FormulaName -> FormulaID 反查表
    for row in raw_data[SHEET_FORMULA]:
        formula_id = as_str(row.get("FormulaID"))
        formula_name = as_str(row.get("FormulaName"))
        if formula_id:
            formula_map[formula_id] = row
        if formula_name and formula_id:
            formula_name_to_id[formula_name] = formula_id

    # 建立 TheoryID -> 行数据 映射
    for row in raw_data[SHEET_THEORY]:
        theory_id = as_str(row.get("TheoryID"))
        if theory_id:
            theory_map[theory_id] = row

    # 建立 NpcID -> 行数据 映射。NPC 的 disease 不从 Excel 导入，运行时再随机分配。
    for row in raw_data[SHEET_NPC]:
        npc_id = as_str(row.get("NpcID"))
        if npc_id:
            npc_map[npc_id] = row

    # 建立 StoryID -> Story 元数据映射
    for row in raw_data.get(SHEET_STORY, []):
        story_id = as_str(row.get("StoryID"))
        if story_id:
            story_map[story_id] = row

    # 将 StoryLine 按 StoryID 分组，便于后续按剧情生成资源
    for row in raw_data.get(SHEET_STORY_LINE, []):
        story_id = as_str(row.get("StoryID"))
        if story_id:
            story_line_map.setdefault(story_id, []).append(row)

    for rows in story_line_map.values():
        rows.sort(key=lambda item: as_int(item.get("LineIndex"), 0))

    story_speaker_npc_id_map = build_story_speaker_npc_id_map(npc_map, story_line_map)

    # 将方剂组成按 FormulaID 分组，便于后续一次性生成整个方剂资源
    for row in raw_data[SHEET_FORMULA_INGREDIENT]:
        formula_id = as_str(row.get("FormulaID"))
        formula_name = as_str(row.get("FormulaName"))

        if not formula_id and formula_name:
            formula_id = formula_name_to_id.get(formula_name, "")

        if not formula_id:
            continue

        formula_ingredient_map.setdefault(formula_id, []).append(row)

    return {
        "book_map": book_map,
        "herb_map": herb_map,
        "disease_map": disease_map,
        "disease_name_to_id": disease_name_to_id,
        "pulse_map": pulse_map,
        "formula_map": formula_map,
        "formula_name_to_id": formula_name_to_id,
        "formula_ingredient_map": formula_ingredient_map,
        "theory_map": theory_map,
        "npc_map": npc_map,
        "story_map": story_map,
        "story_line_map": story_line_map,
        "story_speaker_npc_id_map": story_speaker_npc_id_map,
    }


def get_formula_target_disease_id(
    formula_row: dict[str, Any],
    disease_name_to_id: dict[str, str],
) -> str:
    """
    功能：获取方剂对应的目标疾病 ID。
    作用：
    1. 优先读取 Excel 中直接填写的 TargetDiseaseID。
    2. 若未填写，则根据疾病名称自动反查对应 ID。
    """
    target_disease_id = as_str(formula_row.get("TargetDiseaseID"))
    if target_disease_id:
        return target_disease_id

    target_disease_name = as_str(formula_row.get("TargetDiseaseName"))
    if target_disease_name:
        return as_str(disease_name_to_id.get(target_disease_name))

    return ""



def get_disease_recommended_formula_id(
    disease_row: dict[str, Any],
    formula_name_to_id: dict[str, str],
) -> str:
    """
    功能：获取疾病推荐方剂 ID。
    作用：
    1. 只读取 Disease sheet 的 RecommendedFormulaName。
    2. 用 Formula sheet 的 FormulaName 反查 FormulaID。
    3. 不再兼容 RecommendedFormulaID，也不把名称当作 ID 直接使用。
    """
    recommended_formula_name = as_str(disease_row.get("RecommendedFormulaName"))
    if not recommended_formula_name:
        return ""

    return as_str(formula_name_to_id.get(recommended_formula_name, ""))


def build_herb_detail_text(row: dict[str, Any]) -> str:
    """
    功能：读取 Herb sheet 中配置的 DetailText 原文。
    作用：
    1. 药材图鉴正文不再由脚本自动拼接。
    2. 直接使用 Excel 中填写的 DetailText 作为导出内容。
    """
    return as_str(row.get("DetailText"))

def get_formula_ingredient_required(row: dict[str, Any]) -> bool:
    """
    功能：判断某个方剂药材是否为必需药材。
    作用：
    1. 读取 FormulaIngredient 的 Required 配置。
    2. 如果策划表未填写该列，则默认按必需处理。
    """
    return as_bool(row.get("Required"), True)


def validate_data(indexed_data: dict[str, Any]) -> list[str]:
    """
    功能：校验各张表之间的引用关系是否合法。
    作用：
    1. 在真正导出资源前提前发现脏数据。
    2. 避免生成后才在游戏运行时出现引用丢失问题。
    """
    # 收集所有错误，最后一次性输出，方便策划集中修表
    errors: list[str] = []

    book_map = indexed_data["book_map"]
    herb_map = indexed_data["herb_map"]
    disease_map = indexed_data["disease_map"]
    disease_name_to_id = indexed_data["disease_name_to_id"]
    pulse_map = indexed_data["pulse_map"]
    formula_map = indexed_data["formula_map"]
    formula_name_to_id = indexed_data["formula_name_to_id"]
    formula_ingredient_map = indexed_data["formula_ingredient_map"]
    theory_map = indexed_data["theory_map"]
    npc_map = indexed_data["npc_map"]
    story_map = indexed_data["story_map"]
    story_line_map = indexed_data["story_line_map"]
    story_speaker_npc_id_map = indexed_data["story_speaker_npc_id_map"]

    for book_id, row in book_map.items():
        book_name = as_str(row.get("BookName"))
        book_type = normalize_book_type(row.get("BookType"))

        if not book_name:
            errors.append(f"Book 缺少 BookName: {book_id}")

        if book_type not in ("herb", "disease", "formula", "clinical_log", "theory"):
            errors.append(f"Book 类型非法: {book_id} -> {book_type}")

    for herb_id, row in herb_map.items():
        if not as_str(row.get("HerbName")):
            errors.append(f"Herb 缺少 HerbName: {herb_id}")

        book_id = as_str(row.get("BookID"))
        if book_id and book_id not in book_map:
            errors.append(f"Herb 引用了不存在的 BookID: {herb_id} -> {book_id}")

    for disease_id in disease_map:
        if disease_id not in pulse_map:
            errors.append(f"Disease 缺少 Pulse 数据: {disease_id}")

    for disease_id, row in disease_map.items():
        book_id = as_str(row.get("BookID"))
        if book_id and book_id not in book_map:
            errors.append(f"Disease 引用了不存在的 BookID: {disease_id} -> {book_id}")

        # Disease 表现在只使用 RecommendedFormulaName。
        # 这里用方剂名称反查 FormulaID；如果名称填了但反查失败，就提示名称不存在。
        recommended_formula_name = as_str(row.get("RecommendedFormulaName"))
        formula_id = get_disease_recommended_formula_id(row, formula_name_to_id)
        if recommended_formula_name and not formula_id:
            errors.append(f"Disease 推荐方剂名称不存在: {disease_id} -> {recommended_formula_name}")
        elif formula_id and formula_id not in formula_map:
            errors.append(f"Disease 推荐方剂不存在: {disease_id} -> {formula_id}")

    for formula_id, row in formula_map.items():
        book_id = as_str(row.get("BookID"))
        if book_id and book_id not in book_map:
            errors.append(f"Formula 引用了不存在的 BookID: {formula_id} -> {book_id}")

        target_disease_id = get_formula_target_disease_id(row, disease_name_to_id)
        if target_disease_id and target_disease_id not in disease_map:
            errors.append(f"Formula 目标疾病不存在: {formula_id} -> {target_disease_id}")

        target_disease_name = as_str(row.get("TargetDiseaseName"))
        if target_disease_name and target_disease_name not in disease_name_to_id:
            errors.append(f"Formula 目标疾病名称不存在: {formula_id} -> {target_disease_name}")

    for theory_id, row in theory_map.items():
        if not as_str(row.get("TheoryName")):
            errors.append(f"Theory 缺少 TheoryName: {theory_id}")

        book_id = as_str(row.get("BookID"))
        if book_id and book_id not in book_map:
            errors.append(f"Theory 引用了不存在的 BookID: {theory_id} -> {book_id}")

    for npc_id, row in npc_map.items():
        if not as_str(row.get("NpcName")):
            errors.append(f"Npc 缺少 NpcName: {npc_id}")

        npc_type = normalize_npc_type(row.get("NpcType")) or "random"
        if npc_type not in ("random", "story"):
            errors.append(f"Npc 类型非法: {npc_id} -> {npc_type}")

        age = as_int(row.get("Age"), -1)
        if age < 0:
            errors.append(f"Npc 年龄非法: {npc_id} -> {row.get('Age')}")

        portrait_before_path = get_npc_portrait_before_path(npc_id, npc_type)
        portrait_after_path = get_npc_portrait_after_path(npc_id, npc_type)
        if not is_valid_resource_path(portrait_before_path):
            errors.append(f"Npc 治疗前立绘路径非法: {npc_id} -> {portrait_before_path}")
        if not is_valid_resource_path(portrait_after_path):
            errors.append(f"Npc 治疗后立绘路径非法: {npc_id} -> {portrait_after_path}")

    for story_id, row in story_map.items():
        if not as_str(row.get("StoryName")):
            errors.append(f"Story 缺少 StoryName: {story_id}")
        if story_id not in story_line_map:
            errors.append(f"Story 缺少 StoryLine 数据: {story_id}")

        trigger_type = as_str(row.get("TriggerType")).lower() or "scene_enter"
        if trigger_type not in (
            "scene_enter",
            "story_npc_cured",
            "story_npc_failed_back",
            "story_npc_failed_over",
        ):
            errors.append(f"Story TriggerType 非法: {story_id} -> {trigger_type}")

        trigger_scene = as_str(row.get("TriggerScene")).lower() or "clinic"
        if trigger_scene not in ("clinic", "night", "map"):
            errors.append(f"Story TriggerScene 非法: {story_id} -> {trigger_scene}")

        return_scene = as_str(row.get("ReturnScene")).lower()
        if return_scene and return_scene not in ("clinic", "night", "map"):
            errors.append(f"Story ReturnScene 非法: {story_id} -> {return_scene}")

        clinic_npc_id = (
            as_str(row.get("NpcID"))
            or as_str(row.get("ClinicNpcID"))
            or as_str(row.get("ClinicNpcId"))
        )
        if clinic_npc_id:
            clinic_npc_row = npc_map.get(clinic_npc_id)
            if clinic_npc_row is None:
                errors.append(f"Story NpcID 不存在: {story_id} -> {clinic_npc_id}")
            elif normalize_npc_type(clinic_npc_row.get("NpcType")) != "story":
                errors.append(f"Story NpcID 不是 story NPC: {story_id} -> {clinic_npc_id}")

        clinic_npc_portrait_path = as_str(row.get("ClinicNpcPortraitPath"))
        if not is_valid_resource_path(clinic_npc_portrait_path):
            errors.append(
                f"Story ClinicNpcPortraitPath 非法: "
                f"{story_id} -> {clinic_npc_portrait_path}"
            )

        trigger_npc_id = (
            as_str(row.get("TriggerNpcID"))
            or as_str(row.get("TriggerNpcId"))
        )
        is_treatment_result_story = trigger_type in (
            "story_npc_cured",
            "story_npc_failed_back",
            "story_npc_failed_over",
        )
        if is_treatment_result_story and not trigger_npc_id:
            errors.append(f"Story 治疗结果剧情缺少 TriggerNpcID: {story_id}")
        elif trigger_npc_id:
            trigger_npc_row = npc_map.get(trigger_npc_id)
            if trigger_npc_row is None:
                errors.append(f"Story TriggerNpcID 不存在: {story_id} -> {trigger_npc_id}")
            elif normalize_npc_type(trigger_npc_row.get("NpcType")) != "story":
                errors.append(
                    f"Story TriggerNpcID 不是 story NPC: {story_id} -> {trigger_npc_id}"
                )

    for story_id, rows in story_line_map.items():
        if story_id not in story_map:
            errors.append(f"StoryLine 引用了不存在的 StoryID: {story_id}")
        for i, row in enumerate(rows, start=1):
            line_type = as_str(row.get("LineType")) or "dialogue"
            if line_type not in ("dialogue", "subtitle"):
                errors.append(f"StoryLine LineType 非法: {story_id} 第{i}行 -> {line_type}")

            portrait_side = as_str(row.get("PortraitSide")) or "auto"
            if portrait_side not in ("auto", "left", "mid", "right"):
                errors.append(f"StoryLine PortraitSide 非法: {story_id} 第{i}行 -> {portrait_side}")

            hide_value = as_str(row.get("Hide")).lower()
            if hide_value not in ("", "hide", "dim", "normal"):
                errors.append(
                    f"StoryLine Hide 非法: {story_id} 第{i}行 -> {hide_value}；"
                    "只允许留空或填写 hide、dim、normal"
                )

            background_path = as_str(row.get("BackgroundPath"))
            if not is_valid_resource_path(background_path):
                errors.append(
                    f"StoryLine BackgroundPath 非法: {story_id} 第{i}行 -> {background_path}"
                )

            speaker = as_str(row.get("Speaker"))
            portrait_path = resolve_story_portrait_path(
                row.get("PortraitPath"),
                speaker,
                story_speaker_npc_id_map,
            )
            if speaker and not portrait_path:
                errors.append(
                    f"StoryLine 无法根据 Speaker 解析立绘目录: "
                    f"{story_id} 第{i}行 -> {speaker}；"
                    "请在 Npc sheet 添加对应 story NPC，或填写完整 PortraitPath"
                )
            elif not is_valid_resource_path(portrait_path):
                errors.append(
                    f"StoryLine PortraitPath 非法: {story_id} 第{i}行 -> {portrait_path}"
                )

    for formula_id, rows in formula_ingredient_map.items():
        if formula_id not in formula_map:
            errors.append(f"FormulaIngredient 引用了不存在的 FormulaID: {formula_id}")

        for i, row in enumerate(rows, start=1):
            herb_id = as_str(row.get("HerbID"))
            if not herb_id:
                errors.append(f"FormulaIngredient 缺少 HerbID: {formula_id} 第{i}行")
                continue

            if herb_id not in herb_map:
                errors.append(f"FormulaIngredient 药材不存在: {formula_id} -> {herb_id}")

            role = as_str(row.get("Role"))
            if role not in ("君", "臣", "佐", "使"):
                errors.append(f"FormulaIngredient 角色非法: {formula_id} -> {role}")

            unit = normalize_unit(row.get("Unit"))
            if unit not in ("fen", "qian", "liang", "jin"):
                errors.append(f"FormulaIngredient 单位非法: {formula_id} -> {unit}")

            amount = as_float(row.get("Amount"), 0.0)
            if amount <= 0:
                errors.append(f"FormulaIngredient 数量非法: {formula_id} -> {herb_id} amount={amount}")

    return errors


def build_book_resources(indexed_data: dict[str, Any]) -> None:
    """
    功能：根据 Book 表数据生成 BookData 子类 .tres 资源。
    作用：
    1. 根据 BookType 导出为 HerbBookData / DiseaseBookData / FormulaBookData / ClinicalLogData。
    2. 仅写入对应子类实际需要的字段，避免所有书都落成基类 BookData。
    """
    book_map = indexed_data["book_map"]
    herb_map = indexed_data["herb_map"]
    theory_map = indexed_data["theory_map"]

    ensure_dir(BOOK_OUTPUT_DIR)

    for book_id, row in book_map.items():
        book_name = as_str(row.get("BookName"))
        book_type = normalize_book_type(row.get("BookType"))
        author_name = as_str(row.get("Author"))
        detail_text = as_str(row.get("DetailText"))
        sort_index = as_int(row.get("SortIndex"), 0)
        visible_by_default = as_bool(row.get("VisibleByDefault"), True)
        read_once = as_bool(row.get("ReadOnce"), False)
        allow_daytime_open = as_bool(row.get("AllowDaytimeOpen"), True)

        herb_unlock_order: list[str] = []
        if book_type == "herb":
            herb_unlock_order = unique_keep_order([
                herb_id
                for herb_id, herb_row in herb_map.items()
                if as_str(herb_row.get("BookID")) == book_id
            ])

        unlock_entry_ids = split_multi_value(row.get("UnlockEntryIDs"))

        script_path = BOOK_DATA_SCRIPT_PATH
        script_class = "BookData"
        extra_lines: list[str] = []

        if book_type == "herb":
            script_path = HERB_BOOK_DATA_SCRIPT_PATH
            script_class = "HerbBookData"
            extra_lines.append(
                f'herb_unlock_order = {format_godot_string_array(herb_unlock_order)}'
            )
        elif book_type == "disease":
            script_path = DISEASE_BOOK_DATA_SCRIPT_PATH
            script_class = "DiseaseBookData"
            extra_lines.append(
                f'unlock_entry_ids = {format_godot_string_array(unlock_entry_ids)}'
            )
        elif book_type == "formula":
            script_path = FORMULA_BOOK_DATA_SCRIPT_PATH
            script_class = "FormulaBookData"
            extra_lines.append(
                f'unlock_entry_ids = {format_godot_string_array(unlock_entry_ids)}'
            )
        elif book_type == "theory":
            script_path = THEORY_BOOK_DATA_SCRIPT_PATH
            script_class = "TheoryBookData"
            if not unlock_entry_ids:
                unlock_entry_ids = unique_keep_order([
                    theory_id
                    for theory_id, theory_row in theory_map.items()
                    if as_str(theory_row.get("BookID")) == book_id
                ])
            extra_lines.append(
                f'unlock_entry_ids = {format_godot_string_array(unlock_entry_ids)}'
            )
        elif book_type == "clinical_log":
            script_path = CLINICAL_LOG_DATA_SCRIPT_PATH
            script_class = "ClinicalLogData"

        content_lines = [
            f'[gd_resource type="Resource" script_class="{script_class}" load_steps=2 format=3]',
            "",
            f'[ext_resource type="Script" path="{script_path}" id="1"]',
            "",
            "[resource]",
            'script = ExtResource("1")',
            f'book_type = {format_godot_string(book_type)}',
            f'book_id = {format_godot_string(book_id)}',
            f'book_name = {format_godot_string(book_name)}',
            f'detail_text = {format_godot_string(detail_text)}',
            f'author_name = {format_godot_string(author_name)}',
            f'sort_index = {sort_index}',
            f'visible_by_default = {"true" if visible_by_default else "false"}',
            f'read_once = {"true" if read_once else "false"}',
            f'allow_daytime_open = {"true" if allow_daytime_open else "false"}',
            *extra_lines,
            "",
        ]
        content = "\n".join(content_lines)
        write_text_file(BOOK_OUTPUT_DIR / f"{safe_filename(book_id)}.tres", content)


def build_herb_resources(indexed_data: dict[str, Any]) -> None:
    """
    功能：生成药材数据资源和药材图鉴条目资源。
    作用：
    1. 输出 HerbData，供药材系统直接读取。
    2. 输出 HerbBookEntryData，供图鉴/医书系统显示。
    """
    herb_map = indexed_data["herb_map"]

    ensure_dir(HERB_OUTPUT_DIR)
    ensure_dir(HERB_BOOK_ENTRY_OUTPUT_DIR)

    for herb_id, row in herb_map.items():
        herb_name = as_str(row.get("HerbName"))
        nature = as_str(row.get("Nature"))
        taste_list = split_multi_value(row.get("Taste"))
        meridian_list = split_multi_value(row.get("Meridians"))

        herb_content = f'''[gd_resource type="Resource" script_class="HerbData" load_steps=2 format=3]

[ext_resource type="Script" path="{HERB_DATA_SCRIPT_PATH}" id="1"]

[resource]
script = ExtResource("1")
herb_id = {format_godot_string(herb_id)}
herb_name = {format_godot_string(herb_name)}
nature = {format_godot_string(nature)}
taste = {format_godot_string_array(taste_list)}
meridians = {format_godot_string_array(meridian_list)}
'''
        write_text_file(HERB_OUTPUT_DIR / f"{safe_filename(herb_id)}.tres", herb_content)

        entry_id = as_str(row.get("EntryID")) or herb_id
        title = as_str(row.get("Title")) or herb_name
        detail_text = build_herb_detail_text(row)
        unlock_required_experience_points = get_unlock_required_experience_points(row)

        entry_content = f'''[gd_resource type="Resource" script_class="HerbBookEntryData" load_steps=2 format=3]

[ext_resource type="Script" path="{HERB_BOOK_ENTRY_SCRIPT_PATH}" id="1"]

[resource]
script = ExtResource("1")
entry_id = {format_godot_string(entry_id)}
book_id = {format_godot_string(row.get("BookID"))}
title = {format_godot_string(title)}
detail_text = {format_godot_string(detail_text)}
unlock_required_experience_points = {unlock_required_experience_points}
herb_id = {format_godot_string(herb_id)}
'''
        write_text_file(HERB_BOOK_ENTRY_OUTPUT_DIR / f"{safe_filename(entry_id)}.tres", entry_content)


def build_disease_resources(indexed_data: dict[str, Any]) -> None:
    """
    功能：根据疾病表和脉象表生成疾病资源。
    作用：
    1. 输出 DiseaseData，供诊断系统读取。
    2. 输出 DiseaseBookEntryData，供图鉴和解锁逻辑使用。
    """
    disease_map = indexed_data["disease_map"]
    pulse_map = indexed_data["pulse_map"]
    formula_name_to_id = indexed_data["formula_name_to_id"]

    ensure_dir(DISEASE_OUTPUT_DIR)
    ensure_dir(DISEASE_BOOK_ENTRY_OUTPUT_DIR)

    for disease_id, disease_row in disease_map.items():
        # 获取当前疾病对应的脉象数据；若缺失则用空字典兜底
        pulse_row = pulse_map.get(disease_id, {})

        disease_name = as_str(disease_row.get("DiseaseName"))
        # 读取 Disease sheet 的 DetailText，写入 DiseaseData 资源本体。
        # 这样游戏逻辑直接加载 res://Data/Disease/*.tres 时也能拿到正文。
        detail_text = as_str(disease_row.get("DetailText"))
        # Disease 表现在填写 RecommendedFormulaName。
        # 导出 DiseaseData 时仍写入 recommended_formula_id，供游戏逻辑继续按 ID 查方剂。
        recommended_formula_id = get_disease_recommended_formula_id(disease_row, formula_name_to_id)

        disease_content = f'''[gd_resource type="Resource" script_class="DiseaseData" load_steps=2 format=3]

[ext_resource type="Script" path="{DISEASE_DATA_SCRIPT_PATH}" id="1"]

[resource]
script = ExtResource("1")
disease_id = {format_godot_string(disease_id)}
disease_name = {format_godot_string(disease_name)}
detail_text = {format_godot_string(detail_text)}
recommended_formula_id = {format_godot_string(recommended_formula_id)}
exterior_qi = {as_float(pulse_row.get("EQ"), 1.0)}
exterior_blood = {as_float(pulse_row.get("EB"), 1.0)}
exterior_cold_hot = {as_float(pulse_row.get("ET"), 1.0)}
exterior_wet_dry = {as_float(pulse_row.get("EH"), 1.0)}
heart_qi = {as_float(pulse_row.get("HQ"), 1.0)}
heart_blood = {as_float(pulse_row.get("HB"), 1.0)}
heart_cold_hot = {as_float(pulse_row.get("HT"), 1.0)}
heart_wet_dry = {as_float(pulse_row.get("HH"), 1.0)}
liver_qi = {as_float(pulse_row.get("LQ"), 1.0)}
liver_blood = {as_float(pulse_row.get("LB"), 1.0)}
liver_cold_hot = {as_float(pulse_row.get("LT"), 1.0)}
liver_wet_dry = {as_float(pulse_row.get("LH"), 1.0)}
spleen_qi = {as_float(pulse_row.get("SQ"), 1.0)}
spleen_blood = {as_float(pulse_row.get("SB"), 1.0)}
spleen_cold_hot = {as_float(pulse_row.get("ST"), 1.0)}
spleen_wet_dry = {as_float(pulse_row.get("SH"), 1.0)}
lung_qi = {as_float(pulse_row.get("PQ"), 1.0)}
lung_blood = {as_float(pulse_row.get("PB"), 1.0)}
lung_cold_hot = {as_float(pulse_row.get("PT"), 1.0)}
lung_wet_dry = {as_float(pulse_row.get("PH"), 1.0)}
kidney_yin_qi = {as_float(pulse_row.get("KYQ"), 1.0)}
kidney_yin_blood = {as_float(pulse_row.get("KYB"), 1.0)}
kidney_yin_cold_hot = {as_float(pulse_row.get("KYT"), 1.0)}
kidney_yin_wet_dry = {as_float(pulse_row.get("KYH"), 1.0)}
kidney_yang_qi = {as_float(pulse_row.get("KZQ"), 1.0)}
kidney_yang_blood = {as_float(pulse_row.get("KZB"), 1.0)}
kidney_yang_cold_hot = {as_float(pulse_row.get("KZT"), 1.0)}
kidney_yang_wet_dry = {as_float(pulse_row.get("KZH"), 1.0)}
'''
        write_text_file(DISEASE_OUTPUT_DIR / f"{safe_filename(disease_id)}.tres", disease_content)

        entry_id = as_str(disease_row.get("EntryID")) or disease_id
        title = as_str(disease_row.get("Title")) or disease_name

        entry_content = f'''[gd_resource type="Resource" script_class="DiseaseBookEntryData" load_steps=2 format=3]

[ext_resource type="Script" path="{DISEASE_BOOK_ENTRY_SCRIPT_PATH}" id="1"]

[resource]
script = ExtResource("1")
entry_id = {format_godot_string(entry_id)}
book_id = {format_godot_string(disease_row.get("BookID"))}
title = {format_godot_string(title)}
detail_text = {format_godot_string(disease_row.get("DetailText"))}
disease_id = {format_godot_string(disease_id)}
'''
        write_text_file(DISEASE_BOOK_ENTRY_OUTPUT_DIR / f"{safe_filename(entry_id)}.tres", entry_content)


def build_formula_resources(indexed_data: dict[str, Any]) -> None:
    """
    功能：根据方剂表和方剂组成表生成方剂资源。
    作用：
    1. 输出 FormulaData，供开方与抓药逻辑使用。
    2. 输出 FormulaBookEntryData，供书籍条目和图鉴系统使用。
    """
    disease_name_to_id = indexed_data["disease_name_to_id"]
    formula_map = indexed_data["formula_map"]
    formula_ingredient_map = indexed_data["formula_ingredient_map"]
    theory_map = indexed_data["theory_map"]

    ensure_dir(FORMULA_OUTPUT_DIR)
    ensure_dir(FORMULA_BOOK_ENTRY_OUTPUT_DIR)

    for formula_id, formula_row in formula_map.items():
        # 获取该方剂包含的所有药材组成行
        ingredient_rows = formula_ingredient_map.get(formula_id, [])
        formula_name = as_str(formula_row.get("FormulaName"))
        # 读取 Formula sheet 的 DetailText，写入 FormulaData 资源本体。
        # 图鉴条目 FormulaBookEntryData 仍然继续使用同一列。
        detail_text = as_str(formula_row.get("DetailText"))
        target_disease_name = as_str(formula_row.get("TargetDiseaseName"))
        target_disease_id = get_formula_target_disease_id(formula_row, disease_name_to_id)

        # 记录方剂中引用到的 Herb 资源，避免重复声明 ext_resource
        herb_ext_resources: list[tuple[str, str]] = []
        herb_ext_id_map: dict[str, str] = {}

        herb_counter = 1
        for row in ingredient_rows:
            herb_id = as_str(row.get("HerbID"))
            if herb_id and herb_id not in herb_ext_id_map:
                ext_id = f"herb_{herb_counter}"
                herb_ext_id_map[herb_id] = ext_id
                herb_path = f"res://Data/Herb/{herb_id}.tres"
                herb_ext_resources.append((ext_id, herb_path))
                herb_counter += 1

        ext_lines = [
            f'[ext_resource type="Script" path="{FORMULA_INGREDIENT_SCRIPT_PATH}" id="1"]',
            f'[ext_resource type="Script" path="{FORMULA_DATA_SCRIPT_PATH}" id="2"]',
        ]
        for ext_id, herb_path in herb_ext_resources:
            ext_lines.append(f'[ext_resource type="Resource" path="{herb_path}" id="{ext_id}"]')

        # 每味药会生成一个 sub_resource，再按君臣佐使分组
        sub_lines: list[str] = []
        jun_sub_ids: list[str] = []
        chen_sub_ids: list[str] = []
        zuo_sub_ids: list[str] = []
        shi_sub_ids: list[str] = []

        for index, row in enumerate(ingredient_rows, start=1):
            herb_id = as_str(row.get("HerbID"))
            role = as_str(row.get("Role"))
            amount = as_float(row.get("Amount"), 0.0)
            unit = normalize_unit(row.get("Unit"))
            required = get_formula_ingredient_required(row)

            if not herb_id or herb_id not in herb_ext_id_map:
                continue

            sub_id = f"Ingredient_{index}"
            herb_ext_id = herb_ext_id_map[herb_id]

            block = f'''[sub_resource type="Resource" id="{sub_id}"]
script = ExtResource("1")
herb = ExtResource("{herb_ext_id}")
amount = {amount}
unit = {format_godot_string(unit)}
required = {"true" if required else "false"}'''
            sub_lines.append(block)

            if role == "君":
                jun_sub_ids.append(sub_id)
            elif role == "臣":
                chen_sub_ids.append(sub_id)
            elif role == "佐":
                zuo_sub_ids.append(sub_id)
            elif role == "使":
                shi_sub_ids.append(sub_id)

        def format_group(sub_ids: list[str]) -> str:
            if not sub_ids:
                return "[]"
            sub_text = ", ".join(f'SubResource("{sid}")' for sid in sub_ids)
            return f"[{sub_text}]"

        formula_content_parts = [
            '[gd_resource type="Resource" script_class="FormulaData" load_steps=2 format=3]',
            "",
            *ext_lines,
            "",
            *sub_lines,
            "",
            "[resource]",
            'script = ExtResource("2")',
            f'formula_id = {format_godot_string(formula_id)}',
            f'formula_name = {format_godot_string(formula_name)}',
            f'detail_text = {format_godot_string(detail_text)}',
            f'target_disease_id = {format_godot_string(target_disease_id)}',
            f'target_disease_name = {format_godot_string(target_disease_name)}',
            f'jun_group = {format_group(jun_sub_ids)}',
            f'chen_group = {format_group(chen_sub_ids)}',
            f'zuo_group = {format_group(zuo_sub_ids)}',
            f'shi_group = {format_group(shi_sub_ids)}',
            "",
        ]
        formula_content = "\n".join(formula_content_parts)

        write_text_file(FORMULA_OUTPUT_DIR / f"{safe_filename(formula_id)}.tres", formula_content)

        entry_id = as_str(formula_row.get("EntryID")) or formula_id
        title = as_str(formula_row.get("Title")) or formula_name

        entry_content = f'''[gd_resource type="Resource" script_class="FormulaBookEntryData" load_steps=2 format=3]

[ext_resource type="Script" path="{FORMULA_BOOK_ENTRY_SCRIPT_PATH}" id="1"]

[resource]
script = ExtResource("1")
entry_id = {format_godot_string(entry_id)}
book_id = {format_godot_string(formula_row.get("BookID"))}
title = {format_godot_string(title)}
detail_text = {format_godot_string(formula_row.get("DetailText"))}
formula_id = {format_godot_string(formula_id)}
'''
        write_text_file(FORMULA_BOOK_ENTRY_OUTPUT_DIR / f"{safe_filename(entry_id)}.tres", entry_content)


def build_theory_resources(indexed_data: dict[str, Any]) -> None:
    """
    功能：根据 Theory 表生成理论书条目资源。
    作用：
    1. 将黄帝内经等基础理论内容导出为 TheoryBookEntryData。
    2. DetailText 来自 Theory sheet；运行前会先从 DetailText/说明/*.txt 自动写入。
    """
    theory_map = indexed_data["theory_map"]

    ensure_dir(THEORY_BOOK_ENTRY_OUTPUT_DIR)

    for theory_id, row in theory_map.items():
        theory_name = as_str(row.get("TheoryName"))
        entry_id = as_str(row.get("EntryID")) or theory_id
        title = as_str(row.get("Title")) or theory_name
        unlock_required_experience_points = get_unlock_required_experience_points(row)

        entry_content = f'''[gd_resource type="Resource" script_class="TheoryBookEntryData" load_steps=2 format=3]

[ext_resource type="Script" path="{THEORY_BOOK_ENTRY_SCRIPT_PATH}" id="1"]

[resource]
script = ExtResource("1")
entry_id = {format_godot_string(entry_id)}
book_id = {format_godot_string(row.get("BookID"))}
title = {format_godot_string(title)}
detail_text = {format_godot_string(row.get("DetailText"))}
unlock_required_experience_points = {unlock_required_experience_points}
'''
        write_text_file(THEORY_BOOK_ENTRY_OUTPUT_DIR / f"{safe_filename(entry_id)}.tres", entry_content)



def format_ext_resource_value(ext_id: str) -> str:
    return f'ExtResource("{ext_id}")'


def build_story_resources(indexed_data: dict[str, Any]) -> None:
    """
    功能：根据 Story / StoryLine 表生成剧情 .tres。
    输出：res://Data/Story/{StoryID}.tres
    """
    story_map = indexed_data["story_map"]
    story_line_map = indexed_data["story_line_map"]
    story_speaker_npc_id_map = indexed_data["story_speaker_npc_id_map"]

    ensure_dir(STORY_OUTPUT_DIR)

    for story_id, story_row in story_map.items():
        story_lines = story_line_map.get(story_id, [])
        story_name = as_str(story_row.get("StoryName"))
        trigger_type = as_str(story_row.get("TriggerType")).lower() or "scene_enter"
        trigger_scene = as_str(story_row.get("TriggerScene")).lower() or "clinic"
        trigger_npc_id = (
            as_str(story_row.get("TriggerNpcID"))
            or as_str(story_row.get("TriggerNpcId"))
        )
        trigger_day = as_int(story_row.get("TriggerDay"), 0)
        required_reputation_points = as_int(story_row.get("Reputation"), 0)
        unlock_entry_id = as_str(story_row.get("EntryId"))
        play_once = as_bool(story_row.get("PlayOnce"), True)
        return_scene = as_str(story_row.get("ReturnScene")).lower() or trigger_scene
        clinic_npc_id = (
            as_str(story_row.get("ClinicNpcID"))
            or as_str(story_row.get("ClinicNpcId"))
            or as_str(story_row.get("NpcID"))
        )
        clinic_npc_portrait_path = as_str(
            story_row.get("ClinicNpcPortraitPath")
        )

        ext_lines = [
            f'[ext_resource type="Script" path="{STORY_LINE_SCRIPT_PATH}" id="1_storyline"]',
            f'[ext_resource type="Script" path="{STORY_DATA_SCRIPT_PATH}" id="2_storydata"]',
        ]

        resource_path_to_id: dict[str, str] = {}
        next_ext_index = 1

        def add_texture_resource(path_text: str, prefix: str) -> str:
            nonlocal next_ext_index
            clean_path = as_str(path_text)
            if not clean_path:
                return ""
            if clean_path in resource_path_to_id:
                return resource_path_to_id[clean_path]
            ext_id = f"{prefix}_{next_ext_index}"
            next_ext_index += 1
            resource_path_to_id[clean_path] = ext_id
            ext_lines.append(f'[ext_resource type="Texture2D" path="{clean_path}" id="{ext_id}"]')
            return ext_id

        clinic_npc_portrait_ext_id = add_texture_resource(
            clinic_npc_portrait_path,
            "clinic_npc_portrait",
        )

        sub_lines: list[str] = []
        sub_ids: list[str] = []
        for index, line_row in enumerate(story_lines, start=1):
            line_index = as_int(line_row.get("LineIndex"), index)
            sub_id = f"StoryLine_{line_index:03d}"
            sub_ids.append(sub_id)

            line_type = as_str(line_row.get("LineType")) or "dialogue"
            speaker = as_str(line_row.get("Speaker"))
            text = as_str(line_row.get("Text"))
            portrait_path = resolve_story_portrait_path(
                line_row.get("PortraitPath"),
                speaker,
                story_speaker_npc_id_map,
            )
            portrait_ext_id = add_texture_resource(portrait_path, "portrait")
            background_ext_id = add_texture_resource(
                as_str(line_row.get("BackgroundPath")),
                "background",
            )

            portrait_side = as_str(line_row.get("PortraitSide")) or "auto"
            inactive_portrait_mode = normalize_inactive_portrait_mode(line_row.get("Hide"))

            block_lines = [
                f'[sub_resource type="Resource" id="{sub_id}"]',
                'script = ExtResource("1_storyline")',
                f'line_type = {format_godot_string(line_type)}',
                f'portrait_side = {format_godot_string(portrait_side)}',
                f'inactive_portrait_mode = {format_godot_string(inactive_portrait_mode)}',
            ]
            if speaker:
                block_lines.append(f'speaker = {format_godot_string(speaker)}')
            block_lines.append(f'text = {format_godot_string(text)}')
            if portrait_ext_id:
                block_lines.append(f'portrait = {format_ext_resource_value(portrait_ext_id)}')
            if background_ext_id:
                block_lines.append(f'background = {format_ext_resource_value(background_ext_id)}')
            sub_lines.append("\n".join(block_lines))

        line_array = ", ".join(f'SubResource("{sub_id}")' for sub_id in sub_ids)

        resource_lines = [
            "[resource]",
            'script = ExtResource("2_storydata")',
            f'story_id = {format_godot_string(story_id)}',
            f'trigger_type = {format_godot_string(trigger_type)}',
            f'trigger_scene = {format_godot_string(trigger_scene)}',
            f'trigger_npc_id = {format_godot_string(trigger_npc_id)}',
            f'trigger_day = {trigger_day}',
            f'required_reputation_points = {required_reputation_points}',
            f'unlock_entry_id = {format_godot_string(unlock_entry_id)}',
            f'play_once = {"true" if play_once else "false"}',
            f'return_scene = {format_godot_string(return_scene)}',
            f'clinic_npc_id = {format_godot_string(clinic_npc_id)}',
        ]
        if clinic_npc_portrait_ext_id:
            resource_lines.append(
                f'clinic_npc_portrait = '
                f'{format_ext_resource_value(clinic_npc_portrait_ext_id)}'
            )
        resource_lines.append(f'lines = Array[ExtResource("1_storyline")]([{line_array}])')

        story_content_parts = [
            '[gd_resource type="Resource" script_class="StoryData" format=3]',
            "",
            *ext_lines,
            "",
            *sub_lines,
            "",
            *resource_lines,
            "",
        ]
        write_text_file(STORY_OUTPUT_DIR / f"{safe_filename(story_id)}.tres", "\n".join(story_content_parts))


def build_npc_resources(indexed_data: dict[str, Any]) -> None:
    """
    功能：根据 Npc 表生成 NPC 基础资源。
    输出：res://Data/Npc/{NpcID}.tres
    说明：NPC 的 disease 不从 Excel 写入，由运行时从已解锁疾病中随机分配。
    """
    npc_map = indexed_data["npc_map"]

    ensure_dir(NPC_OUTPUT_DIR)

    for npc_id, row in npc_map.items():
        npc_name = as_str(row.get("NpcName"))
        npc_type = normalize_npc_type(row.get("NpcType")) or "random"
        gender = as_str(row.get("Gender"))
        age = as_int(row.get("Age"), 0)
        dialogue_prefix = as_str(row.get("DialoguePrefix"))
        dialogue_suffix = as_str(row.get("DialogueSuffix"))
        dialogue_after_treatment = as_str(row.get("DialogueAfterTreatment"))
        dialogue_treatment_failed = as_str(row.get("dialogueTreatmentFailed"))
        portrait_before_path = get_npc_portrait_before_path(npc_id, npc_type)
        portrait_after_path = get_npc_portrait_after_path(npc_id, npc_type)

        ext_lines = [
            f'[ext_resource type="Script" path="{NPC_DATA_SCRIPT_PATH}" id="1"]',
        ]

        portrait_before_ext_id = ""
        portrait_after_ext_id = ""

        if portrait_before_path:
            portrait_before_ext_id = "portrait_before_1"
            ext_lines.append(f'[ext_resource type="Texture2D" path="{portrait_before_path}" id="{portrait_before_ext_id}"]')

        if portrait_after_path:
            portrait_after_ext_id = "portrait_after_1"
            ext_lines.append(f'[ext_resource type="Texture2D" path="{portrait_after_path}" id="{portrait_after_ext_id}"]')

        load_steps = len(ext_lines) + 1

        resource_lines = [
            "[resource]",
            'script = ExtResource("1")',
            f'npc_id = {format_godot_string(npc_id)}',
            f'npc_type = {format_godot_string(npc_type)}',
            f'npc_name = {format_godot_string(npc_name)}',
            f'gender = {format_godot_string(gender)}',
            f'age = {age}',
            f'dialogue_prefix = {format_godot_string(dialogue_prefix)}',
            f'dialogue_suffix = {format_godot_string(dialogue_suffix)}',
            f'dialogue_after_treatment = {format_godot_string(dialogue_after_treatment)}',
            f'dialogue_treatment_failed = {format_godot_string(dialogue_treatment_failed)}',
        ]

        if portrait_before_ext_id:
            resource_lines.append(f'portrait_before_treatment = {format_ext_resource_value(portrait_before_ext_id)}')
        if portrait_after_ext_id:
            resource_lines.append(f'portrait_after_treatment = {format_ext_resource_value(portrait_after_ext_id)}')

        npc_content_parts = [
            f'[gd_resource type="Resource" script_class="NpcData" load_steps={load_steps} format=3]',
            "",
            *ext_lines,
            "",
            *resource_lines,
            "",
        ]

        write_text_file(NPC_OUTPUT_DIR / f"{safe_filename(npc_id)}.tres", "\n".join(npc_content_parts))


def clear_output_dirs() -> None:
    """
    功能：清理旧的导出资源文件。
    作用：
    1. 防止旧资源残留影响本次导入结果。
    2. 保证输出目录中的 .tres 文件与当前 Excel 数据一致。
    """
    target_dirs = [
        BOOK_OUTPUT_DIR,
        HERB_OUTPUT_DIR,
        DISEASE_OUTPUT_DIR,
        FORMULA_OUTPUT_DIR,
        STORY_OUTPUT_DIR,
        NPC_OUTPUT_DIR,
        HERB_BOOK_ENTRY_OUTPUT_DIR,
        DISEASE_BOOK_ENTRY_OUTPUT_DIR,
        FORMULA_BOOK_ENTRY_OUTPUT_DIR,
        THEORY_BOOK_ENTRY_OUTPUT_DIR,
    ]

    for folder in target_dirs:
        ensure_dir(folder)
        for file_path in folder.glob("*.tres"):
            file_path.unlink()


def main() -> None:
    """
    功能：脚本主入口。
    作用：
    1. 串联读取 Excel、建立索引、校验数据、生成资源的完整流程。
    2. 控制导入过程的执行顺序，保证只有校验通过后才会正式导出。
    """
    log(f"脚本目录: {CURRENT_DIR}")
    log(f"Excel 路径: {EXCEL_PATH}")
    log(f"输出目录: {OUTPUT_DIR}")

    # 第一步：先把 DetailText 文件夹中的 txt 正文同步进 Data.xlsx
    import_detail_text_txt_to_excel()

    # 第二步：读取 Excel 原始数据
    raw_data = load_excel_data(EXCEL_PATH)
    # 第三步：建立索引，加速后续查找和反查
    indexed_data = build_index(raw_data)

    # 第四步：先校验数据，校验不通过则停止生成
    errors = validate_data(indexed_data)
    if errors:
        log("数据校验失败，已停止生成：")
        for err in errors:
            print(" -", err)
        return

    # 第五步：清理旧资源，准备重新导出
    clear_output_dirs()
    # 第六步：按模块生成各类 .tres 资源
    build_book_resources(indexed_data)
    build_herb_resources(indexed_data)
    build_disease_resources(indexed_data)
    build_formula_resources(indexed_data)
    build_theory_resources(indexed_data)
    build_story_resources(indexed_data)
    build_npc_resources(indexed_data)

    log("导入完成")


if __name__ == "__main__":
    main()
