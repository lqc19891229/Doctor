@echo off
setlocal
cd /d "%~dp0"

echo ==========================================
echo Doctor 数据导入
echo ==========================================
echo.

REM 优先使用 python；如果不可用，则尝试 Windows 的 py 启动器。
where python >nul 2>nul
if %errorlevel%==0 (
    set "PYTHON_CMD=python"
) else (
    where py >nul 2>nul
    if %errorlevel%==0 (
        set "PYTHON_CMD=py"
    ) else (
        echo 错误：未找到 Python。
        echo 请先安装 Python，并确认 python 或 py 已加入 PATH。
        echo.
        pause
        exit /b 1
    )
)

REM import_data.py 要求 Data.xlsx 与它位于同一个 DataTables 文件夹。
if not exist "import_data.py" (
    echo 错误：当前文件夹中找不到 import_data.py：
    echo %cd%
    echo.
    echo 请把本 BAT 文件放到与 import_data.py 和 Data.xlsx 相同的文件夹中。
    echo.
    pause
    exit /b 1
)

if not exist "Data.xlsx" (
    echo 错误：当前文件夹中找不到 Data.xlsx：
    echo %cd%
    echo.
    echo import_data.py 会从自身所在文件夹读取 Data.xlsx。
    echo.
    pause
    exit /b 1
)

echo 当前 Python 版本：
%PYTHON_CMD% --version
echo.
echo 正在运行 import_data.py...
echo.

%PYTHON_CMD% "import_data.py"
set "RESULT=%errorlevel%"

echo.
if not "%RESULT%"=="0" (
    echo ==========================================
    echo 数据导入失败 - 退出代码 %RESULT%
    echo ==========================================
    echo.
    echo 请查看上方的错误信息。
    echo 如果提示缺少 openpyxl，请运行：
    echo     %PYTHON_CMD% -m pip install openpyxl
    echo.
    pause
    exit /b %RESULT%
)

echo ==========================================
echo 数据导入完成
echo ==========================================
echo.
echo Data.xlsx 已成功导入，并重新生成 Godot .tres 资源。
echo.
pause
exit /b 0
