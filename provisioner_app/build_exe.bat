@echo off
REM ============================================================
REM  FONEX Provisioner — Build Windows EXE (Self-Contained)
REM  Run this on Windows to create the standalone .exe
REM ============================================================

title Building FONEX Provisioner...
echo.
echo  [1/4] Checking for FONEX APK...

REM Copy from Flutter build output if available
if not exist fonex.apk (
    if exist "..\build\app\outputs\flutter-apk\app-release.apk" (
        echo      Found app-release.apk, copying to fonex.apk...
        copy "..\build\app\outputs\flutter-apk\app-release.apk" "fonex.apk"
    ) else (
        echo      WARNING: fonex.apk not found in current folder or build output.
        echo      Please build the Flutter app first or place fonex.apk here manually.
        pause
        exit /b
    )
) else (
    echo      Using existing fonex.apk
)

echo.
echo  [2/4] checking/downloading ADB (Platform Tools)...

if not exist platform-tools\adb.exe (
    echo      Downloading Android Platform Tools...
    curl -L -o platform-tools-latest-windows.zip https://dl.google.com/android/repository/platform-tools-latest-windows.zip
    
    echo      Extracting...
    tar -xf platform-tools-latest-windows.zip
    
    del platform-tools-latest-windows.zip
)

if not exist platform-tools\adb.exe (
    echo      ERROR: Failed to download/extract ADB.
    pause
    exit /b
)
echo      ADB is ready.

echo.
echo  [3/4] Installing Python dependencies...
pip install -r requirements.txt
pip install pyinstaller

echo.
echo  [4/4] Building FONEX_Provisioner.exe...

REM  --add-binary "src;dest"  (Windows separator is ;)
REM  We bundle adb.exe and dlls into the root of the internal _MEIPASS folder

pyinstaller ^
  --noconfirm ^
  --onefile ^
  --windowed ^
  --name FONEX_Provisioner ^
  --icon=fonex_icon.ico ^
  --add-binary "platform-tools/adb.exe;." ^
  --add-binary "platform-tools/AdbWinApi.dll;." ^
  --add-binary "platform-tools/AdbWinUsbApi.dll;." ^
  --add-data "fonex.apk;." ^
  fonex_provisioner.py

echo.
echo  ============================================================
echo  BUILD SUCCESS!
echo  ============================================================
echo.
echo  Your standalone EXE is at:  dist\FONEX_Provisioner.exe
echo.
echo  It works on any Windows PC without needing extra files.
echo.
pause
