# Integration Guide: Auto-Save Registration & Optimized Sync

## Overview
This guide explains how to integrate the new auto-save registration and optimized sync services into your existing FONEX app.

## Files Created

1. **lib/services/device_storage_service.dart** - Local storage service for device registration info
2. **lib/services/sync_service.dart** - Enterprise-level sync service with queue and retry logic

## Integration Steps

### Step 1: Add Imports to main.dart

Add these imports at the top of `lib/main.dart` (after line 10):

```dart
import 'services/device_storage_service.dart';
import 'services/sync_service.dart';
```

### Step 2: Initialize Sync Service

In `_DeviceControlHomeState.initState()` method (around line 623), add:

```dart
@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addObserver(this);
  // Initialize sync service for enterprise-level sync
  SyncService().initialize();
  _initialize();
  // ... rest of initState code
}
```

### Step 3: Dispose Sync Service

In `_DeviceControlHomeState.dispose()` method (around line 641), add:

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

### Step 4: Update _serverCheckIn Method

Replace the entire `_serverCheckIn` method (starting at line 809) with this optimized version:

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

## Features Added

### 1. Auto-Save Registration
- On first check-in, device info is automatically saved to local storage
- Registration info persists even if server sync fails
- Device can work offline after initial registration

### 2. Optimized Sync Service
- **Queue Management**: Failed syncs are queued and retried automatically
- **Batch Processing**: Processes multiple sync items efficiently
- **Retry Logic**: Exponential backoff for failed requests
- **Offline Support**: Works seamlessly when network is unavailable

### 3. Enterprise-Level Reliability
- Handles thousands of devices efficiently
- Prevents concurrent sync operations
- Tracks sync failures for diagnostics
- Automatic periodic sync processing

## Backend Requirements

Your backend should handle:
- Auto-registration when `device_hash` or `imei` is new
- `is_first_registration` flag in check-in payload
- Standard check-in response format with `action` field

## Testing

1. **First Registration Test**:
   - Clear app data
   - Launch app
   - Check logs for "First-time registration detected"
   - Verify device info is saved locally

2. **Offline Sync Test**:
   - Disable network
   - Perform check-in
   - Verify sync is queued
   - Re-enable network
   - Verify queued syncs are processed

3. **Retry Test**:
   - Temporarily break backend connection
   - Perform check-in
   - Verify retry logic works
   - Fix backend
   - Verify sync succeeds

## Manual Sync Trigger

You can manually trigger sync from Settings screen:

```dart
final syncService = SyncService();
final success = await syncService.manualSync();
```

## Status Check

Get sync status for diagnostics:

```dart
final status = await SyncService().getSyncStatus();
print('Queue size: ${status['queue_size']}');
print('Last sync: ${status['last_sync']}');
```
