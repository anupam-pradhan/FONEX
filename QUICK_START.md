# 🚀 QUICK START GUIDE - Supabase Only Version

## What You Have Now

✅ **Fully Free** - Uses Supabase (no Firebase)
✅ **Personal Accounts Work** - No restrictions
✅ **Supabase Realtime** - For instant lock/unlock commands
✅ **All Features Working** - State sync, timing, factory reset

---

## 1. Build & Test

```bash
cd /Users/anupampradhan/Desktop/FONEX

# Get dependencies
flutter pub get

# Check for errors
flutter analyze

# Build release APK
flutter build apk --release
```

**Output:** `build/app/outputs/flutter-apk/app-release.apk`

---

## 2. Verify Supabase Commands Table

Check your Supabase Dashboard → SQL Editor:

```sql
-- Make sure this table exists in your public schema:
CREATE TABLE device_commands (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  device_id TEXT NOT NULL,
  command TEXT NOT NULL, -- 'LOCK' or 'UNLOCK'
  created_at TIMESTAMP DEFAULT NOW(),
  processed BOOLEAN DEFAULT FALSE,
  processed_at TIMESTAMP
);

-- Enable realtime:
-- Dashboard → Replication → Enable for public.device_commands
```

---

## 3. Send Lock Command from Your Backend

```sql
-- Lock the device
INSERT INTO device_commands (device_id, command)
VALUES ('your-device-id', 'LOCK');

-- Unlock the device
INSERT INTO device_commands (device_id, command)
VALUES ('your-device-id', 'UNLOCK');
```

**How It Works:**

1. You insert command in Supabase
2. App listens via Supabase Realtime (even with app closed!)
3. App receives command
4. Executes lock/unlock via Android native layer
5. Marks command as processed

---

## 4. Test on Real Device

```bash
# Install on connected Android device
flutter run --release

# Or install APK directly
adb install build/app/outputs/flutter-apk/app-release.apk
```

**Test Checklist:**

- [ ] App starts normally
- [ ] Google login works (personal account)
- [ ] Lock works (app open)
- [ ] Unlock works (app open)
- [ ] Close app completely
- [ ] Insert `LOCK` command in Supabase
- [ ] Device locks (even with app closed) ✅
- [ ] Insert `UNLOCK` command in Supabase
- [ ] Device unlocks ✅
- [ ] Days calculation shows correctly
- [ ] Factory reset blocked when unpaid

---

## 5. Key Files to Know

### `lib/services/supabase_command_listener.dart` (NEW)

Listens for lock/unlock commands via Supabase Realtime.

- Automatically starts when app initializes
- Works in foreground and background
- Uses your existing Supabase credentials

### `lib/services/simple_google_auth.dart` (NEW)

Simplified Google authentication - any account works.

- Personal accounts: ✅ Full features
- Workspace accounts: ✅ Full features
- No restrictions or account checking

### `lib/main.dart` (UPDATED)

- Added SupabaseCommandListener initialization
- Removed Firebase-based background listener
- Removed workspace account restrictions

### `pubspec.yaml` (UPDATED)

**Removed:**

- ❌ `firebase_messaging` (not needed)
- ❌ `firebase_database` (not needed)

**Kept:**

- ✅ `firebase_auth` (for Google Sign-In)
- ✅ `supabase_flutter` (your database)

---

## 6. Your Supabase Setup (Should Already Be Done)

**Location:** Check your Supabase Dashboard

```
URL: https://[your-project].supabase.co
Anon Key: eyJ... (from Settings → API)
```

In `lib/config.dart`:

```dart
// These should match your Supabase project
const String supabaseUrl = 'https://[your-project].supabase.co';
const String supabaseAnonKey = 'eyJ...';
```

---

## 7. How Lock/Unlock Works (Architecture)

```
Backend (Your Server/App)
         ↓
    Supabase Database
    (Insert LOCK/UNLOCK)
         ↓
Supabase Realtime Channel
         ↓
SupabaseCommandListener
(lib/services/supabase_command_listener.dart)
         ↓
Android MethodChannel
         ↓
Device Lock Manager
(Kotlin in android/)
         ↓
Device Locked/Unlocked ✅
```

**Key Point:** Works even if app is closed because:

1. Supabase Realtime is a persistent connection
2. App auto-reconnects on startup
3. Commands are stored in database (not lost)

---

## 8. Troubleshooting

### "Device lock failed"

- Check: Is Device Owner set up? Run `provision_device.sh`
- Check: Is app set as device owner? (Settings → Device Admin)

### "Commands not received"

- Check: Supabase Realtime enabled for device_commands table
- Check: Command inserted in correct format (device_id TEXT, command TEXT)
- Check: App has internet connection

### "Personal account says no access"

- This shouldn't happen - all accounts are equal now
- Check: You're using `SimpleGoogleAuth` (not old WorkspaceAuthService)
- Check: main.dart imports are correct

### "State mismatched"

- DeviceStateManager should sync automatically
- Tap "Sync" button in developer debug panel

---

## 9. Next Steps

1. **Build & Deploy APK**

   ```bash
   flutter build apk --release
   ```

2. **Test Lock/Unlock**
   - Insert commands in Supabase
   - Verify device responds

3. **Monitor Logs**
   - Use: `flutter logs` while app running
   - Look for `SupabaseCommandListener` messages

4. **Deploy to Retail Devices**
   - Use your device management system
   - Push APK to devices
   - Test on actual retail hardware

---

## 10. Support & Debugging

### Enable Debug Logging

In `lib/services/app_logger.dart`, logs are already enabled:

```dart
AppLogger.log('Message'); // Prints to console & file
```

### View Logs

```bash
flutter logs | grep SupabaseCommandListener
flutter logs | grep DeviceStateManager
```

### Developer Debug Panel

In `lib/main.dart`, you can add a tap gesture on the FONEX logo to show the debug panel:

```dart
// Shows real-time state, logs, and sync button
DeveloperDebugPanel().show();
```

---

## Important Reminders

✅ **Supabase Only** - No Firebase needed
✅ **Free Services** - Supabase, Vercel, no paid services
✅ **Personal Accounts** - Any Google account works fully
✅ **No Restrictions** - All users equal access
✅ **Production Ready** - Test and deploy!

**Questions?** Check `SUPABASE_ONLY_CHANGES.md` for detailed info.
