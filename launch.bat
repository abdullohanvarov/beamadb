@echo off
setlocal
set "DIR=%~dp0"
title BeamADB - Android Wireless Debugging

echo ==============================================================
echo                      BeamADB Launcher
echo       Android Wireless Debugging ^& QR Pairing Bridge
echo ==============================================================
echo.

if exist "%DIR%dist\beamadb.exe" (
    echo Starting BeamADB...
    start "" "%DIR%dist\beamadb.exe" ui
    exit /b 0
)

if exist "%DIR%beamadb.exe" (
    echo Starting BeamADB...
    start "" "%DIR%beamadb.exe" ui
    exit /b 0
)

where py >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    echo Starting BeamADB using Python launcher...
    start "" py -3 "%DIR%beamadb" ui
    exit /b 0
)

where python >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    echo Starting BeamADB using python.exe...
    start "" python "%DIR%beamadb" ui
    exit /b 0
)

echo [!] Python 3 was not found.
echo Please install Python 3.8+ or download the BeamADB Windows Installer.
echo.
pause
exit /b 1
