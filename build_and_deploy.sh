#!/bin/bash
# FONEX Build & Deploy Script
# Supabase-Only Version

set -e  # Exit on error

PROJECT_DIR="/Users/anupampradhan/Desktop/FONEX"
cd "$PROJECT_DIR"

ENV_FILE=".env"
if [ -f "$ENV_FILE" ]; then
    echo "🔐 Loading build environment from $ENV_FILE"
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
else
    echo "⚠️  $ENV_FILE not found. Falling back to shell environment variables."
fi

echo "╔════════════════════════════════════════════════════════════╗"
echo "║        FONEX - SUPABASE-ONLY DEPLOYMENT SCRIPT            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Step 1: Check Flutter
echo "📱 Checking Flutter installation..."
flutter --version
echo "✅ Flutter OK"
echo ""

# Step 2: Get dependencies
echo "📦 Getting dependencies..."
flutter pub get
echo "✅ Dependencies installed"
echo ""

# Step 3: Run analysis
echo "🔍 Running Flutter analysis..."
if flutter analyze; then
    echo "✅ No critical errors"
else
    echo "⚠️  Analysis found issues (see above)"
fi
echo ""

# Step 4: Build APK
echo "🔨 Building release APK..."
REQUIRED_ENV_KEYS=(
    "SERVER_BASE_URL"
    "SUPABASE_URL"
    "SUPABASE_ANON_KEY"
    "DEVICE_SECRET"
    "COMMAND_SIGNING_SECRET"
    "ENFORCE_SIGNED_COMMANDS"
    "COMMAND_SIGNATURE_MAX_AGE_SECONDS"
)

MISSING_KEYS=()
for key in "${REQUIRED_ENV_KEYS[@]}"; do
    if [ -z "${!key}" ]; then
        MISSING_KEYS+=("$key")
    fi
done

if [ ${#MISSING_KEYS[@]} -gt 0 ]; then
    echo "❌ Missing required environment values:"
    for key in "${MISSING_KEYS[@]}"; do
        echo "   - $key"
    done
    echo "Add them to .env (see .env.example) or export them in shell."
    exit 1
fi

BUILD_CMD=(
    flutter build apk --release
    "--dart-define=SERVER_BASE_URL=$SERVER_BASE_URL"
    "--dart-define=SUPABASE_URL=$SUPABASE_URL"
    "--dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY"
    "--dart-define=DEVICE_SECRET=$DEVICE_SECRET"
    "--dart-define=COMMAND_SIGNING_SECRET=$COMMAND_SIGNING_SECRET"
    "--dart-define=ENFORCE_SIGNED_COMMANDS=$ENFORCE_SIGNED_COMMANDS"
    "--dart-define=COMMAND_SIGNATURE_MAX_AGE_SECONDS=$COMMAND_SIGNATURE_MAX_AGE_SECONDS"
)
"${BUILD_CMD[@]}"

if [ -f "build/app/outputs/flutter-apk/app-release.apk" ]; then
    echo "✅ APK built successfully"
    APK_SIZE=$(du -h "build/app/outputs/flutter-apk/app-release.apk" | cut -f1)
    echo "   Size: $APK_SIZE"
else
    echo "❌ Build failed"
    exit 1
fi
echo ""

# Step 5: Check connected devices
echo "📱 Checking connected devices..."
if adb devices | grep -q "device$"; then
    echo "✅ Android device found"
    
    # Step 6: Install APK
    echo "📲 Installing APK on device..."
    adb install -r "build/app/outputs/flutter-apk/app-release.apk"
    echo "✅ APK installed"
    echo ""
    
    # Step 7: Run app
    read -p "🚀 Launch app now? (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Launching FONEX..."
        adb shell am start -n "com.roycomm.fonex/.MainActivity"
        echo "✅ App launched"
        echo ""
        echo "📋 Follow logs:"
        echo "   flutter logs"
    fi
else
    echo "⚠️  No device connected"
    echo ""
    echo "📌 APK ready at:"
    echo "   build/app/outputs/flutter-apk/app-release.apk"
    echo ""
    echo "To install manually:"
    echo "   adb install -r build/app/outputs/flutter-apk/app-release.apk"
fi

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                    BUILD COMPLETE ✅                       ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "📚 Documentation:"
echo "   • QUICK_START.md - Testing guide"
echo "   • SUPABASE_ONLY_CHANGES.md - Technical details"
echo "   • MIGRATION_SUMMARY.md - Overview"
echo ""
echo "🧪 Test Checklist:"
echo "   [ ] App starts normally"
echo "   [ ] Google login works"
echo "   [ ] Lock/unlock works (app open)"
echo "   [ ] Close app completely"
echo "   [ ] Insert LOCK in Supabase"
echo "   [ ] Device locks (app closed) ✅"
echo "   [ ] Days calculation correct"
echo "   [ ] Factory reset blocked when unpaid"
echo ""
