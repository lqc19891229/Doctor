@echo off
setlocal
cd /d "%~dp0"

python export_translations.py translations_managed.xlsx ..\Localization\translations.csv Data.xlsx
set "EXPORT_ERROR=%ERRORLEVEL%"
if not "%EXPORT_ERROR%"=="0" goto report

python export_traditional_chinese_search.py translations_managed.xlsx ..\Localization\search_zh_TW.txt
set "EXPORT_ERROR=%ERRORLEVEL%"

:report
echo.
if "%EXPORT_ERROR%"=="2" (
    echo Export stopped because some translations or Traditional Chinese search aliases are missing.
    echo Please check translations_managed.xlsx and run again.
) else if not "%EXPORT_ERROR%"=="0" (
    echo Export failed. Please check the error message above.
) else (
    echo Export completed successfully.
)
echo.
pause
exit /b %EXPORT_ERROR%
