# 🔧 FINAL INTEGRATION - Apply These Changes

## ⚠️ CRITICAL: Services Created But Not Integrated

The sync services are ready but need to be connected to `main.dart`. Apply these exact changes:

---

## Change 1: Add Imports (After Line 10)

**File:** `lib/main.dart`  
**Location:** After `import 'config.dart';`

**Add these two lines:**
```dart
import 'services/device_storage_service.dart';
import 'services/sync_service.dart';
```

**Complete section should look like:**
```dart
import 'dart:convert';
import 'config.dart';
import 'services/device_storage_service.dart';
import 'services/sync_service.dart';
```

---

## Change 2: Initialize Sync Service (Line 626)

**File:** `lib/main.dart`  
**Location:** In `_DeviceControlHomeState.initState()` method

**Find:**
```dart
@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addObserver(this);
  _initialize();
```

**Change to:**
```dart
@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addObserver(this);
  // Initialize sync service for enterprise-level sync
  SyncService().initialize();
  _initialize();
```

---

## Change 3: Dispose Sync Service (Line 643)

**File:** `lib/main.dart`  
**Location:** In `_DeviceControlHomeState.dispose()` method

**Find:**
```dart
@override
void dispose() {
  _simCheckTimer?.cancel();
  _serverCheckInTimer?.cancel();
  WidgetsBinding.instance.removeObserver(this);
  super.dispose();
}
```

**Change to:**
```dart
@override
void dispose() {
  _simCheckTimer?.cancel();
  _serverCheckInTimer?.cancel();
  SyncService().dispose();
  WidgetsBinding.instance.removeObserver(this);
  super.dispose();
}
```

---

## Change 4: Update _serverCheckIn Method (Line 809)

**File:** `lib/main.dart`  
**Location:** Replace entire `_serverCheckIn` method

**Replace the method starting at line 809 with this optimized version:**

```dart
  /// Backend check-in — optimized sync with auto-registration and queue management
  /// Uses enterprise-level sync service for reliability and offline support
  Future<void> _serverCheckIn({int retryCount = 0}) async {
    if (_isConnecting) return; // Prevent concurrent check-ins
    
    _isConnecting = true;
    try {
      final deviceHash = await DeviceHashUtil.getDeviceHash();
      String imei = "Not Found";
      Map<String, dynamic> metadata = {};
      
      try {
        final info = await _channel.invokeMapMethod<String, dynamic>('getDeviceInfo');
        if (info != null) {
          if (info.containsKey('imei')) imei = info['imei'] as String;
          metadata = {
            'model': info['deviceModel']?.toString() ?? 'Unknown',
            'manufacturer': info['manufacturer']?.toString() ?? 'Unknown',
            'android_version': info['androidVersion'] ?? 0,
            'is_device_owner': _isDeviceOwner,
          };
        }
      } catch (_) {}

      // Check if this is first registration and auto-save to local DB
      final isRegistered = await DeviceStorageService.isDeviceRegistered();
      if (!isRegistered) {
        debugPrint('🆕 First-time registration detected - auto-saving to local DB...');
        await SyncService().registerDevice(
          deviceHash: deviceHash,
          imei: imei,
          metadata: metadata,
        );
      }

      // Perform optimized check-in using sync service
      final syncService = SyncService();
      final response = await syncService.performCheckIn(
        deviceHash: deviceHash,
        imei: imei,
        isLocked: _isDeviceLocked,
        daysRemaining: _daysRemaining,
        metadata: metadata,
      );

      if (response != null) {
        if (mounted) {
          setState(() {
            _isServerConnected = true;
            _serverStatusMessage = 'Connected';
            _lastServerSync = DateTime.now();
          });
        }
        
        final rawAction = response['action'] as String? ?? 'none';
        final action = rawAction.toLowerCase();
        
        debugPrint('Server check-in response: action=$action');
        
        // Execute server commands with accuracy
        switch (action) {
          case 'lock':
            await _engageDeviceLock();
            if (mounted) setState(() { _isDeviceLocked = true; _daysRemaining = 0; });
            debugPrint('Device locked by server command');
            break;
          case 'unlock':
            await _disengageDeviceLock();
            debugPrint('Device unlocked by server command');
            break;
          case 'extend':
          case 'extend_days':
            final days = response['days'] as int? ?? _lockAfterDays;
            final prefs = await SharedPreferences.getInstance();
            await prefs.setInt(
              _keyLastVerified,
              DateTime.now().subtract(Duration(days: _lockAfterDays - days)).millisecondsSinceEpoch,
            );
            if (mounted) setState(() => _daysRemaining = days);
            debugPrint('Device extended by server: $days days');
            break;
          case 'paid_in_full':
          case 'mark_paid_in_full':
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('is_paid_in_full', true);
            if (mounted) setState(() => _isPaidInFull = true);
            await _disengageDeviceLock();
            try {
              await _channel.invokeMethod('clearDeviceOwner');
              debugPrint('Device marked as paid in full - restrictions removed');
            } on PlatformException catch (e) {
              debugPrint('Error clearing device owner: $e');
            }
            break;
          case 'none':
            debugPrint('No action required from server');
            break;
          default:
            debugPrint('Unknown server action: $action');
            break;
        }
      } else {
        // Sync failed but queued for retry
        if (mounted) {
          setState(() {
            _isServerConnected = false;
            _serverStatusMessage = 'Queued for sync';
          });
        }
        debugPrint('Check-in queued for retry (offline or server error)');
      }
    } catch (e, stacktrace) {
      if (mounted) {
        setState(() {
          _isServerConnected = false;
          _serverStatusMessage = 'Connection failed';
        });
      }
      debugPrint('Error during _serverCheckIn: $e\n$stacktrace');
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    }
  }
```

---

## ✅ Verification Steps

After applying changes:

1. **Check Imports:**
   ```bash
   grep -n "import.*services" lib/main.dart
   ```
   Should show 2 import lines

2. **Check Initialization:**
   ```bash
   grep -n "SyncService().initialize()" lib/main.dart
   ```
   Should show 1 line in initState

3. **Check Disposal:**
   ```bash
   grep -n "SyncService().dispose()" lib/main.dart
   ```
   Should show 1 line in dispose

4. **Check Method Update:**
   ```bash
   grep -n "First-time registration detected" lib/main.dart
   ```
   Should show 1 line in _serverCheckIn

---

## 🚀 After Integration

1. Run `flutter pub get` (if needed)
2. Test first registration
3. Test offline sync
4. Build release APK
5. Deploy to production

---

**Status: Ready to integrate - Apply 4 changes above!**
