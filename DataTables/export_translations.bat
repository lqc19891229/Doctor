@echo off
setlocal
cd /d "%~dp0"

REM 默认目录结构：
REM   Localization\
REM     translations_managed.xlsx
REM     export_translations.py
REM     export_translations.bat
REM   DataTables\
REM     Data.xlsx
REM
REM Python 脚本也支持自动查找 Data.xlsx，
REM 这里显式传入路径，避免项目结构歧义。

python export_translations.py translations_managed.xlsx translations.csv ..\DataTables\Data.xlsx

echo.
if errorlevel 2 (
    echo 已同步新的疾病症状，但其中部分英文翻译仍为空。
    echo 请打开 translations_managed.xlsx，补全新增症状的英文后再次运行。
) else if errorlevel 1 (
    echo 导出失败，请查看上方错误信息。
) else (
    echo 导出成功。
)
echo.
pause
