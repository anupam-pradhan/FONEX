# FONEX 2.0.0 - Quick Reference

## 🚀 Start Here

### 1. Update Dependencies
```bash
cd /Users/anupampradhan/Desktop/FONEX
flutter pub get
```

### 2. Initialize Services
```dart
// In main.dart, inside main():
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  DeviceStateManager().initialize();  // ← ADD THIS
  SyncService().initialize();
  runApp(const FonexApp());
}
```

### 3. Use New Services

#### Lock Device
```dart
final success = await DeviceStateManager().engageLock(
  reason: 'EMI not paid',
);
```

#### Unlock Device
```dart
final success = await DeviceStateManager().disengageLock(
  resetTimerAnchor: true,
);
```

#### Get Remaining Days
```dart
final (days, seconds) = 
    await PreciseTimingService().getRemainingDaysAndSeconds();
```

#### Mark as Paid
```dart
await DeviceStateManager().markPaidInFull();
```

#### Extend EMI
```dart
await PreciseTimingService().extendWindow(5); // +5 days
```

---

## 📋 New Services

### DeviceStateManager
- **Purpose**: Lock/Unlock with guaranteed state sync
- **File**: `lib/services/device_state_manager.dart`
- **Key Methods**:
  - `engageLock()` - Lock device
  - `disengageLock()` - Unlock device
  - `markPaidInFull()` - Mark as paid
  - `markAsEmiPending()` - Back to EMI mode
  - `syncStateWithNative()` - Force sync
  - `getDebugInfo()` - Debug state

### PreciseTimingService
- **Purpose**: Millisecond-precise EMI timer
- **File**: `lib/services/precise_timing_service.dart`
- **Key Methods**:
  - `initializeTimer()` - Set up timer
  - `getRemainingDaysAndSeconds()` - Exact time left
  - `getRemainingDeadline()` - When lock happens
  - `extendWindow()` - Add days
  - `resetTimer()` - Reset timer
  - `syncWithServerRemainingDays()` - Sync with server
  - `getDebugInfo()` - Debug timer

### WorkspaceAuthService
- **Purpose**: Workspace account validation
- **File**: `lib/services/workspace_auth_service.dart`
- **Key Methods**:
  - `isWorkspaceEmail()` - Check domain
  - `signInWithGoogleWorkspace()` - Workspace login
  - `signOut()` - Sign out
  - `isCurrentUserWorkspace()` - Verify user

---

## 🔧 Common Tasks

### Task 1: Lock Device on Timer Expiry
```dart
final expired = remaining <= 0;
if (expired) {
  await DeviceStateManager().engageLock(
    reason: 'EMI timer expired',
  );
}
```

### Task 2: Get Exact Days Left
```dart
final (days, secondsInDay) = 
    await PreciseTimingService().getRemainingDaysAndSeconds();
final hoursLeft = secondsInDay / 3600;
print('$days days, $hoursLeft hours left');
```

### Task 3: Extend Payment Deadline
```dart
// User paid partial amount, extend by 10 days
await PreciseTimingService().extendWindow(10);
AppLogger.log('EMI extended by 10 days');
```

### Task 4: Mark Payment Complete
```dart
// Payment received, mark as paid in full
await DeviceStateManager().markPaidInFull();
// All restrictions removed, device unlocked
```

### Task 5: Sync with Server
```dart
// Server says 20 days remaining, sync it
await PreciseTimingService().syncWithServerRemainingDays(20);
```

---

## ⚙️ Configuration

### Workspace Domains (Edit in workspace_auth_service.dart)
```dart
static const List<String> _allowedDomains = [
  'your-company.com',      // ← Change to your domain
  'your-company.in',
  // Remove gmail.com after testing
];
```

### EMI Window Duration (Edit in config.dart)
```dart
static const int lockAfterDays = 30;      // Default timer
static const int simAbsentLockDays = 7;   // SIM absent grace
```

### Timeouts (Change if needed)
```dart
// device_state_manager.dart - Line 33
.timeout(const Duration(seconds: 5))  // Device state query

// device_state_manager.dart - Line 94
.timeout(const Duration(seconds: 10)) // Lock/unlock
```

---

## 📊 Monitoring

### Check Device State
```dart
final info = await DeviceStateManager().getDebugInfo();
print(info);
// Output:
// Device State Debug Info:
//   Native Lock State: true
//   Native Paid State: false
//   ...
```

### Check Timer State
```dart
final info = await PreciseTimingService().getDebugInfo();
print(info);
// Output:
// Timer Debug Info:
//   Window: 30 days
//   Anchor: 2026-02-01T10:00:00.000Z
//   Remaining: 23 days, 14.50 hours
//   ...
```

### View All Logs
```dart
AppLogger.logs.forEach(print);
// Or get last N logs:
AppLogger.logs.skip(AppLogger.logs.length - 20).forEach(print);
```

---

## ❌ Troubleshooting

### App Hanging
**Cause**: Method channel call stuck
**Fix**: Check device connectivity, all calls have 5-10s timeout now

### Days Wrong
**Cause**: Using old `.inDays` calculation
**Fix**: Use `PreciseTimingService().getRemainingDaysAndSeconds()`

### Lock Not Working
**Cause**: Device not owner or state mismatch
**Fix**: Check `DeviceStateManager().getDebugInfo()`

### Personal Accounts Login
**Cause**: Workspace validation not active
**Fix**: Implement email check before login

---

## 📚 Documentation Files

| File | Purpose |
|------|---------|
| RELEASE_NOTES.md | What's new in v2.0.0 |
| PRODUCTION_READY.md | Complete feature reference |
| IMPLEMENTATION_GUIDE.md | Code examples & patterns |
| QUICK_REFERENCE.md | This file |

---

## ✅ Pre-Deployment Checklist

- [ ] `flutter pub get` completed
- [ ] No compilation errors: `flutter analyze`
- [ ] DeviceStateManager initialized
- [ ] Lock/unlock works correctly
- [ ] Days calculated accurately
- [ ] No app freezing
- [ ] Workspace auth working
- [ ] All core features tested

---

## 🚢 Deployment

### Build Release
```bash
flutter clean
flutter pub get
flutter build apk --release
# Or for iOS:
flutter build ios --release
```

### Install on Device
```bash
# Android
adb install -r build/app/outputs/apk/release/app-release.apk

# iOS (requires Xcode)
flutter install
```

### Verify
- [ ] Lock device works
- [ ] Unlock device works
- [ ] Days show correctly
- [ ] Paid in full removes restrictions
- [ ] No "App not responding" errors

---

## 💡 Tips

1. **Always call DeviceStateManager().initialize()** in main()
2. **Use timeouts** on all native calls (already built-in)
3. **Check AppLogger** for all state changes
4. **Test on real device** before production
5. **Monitor days accuracy** vs server
6. **Keep workspace domains updated**
7. **Review debug info** when something seems wrong

---

## 🆘 Need Help?

1. Check **PRODUCTION_READY.md** for troubleshooting
2. Review **IMPLEMENTATION_GUIDE.md** for code examples
3. Check inline code comments in `/lib/services/`
4. View AppLogger output: `print(AppLogger.logs)`
5. Get debug info: `DeviceStateManager().getDebugInfo()`

---

**Version**: 2.0.0  
**Status**: ✅ Production Ready  
**Last Updated**: February 25, 2026
