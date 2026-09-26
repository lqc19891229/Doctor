@echo off
setlocal
cd /d "%~dp0"

REM Export directly to the CSV imported by the Godot project.
python export_translations.py translations_managed.xlsx ..\Localization\translations.csv Data.xlsx

echo.
if errorlevel 2 (
    echo New symptoms need English translations in translations_managed.xlsx.
) else if errorlevel 1 (
    echo Export failed. See the error above.
) else (
    echo Export completed. Reimport translations.csv in Godot.
)
echo.
pause
