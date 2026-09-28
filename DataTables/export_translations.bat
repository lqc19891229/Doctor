@echo off
setlocal
cd /d "%~dp0"

python export_translations.py translations_managed.xlsx ..\Localization\translations.csv Data.xlsx

echo.
if errorlevel 2 (
    echo Export stopped because some translations are missing.
    echo Please check translations_managed.xlsx and run again.
) else if errorlevel 1 (
    echo Export failed. Please check the error message above.
) else (
    echo Export completed successfully.
)
echo.
pause
