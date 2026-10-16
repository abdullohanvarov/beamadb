@echo off
setlocal

echo ==============================================================
echo           BeamADB Windows Installer Builder (.exe)
echo ==============================================================
echo.

set "DIR=%~dp0"
cd /d "%DIR%"

:: 1. Locate Python
set "PYTHON_EXE="
where python >nul 2>nul
if %ERRORLEVEL% EQU 0 set "PYTHON_EXE=python"
if not defined PYTHON_EXE (
    if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" (
        set "PYTHON_EXE=%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
    ) else if exist "%ProgramFiles%\Python312\python.exe" (
        set "PYTHON_EXE=%ProgramFiles%\Python312\python.exe"
    ) else (
        where py >nul 2>nul
        if %ERRORLEVEL% EQU 0 set "PYTHON_EXE=py -3"
    )
)

if not defined PYTHON_EXE (
    echo [ERROR] Python 3.8+ is required to build the executable.
    exit /b 1
)

echo [*] Using Python: %PYTHON_EXE%

:: 2. Locate Inno Setup Compiler (ISCC)
set "ISCC_EXE="
where iscc >nul 2>nul
if %ERRORLEVEL% EQU 0 set "ISCC_EXE=iscc"
if not defined ISCC_EXE (
    if exist "%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe" (
        set "ISCC_EXE=%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe"
    ) else if exist "%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe" (
        set "ISCC_EXE=%ProgramFiles(x86)%\Inno Setup 6\ISCC.exe"
    ) else if exist "%ProgramFiles%\Inno Setup 6\ISCC.exe" (
        set "ISCC_EXE=%ProgramFiles%\Inno Setup 6\ISCC.exe"
    )
)

if not defined ISCC_EXE (
    echo [ERROR] Inno Setup 6 compiler ISCC.exe was not found.
    echo Please install Inno Setup 6 from https://jrsoftware.org/isdl.php
    exit /b 1
)

echo [*] Using Inno Setup Compiler: %ISCC_EXE%

:: 3. Locate or Install PyInstaller
set "PYINSTALLER_EXE="
where pyinstaller >nul 2>nul
if %ERRORLEVEL% EQU 0 set "PYINSTALLER_EXE=pyinstaller"
if not defined PYINSTALLER_EXE (
    if exist "%LOCALAPPDATA%\Programs\Python\Python312\Scripts\pyinstaller.exe" (
        set "PYINSTALLER_EXE=%LOCALAPPDATA%\Programs\Python\Python312\Scripts\pyinstaller.exe"
    )
)

if not defined PYINSTALLER_EXE (
    echo [*] Installing PyInstaller...
    %PYTHON_EXE% -m pip install pyinstaller
    set "PYINSTALLER_EXE=%PYTHON_EXE% -m PyInstaller"
)

:: 4. Build standalone beamadb.exe
echo.
echo [*] Step 1/3: Compiling standalone beamadb.exe...
"%PYINSTALLER_EXE%" --noconfirm --clean --onefile --name beamadb --icon "static/icon.ico" --add-data "static;static" --add-data "pyqrcode;pyqrcode" beamadb
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] PyInstaller build failed!
    exit /b %ERRORLEVEL%
)

:: 5. Compile Inno Setup Installer
echo.
echo [*] Step 2/3: Compiling Windows Installer (BeamADB-1.0.0-Setup.exe)...
"%ISCC_EXE%" installer.iss
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Inno Setup compilation failed!
    exit /b %ERRORLEVEL%
)

:: 6. Create Portable ZIP package
echo.
echo [*] Step 3/3: Creating Portable Windows ZIP archive...
powershell -NoProfile -Command "$distDir = 'dist'; $portableDir = 'dist\BeamADB-1.0.0-win64-portable'; if (Test-Path $portableDir) { Remove-Item -Recurse -Force $portableDir }; New-Item -ItemType Directory -Path $portableDir | Out-Null; Copy-Item 'dist\beamadb.exe' $portableDir; Copy-Item 'beamadb.bat' $portableDir; Copy-Item 'launch.bat' $portableDir; Copy-Item 'README.md' $portableDir; Copy-Item 'LICENSE' $portableDir; Copy-Item -Recurse 'static' $portableDir; New-Item -ItemType Directory -Path (Join-Path $portableDir 'bin\scrcpy') | Out-Null; Copy-Item -Recurse 'bin\scrcpy\windows' (Join-Path $portableDir 'bin\scrcpy'); $zipFile = 'dist\BeamADB-1.0.0-win64-portable.zip'; if (Test-Path $zipFile) { Remove-Item -Force $zipFile }; Compress-Archive -Path ('{0}\*' -f $portableDir) -DestinationPath $zipFile; Remove-Item -Recurse -Force $portableDir; Write-Host 'Created portable zip successfully!'"

echo.
echo ==============================================================
echo [SUCCESS] Windows Build Complete!
echo Artifacts created in dist\:
dir /b dist\*.exe dist\*.zip 2>nul
echo ==============================================================
