@echo off
setlocal
cd /d "%~dp0"
python export_translations.py translations_managed.xlsx translations.csv
echo.
pause
