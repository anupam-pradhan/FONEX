# FONEX Setup Guide

Complete setup guide for FONEX Device Control System.

## Prerequisites

1. **Flutter SDK** (3.10.7 or higher)
2. **Android Studio** with Android SDK
3. **Backend Server** (Vercel, Supabase/Neon/MongoDB)
4. **ADB Tools** (for device provisioning)

## Step 1: Configure App Settings

### 1.1 Update Configuration File

Edit `lib/config.dart` with your details:

```dart
// Store Information
static const String storeName = 'Your Store Name';
static const String supportPhone1 = '+91XXXXXXXXXX';
static const String supportPhone2 = '+91XXXXXXXXXX';

// Server URL
static const String serverBaseUrl = 'https://your-backend.vercel.app/api/v1/devices';

// EMI Settings
static const int lockAfterDays = 30; // Days before auto-lock
```

### 1.2 Update Android Package Name (Optional)

If you want a custom package name:

1. Edit `android/app/build.gradle.kts`:
   ```kotlin
   applicationId = "com.yourcompany.fonex"
   ```

2. Update package names in:
   - `android/app/src/main/kotlin/com/roycommunication/fonex/`
   - `android/app/src/main/AndroidManifest.xml`

## Step 2: Backend Server Setup

### 2.1 Deploy Backend

Follow the instructions in `backend_prompt.md` to:
1. Set up database (Supabase/Neon/MongoDB)
2. Deploy API endpoints to Vercel
3. Configure environment variables

### 2.2 Required API Endpoints

Your backend must implement:

- `POST /api/v1/devices/checkin` - Device heartbeat
- `POST /api/v1/devices/unlock` - PIN verification
- `GET /api/v1/devices` - List devices (admin)
- `POST /api/v1/devices/{id}/action` - Device actions (admin)

### 2.3 Update Server URL

After deploying, update `lib/config.dart`:
```dart
static const String serverBaseUrl = 'https://your-deployed-backend.vercel.app/api/v1/devices';
```

## Step 3: Build App

### 3.1 Install Dependencies

```bash
flutter pub get
```

### 3.2 Build APK

```bash
# Debug build
flutter build apk --debug

# Release build (for production)
flutter build apk --release
```

### 3.3 Sign APK (Production)

1. Generate keystore:
   ```bash
   keytool -genkey -v -keystore fonex-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias fonex
   ```

2. Create `android/key.properties`:
   ```properties
   storePassword=your_password
   keyPassword=your_password
   keyAlias=fonex
   storeFile=../fonex-key.jks
   ```

3. Update `android/app/build.gradle.kts` with signing config

## Step 4: Device Provisioning

### 4.1 Prepare Device

1. **Factory reset** the Android device
2. **Skip Google account** during setup
3. Enable **USB Debugging**:
   - Settings → About Phone → Tap Build Number 7 times
   - Settings → Developer Options → USB Debugging ON

### 4.2 Run Provisioner

**Windows:**
```bash
provision_device.bat
```

**Mac/Linux:**
```bash
chmod +x provision_device.sh
./provision_device.sh
```

**Or use GUI:**
- Run `provisioner_app/FONEX_Provisioner.exe` (Windows)
- Run `provisioner_app/dist/FONEX_Provisioner` (Mac)

### 4.3 Verify Setup

After provisioning:
- App should launch automatically
- Device Owner status should be active
- Lock screen should appear after 30 days

## Step 5: Testing

### 5.1 Test Server Connection

1. Launch app
2. Check connection status indicator
3. Verify server sync in logs

### 5.2 Test Device Lock

1. Use dev tools to simulate expiry
2. Verify lock screen appears
3. Test PIN unlock
4. Test emergency call buttons

### 5.3 Test Factory Reset Block

1. Try factory reset from Settings
2. Should show blocked message
3. After marking as paid, reset should work

## Step 6: Production Deployment

### 6.1 Build Release APK

```bash
flutter build apk --release
```

### 6.2 Distribute APK

- Upload to your distribution platform
- Or use the provisioner app for direct installation

### 6.3 Monitor Devices

- Use admin dashboard to monitor devices
- Check server logs for connection issues
- Monitor device check-ins

## Troubleshooting

### App Won't Lock
- Check Device Owner status
- Verify app has necessary permissions
- Check server connection

### Server Connection Fails
- Verify server URL in config
- Check network connectivity
- Review server logs

### Factory Reset Not Blocked
- Verify Device Owner is active
- Check payment status
- Review restriction settings

### App Can Be Uninstalled
- Ensure Device Owner is set
- Check if EMI is marked as paid
- Verify restrictions are applied

## Support

For issues:
1. Check logs: `adb logcat | grep FONEX`
2. Review server logs
3. Check device status in admin dashboard

## Next Steps

1. ✅ Configure store information
2. ✅ Deploy backend server
3. ✅ Build and test app
4. ✅ Provision test device
5. ✅ Deploy to production
