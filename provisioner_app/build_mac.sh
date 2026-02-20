#!/bin/bash
# ============================================================
#  FONEX Provisioner — Build macOS App (Self-Contained)
#  Creates a standalone executable/app for macOS.
# ============================================================

echo ""
echo "  FONEX Provisioner — Build Script (macOS)"
echo "  ========================================"
echo ""

# 1. Check for FONEX APK
echo "  [1/4] Checking for FONEX APK..."
if [ ! -f "fonex.apk" ]; then
    if [ -f "../build/app/outputs/flutter-apk/app-release.apk" ]; then
        echo "      Found app-release.apk, copying to fonex.apk..."
        cp "../build/app/outputs/flutter-apk/app-release.apk" "fonex.apk"
    elif [ -f "../build/app/outputs/flutter-apk/app-debug.apk" ]; then
        echo "      Found app-debug.apk (dev build), copying to fonex.apk..."
        cp "../build/app/outputs/flutter-apk/app-debug.apk" "fonex.apk"
    else
        echo "      ⚠️  WARNING: fonex.apk not found."
        echo "      Please build the Flutter app first or place fonex.apk here."
        exit 1
    fi
else
    echo "      Using existing fonex.apk"
fi

# 2. Check/Download ADB for Mac
echo ""
echo "  [2/4] Checking/Downloading ADB (Platform Tools)..."

if [ ! -f "platform-tools/adb" ]; then
    echo "      Downloading Android Platform Tools for Mac..."
    curl -L -o platform-tools-latest-darwin.zip https://dl.google.com/android/repository/platform-tools-latest-darwin.zip
    
    echo "      Extracting..."
    unzip -q platform-tools-latest-darwin.zip
    rm platform-tools-latest-darwin.zip
fi

if [ ! -f "platform-tools/adb" ]; then
    echo "      ❌ ERROR: Failed to download/extract ADB."
    exit 1
fi
echo "      ADB is ready."

# 3. Install Dependencies
echo ""
echo "  [3/4] Installing Python dependencies..."
pip3 install -r requirements.txt
pip3 install pyinstaller

# 4. Build with PyInstaller
echo ""
echo "  [4/4] Building macOS Bundle..."

# --add-binary "src:dest" (colon separator on Unix)
# Bundle adb and fonex.apk
# Note: Mac apps are bundles. content is in Contents/MacOS/
# We put adb in same dir as executable inside bundle.

~/.local/bin/pyinstaller \
  --noconfirm \
  --onefile \
  --windowed \
  --name FONEX_Provisioner \
  --add-binary "platform-tools/adb:." \
  --add-data "fonex.apk:." \
  fonex_provisioner.py 2>/dev/null || \
python3 -m PyInstaller \
  --noconfirm \
  --onefile \
  --windowed \
  --name FONEX_Provisioner \
  --add-binary "platform-tools/adb:." \
  --add-data "fonex.apk:." \
  fonex_provisioner.py

echo ""
echo "  ============================================================"
echo "  BUILD SUCCESS!"
echo "  ============================================================"
echo ""
echo "  Output: dist/FONEX_Provisioner.app"
echo ""

