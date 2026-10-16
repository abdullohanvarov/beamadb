@echo off
setlocal
set "DIR=%~dp0"

if exist "%DIR%dist\beamadb.exe" (
    "%DIR%dist\beamadb.exe" %*
    exit /b %ERRORLEVEL%
)

if exist "%DIR%beamadb.exe" (
    "%DIR%beamadb.exe" %*
    exit /b %ERRORLEVEL%
)

where py >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    py -3 "%DIR%beamadb" %*
    exit /b %ERRORLEVEL%
)

where python >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    python "%DIR%beamadb" %*
    exit /b %ERRORLEVEL%
)

echo [!] Python 3 was not found. Please install Python 3.8+ or run beamadb.exe.
exit /b 1
