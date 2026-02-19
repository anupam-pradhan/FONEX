#!/bin/bash
# =============================================================================
# FONEX — One-Click Device Provisioning Script
# =============================================================================
# For store owners: Just connect the phone via USB and run this script.
# It installs the app and sets Device Owner automatically.
# =============================================================================

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  ${BOLD}FONEX — Device Provisioning Tool${NC}${CYAN}        ║${NC}"
echo -e "${CYAN}║  Powered by Roy Communication            ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

# Check ADB
if ! command -v adb &> /dev/null; then
    echo -e "${RED}✗ ADB not found!${NC}"
    echo "  Please install Android SDK Platform Tools."
    echo "  Download: https://developer.android.com/studio/releases/platform-tools"
    exit 1
fi

echo -e "${GREEN}✓${NC} ADB found"

# Check device connected
DEVICE_COUNT=$(adb devices | grep -c "device$" || true)
if [ "$DEVICE_COUNT" -eq 0 ]; then
    echo -e "${RED}✗ No device connected!${NC}"
    echo ""
    echo "  Please:"
    echo "  1. Connect the phone via USB"
    echo "  2. Enable USB Debugging on the phone"
    echo "     (Settings → About Phone → Tap Build Number 7 times)"
    echo "     (Settings → Developer Options → USB Debugging → ON)"
    echo "  3. Accept the USB debugging prompt on the phone"
    echo "  4. Run this script again"
    exit 1
fi

echo -e "${GREEN}✓${NC} Device connected"

# Check for existing accounts (Device Owner requires no accounts)
ACCOUNTS=$(adb shell pm list users 2>/dev/null | wc -l || echo "0")
echo -e "${GREEN}✓${NC} Device users detected: $ACCOUNTS"

# Find APK
APK_PATH=""
if [ -f "build/app/outputs/flutter-apk/app-debug.apk" ]; then
    APK_PATH="build/app/outputs/flutter-apk/app-debug.apk"
elif [ -f "build/app/outputs/flutter-apk/app-release.apk" ]; then
    APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
fi

if [ -z "$APK_PATH" ]; then
    echo -e "${YELLOW}⚠ No APK found. Building now...${NC}"
    flutter build apk --debug
    APK_PATH="build/app/outputs/flutter-apk/app-debug.apk"
fi

echo -e "${GREEN}✓${NC} APK ready: $APK_PATH"

# Install APK
echo ""
echo -e "${CYAN}→ Installing FONEX on device...${NC}"
adb install -r "$APK_PATH"
echo -e "${GREEN}✓${NC} FONEX installed"

# Set Device Owner
echo ""
echo -e "${CYAN}→ Setting FONEX as Device Owner...${NC}"
RESULT=$(adb shell dpm set-device-owner com.roycommunication.fonex/.MyDeviceAdminReceiver 2>&1)

if echo "$RESULT" | grep -q "Success"; then
    echo -e "${GREEN}✓${NC} Device Owner set successfully!"
else
    echo -e "${YELLOW}⚠ Device Owner result: $RESULT${NC}"
    echo ""
    if echo "$RESULT" | grep -q "already"; then
        echo -e "${GREEN}✓${NC} Device Owner was already set"
    elif echo "$RESULT" | grep -q "account"; then
        echo -e "${RED}✗ ERROR: There are accounts on the device.${NC}"
        echo ""
        echo "  You need to factory reset the device first:"
        echo "  Settings → System → Reset → Factory Data Reset"
        echo "  Then skip adding any Google account during setup."
        exit 1
    else
        echo -e "${RED}✗ Failed to set Device Owner. See error above.${NC}"
        exit 1
    fi
fi

# Verify
echo ""
echo -e "${CYAN}→ Verifying setup...${NC}"
OWNERS=$(adb shell dpm list-owners 2>&1)
if echo "$OWNERS" | grep -q "fonex"; then
    echo -e "${GREEN}✓${NC} Verified: FONEX is Device Owner"
else
    echo -e "${YELLOW}⚠ Could not verify. Owners: $OWNERS${NC}"
fi

# Launch app
echo ""
echo -e "${CYAN}→ Launching FONEX...${NC}"
adb shell am start -n com.roycommunication.fonex/.MainActivity
echo -e "${GREEN}✓${NC} FONEX launched"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ${BOLD}✓ SETUP COMPLETE!${NC}${GREEN}                       ║${NC}"
echo -e "${GREEN}║                                          ║${NC}"
echo -e "${GREEN}║  The device is now protected by FONEX.   ║${NC}"
echo -e "${GREEN}║  You can disconnect the USB cable and    ║${NC}"
echo -e "${GREEN}║  hand the device to the customer.        ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
