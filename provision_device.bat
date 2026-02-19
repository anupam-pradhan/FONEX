@echo off
REM =============================================================================
REM  FONEX — One-Click Device Provisioning Script (Windows)
REM  For store owners: Connect phone via USB and double-click this file.
REM =============================================================================

title FONEX Device Provisioning
color 0B
echo.
echo  ╔══════════════════════════════════════════╗
echo  ║  FONEX — Device Provisioning Tool        ║
echo  ║  Powered by Roy Communication            ║
echo  ╚══════════════════════════════════════════╝
echo.

REM Check ADB
where adb >nul 2>&1
if %ERRORLEVEL% neq 0 (
    color 0C
    echo  [X] ADB not found!
    echo      Download Android Platform Tools:
    echo      https://developer.android.com/studio/releases/platform-tools
    echo      Extract and add to PATH, then try again.
    pause
    exit /b 1
)
echo  [OK] ADB found

REM Check device
for /f %%i in ('adb devices ^| findstr /c:"device" ^| findstr /v "List"') do set DEVICE=%%i
if "%DEVICE%"=="" (
    color 0E
    echo  [X] No device connected!
    echo.
    echo  Please:
    echo  1. Connect the phone via USB
    echo  2. Enable USB Debugging on the phone
    echo  3. Accept the USB debugging prompt on the phone
    echo  4. Run this script again
    pause
    exit /b 1
)
echo  [OK] Device connected

REM Find APK
set APK_PATH=
if exist "build\app\outputs\flutter-apk\app-debug.apk" (
    set APK_PATH=build\app\outputs\flutter-apk\app-debug.apk
)
if exist "build\app\outputs\flutter-apk\app-release.apk" (
    set APK_PATH=build\app\outputs\flutter-apk\app-release.apk
)

if "%APK_PATH%"=="" (
    echo  [!] No APK found. Building...
    flutter build apk --debug
    set APK_PATH=build\app\outputs\flutter-apk\app-debug.apk
)
echo  [OK] APK ready: %APK_PATH%

REM Install
echo.
echo  → Installing FONEX...
adb install -r "%APK_PATH%"
echo  [OK] FONEX installed

REM Set Device Owner
echo.
echo  → Setting Device Owner...
adb shell dpm set-device-owner com.roycommunication.fonex/.MyDeviceAdminReceiver
echo  [OK] Device Owner set

REM Launch
echo.
echo  → Launching FONEX...
adb shell am start -n com.roycommunication.fonex/.MainActivity
echo  [OK] FONEX launched

echo.
color 0A
echo  ╔══════════════════════════════════════════╗
echo  ║  SETUP COMPLETE!                         ║
echo  ║                                          ║
echo  ║  The device is now protected by FONEX.   ║
echo  ║  Disconnect USB and hand to customer.    ║
echo  ╚══════════════════════════════════════════╝
echo.
pause
