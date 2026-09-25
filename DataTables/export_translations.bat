@echo off
setlocal
cd /d "%~dp0"

REM Default layout:
REM   Localization\
REM     translations_managed.xlsx
REM     export_translations.py
REM     export_translations.bat
REM   DataTables\
REM     Data.xlsx
REM
REM The Python script can also auto-detect Data.xlsx, but the explicit path below
REM makes the project layout unambiguous.

python export_translations.py translations_managed.xlsx translations.csv ..\DataTables\Data.xlsx

echo.
if errorlevel 2 (
    echo New disease symptoms were synchronized, but some English translations are blank.
    echo Open translations_managed.xlsx, translate the new symptom rows, save it, then run again.
) else if errorlevel 1 (
    echo Export failed. Check the error message above.
) else (
    echo Export completed successfully.
)
echo.
pause
