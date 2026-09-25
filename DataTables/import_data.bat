@echo off
setlocal
cd /d "%~dp0"

echo ==========================================
echo Doctor Data Import
echo ==========================================
echo.

REM Prefer "python"; fall back to Windows "py" launcher.
where python >nul 2>nul
if %errorlevel%==0 (
    set "PYTHON_CMD=python"
) else (
    where py >nul 2>nul
    if %errorlevel%==0 (
        set "PYTHON_CMD=py"
    ) else (
        echo ERROR: Python was not found.
        echo Please install Python and make sure python or py is available in PATH.
        echo.
        pause
        exit /b 1
    )
)

REM import_data.py expects Data.xlsx in the same DataTables folder.
if not exist "import_data.py" (
    echo ERROR: import_data.py was not found in:
    echo %cd%
    echo.
    echo Put this BAT file in the same folder as import_data.py and Data.xlsx.
    echo.
    pause
    exit /b 1
)

if not exist "Data.xlsx" (
    echo ERROR: Data.xlsx was not found in:
    echo %cd%
    echo.
    echo import_data.py reads Data.xlsx from its own folder.
    echo.
    pause
    exit /b 1
)

echo Python:
%PYTHON_CMD% --version
echo.
echo Running import_data.py...
echo.

%PYTHON_CMD% "import_data.py"
set "RESULT=%errorlevel%"

echo.
if not "%RESULT%"=="0" (
    echo ==========================================
    echo IMPORT FAILED - exit code %RESULT%
    echo ==========================================
    echo.
    echo Check the error messages above.
    echo If openpyxl is missing, run:
    echo     %PYTHON_CMD% -m pip install openpyxl
    echo.
    pause
    exit /b %RESULT%
)

echo ==========================================
echo IMPORT COMPLETED SUCCESSFULLY
echo ==========================================
echo.
echo Data.xlsx has been imported and Godot .tres resources have been regenerated.
echo.
pause
exit /b 0
