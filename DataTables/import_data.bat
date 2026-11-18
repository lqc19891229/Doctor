@echo off
setlocal EnableExtensions
cd /d "%~dp0"
if errorlevel 1 goto :bad_directory

rem Use UTF-8 for Python's Chinese log output on Japanese Windows.
chcp 65001 >nul
set "PYTHONIOENCODING=utf-8"

echo ==========================================
echo Doctor - Data Import
echo ==========================================
echo.

if not exist "import_data.py" goto :missing_script
if not exist "Data.xlsx" goto :missing_xlsx

rem Check for a working Python 3 interpreter, not just a Windows Store alias.
set "PYTHON_CMD="
where python >nul 2>&1
if not errorlevel 1 (
    python -c "import sys; assert sys.version_info.major == 3" >nul 2>&1
    if not errorlevel 1 set "PYTHON_CMD=python"
)
if defined PYTHON_CMD goto :python_ready

where py >nul 2>&1
if not errorlevel 1 (
    py -3 -c "import sys; assert sys.version_info.major == 3" >nul 2>&1
    if not errorlevel 1 set "PYTHON_CMD=py -3"
)
if not defined PYTHON_CMD goto :missing_python

:python_ready
echo Python:
%PYTHON_CMD% --version
echo.
echo Running import_data.py...
echo.
%PYTHON_CMD% "import_data.py"
set "RESULT=%ERRORLEVEL%"
echo.
if "%RESULT%"=="0" goto :import_success

echo ==========================================
echo Import failed. Exit code: %RESULT%
echo ==========================================
echo Check the error messages above.
echo If openpyxl is missing, run:
echo     %PYTHON_CMD% -m pip install openpyxl
echo.
pause
exit /b %RESULT%

:import_success
echo ==========================================
echo Import finished.
echo ==========================================
echo Data.xlsx was processed and Godot .tres resources were generated.
echo.
pause
exit /b 0

:missing_python
echo ERROR: Python 3 was not found.
echo Install Python 3 and ensure python or py is available in PATH.
echo.
pause
exit /b 1

:missing_script
echo ERROR: import_data.py was not found in:
echo %cd%
echo.
pause
exit /b 1

:missing_xlsx
echo ERROR: Data.xlsx was not found in:
echo %cd%
echo.
pause
exit /b 1

:bad_directory
echo ERROR: Cannot open the DataTables directory.
echo.
pause
exit /b 1
