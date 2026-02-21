// =============================================================================
// DEVICE STORAGE SERVICE
// =============================================================================
// Handles local storage of device registration info and sync state
// Uses SharedPreferences for reliable, fast local storage
// =============================================================================

import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class DeviceStorageService {
  static const String _keyDeviceRegistered = 'device_registered';
  static const String _keyDeviceHash = 'device_hash_stored';
  static const String _keyImei = 'device_imei_stored';
  static const String _keyDeviceMetadata = 'device_metadata';
  static const String _keyRegistrationTimestamp = 'registration_timestamp';
  static const String _keyLastSyncTimestamp = 'last_sync_timestamp';
  static const String _keySyncQueue = 'sync_queue';
  static const String _keyFailedSyncs = 'failed_syncs';
  static const String _keyIsFirstRegistration = 'is_first_registration';

  // ===========================================================================
  // DEVICE REGISTRATION INFO
  // ===========================================================================

  /// Check if device is registered locally
  static Future<bool> isDeviceRegistered() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyDeviceRegistered) ?? false;
  }

  /// Save device registration info (auto-called on first registration)
  static Future<void> saveDeviceRegistration({
    required String deviceHash,
    required String imei,
    required Map<String, dynamic> metadata,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setBool(_keyDeviceRegistered, true),
      prefs.setString(_keyDeviceHash, deviceHash),
      prefs.setString(_keyImei, imei),
      prefs.setString(_keyDeviceMetadata, jsonEncode(metadata)),
      prefs.setInt(_keyRegistrationTimestamp, DateTime.now().millisecondsSinceEpoch),
      prefs.setBool(_keyIsFirstRegistration, true),
    ]);
  }

  /// Get stored device hash
  static Future<String?> getStoredDeviceHash() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyDeviceHash);
  }

  /// Get stored IMEI
  static Future<String?> getStoredImei() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyImei);
  }

  /// Get stored device metadata
  static Future<Map<String, dynamic>?> getStoredMetadata() async {
    final prefs = await SharedPreferences.getInstance();
    final metadataStr = prefs.getString(_keyDeviceMetadata);
    if (metadataStr == null) return null;
    try {
      return jsonDecode(metadataStr) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// Check if this is first registration
  static Future<bool> isFirstRegistration() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyIsFirstRegistration) ?? false;
  }

  /// Mark first registration as complete
  static Future<void> markFirstRegistrationComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsFirstRegistration, false);
  }

  // ===========================================================================
  // SYNC STATE MANAGEMENT
  // ===========================================================================

  /// Update last sync timestamp
  static Future<void> updateLastSyncTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyLastSyncTimestamp, DateTime.now().millisecondsSinceEpoch);
  }

  /// Get last sync timestamp
  static Future<DateTime?> getLastSyncTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt(_keyLastSyncTimestamp);
    if (timestamp == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  // ===========================================================================
  // SYNC QUEUE MANAGEMENT (for offline/retry scenarios)
  // ===========================================================================

  /// Add sync operation to queue
  static Future<void> addToSyncQueue(Map<String, dynamic> syncData) async {
    final prefs = await SharedPreferences.getInstance();
    final queueStr = prefs.getString(_keySyncQueue) ?? '[]';
    try {
      final queue = jsonDecode(queueStr) as List<dynamic>;
      queue.add({
        ...syncData,
        'timestamp': DateTime.now().toIso8601String(),
        'retry_count': 0,
      });
      // Keep only last 100 items to prevent storage bloat
      if (queue.length > 100) {
        queue.removeRange(0, queue.length - 100);
      }
      await prefs.setString(_keySyncQueue, jsonEncode(queue));
    } catch (e) {
      // If queue is corrupted, reset it
      await prefs.setString(_keySyncQueue, jsonEncode([syncData]));
    }
  }

  /// Get sync queue
  static Future<List<Map<String, dynamic>>> getSyncQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final queueStr = prefs.getString(_keySyncQueue) ?? '[]';
    try {
      final queue = jsonDecode(queueStr) as List<dynamic>;
      return queue.map((e) => e as Map<String, dynamic>).toList();
    } catch (e) {
      return [];
    }
  }

  /// Remove item from sync queue
  static Future<void> removeFromSyncQueue(int index) async {
    final prefs = await SharedPreferences.getInstance();
    final queueStr = prefs.getString(_keySyncQueue) ?? '[]';
    try {
      final queue = jsonDecode(queueStr) as List<dynamic>;
      if (index >= 0 && index < queue.length) {
        queue.removeAt(index);
        await prefs.setString(_keySyncQueue, jsonEncode(queue));
      }
    } catch (e) {
      // Reset queue on error
      await prefs.setString(_keySyncQueue, '[]');
    }
  }

  /// Clear sync queue
  static Future<void> clearSyncQueue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keySyncQueue);
  }

  /// Increment retry count for a queue item
  static Future<void> incrementRetryCount(int index) async {
    final prefs = await SharedPreferences.getInstance();
    final queueStr = prefs.getString(_keySyncQueue) ?? '[]';
    try {
      final queue = jsonDecode(queueStr) as List<dynamic>;
      if (index >= 0 && index < queue.length) {
        final item = queue[index] as Map<String, dynamic>;
        item['retry_count'] = (item['retry_count'] as int? ?? 0) + 1;
        await prefs.setString(_keySyncQueue, jsonEncode(queue));
      }
    } catch (e) {
      // Ignore errors
    }
  }

  // ===========================================================================
  // FAILED SYNC TRACKING
  // ===========================================================================

  /// Track failed sync attempt
  static Future<void> trackFailedSync(String reason) async {
    final prefs = await SharedPreferences.getInstance();
    final failedStr = prefs.getString(_keyFailedSyncs) ?? '[]';
    try {
      final failed = jsonDecode(failedStr) as List<dynamic>;
      failed.add({
        'reason': reason,
        'timestamp': DateTime.now().toIso8601String(),
      });
      // Keep only last 50 failures
      if (failed.length > 50) {
        failed.removeRange(0, failed.length - 50);
      }
      await prefs.setString(_keyFailedSyncs, jsonEncode(failed));
    } catch (e) {
      await prefs.setString(_keyFailedSyncs, jsonEncode([{
        'reason': reason,
        'timestamp': DateTime.now().toIso8601String(),
      }]));
    }
  }

  /// Get failed sync count (for diagnostics)
  static Future<int> getFailedSyncCount() async {
    final prefs = await SharedPreferences.getInstance();
    final failedStr = prefs.getString(_keyFailedSyncs) ?? '[]';
    try {
      final failed = jsonDecode(failedStr) as List<dynamic>;
      return failed.length;
    } catch (e) {
      return 0;
    }
  }

  /// Clear failed sync history
  static Future<void> clearFailedSyncs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyFailedSyncs);
  }

  // ===========================================================================
  // UTILITY METHODS
  // ===========================================================================

  /// Get all stored device info
  static Future<Map<String, dynamic>> getAllDeviceInfo() async {
    return {
      'is_registered': await isDeviceRegistered(),
      'device_hash': await getStoredDeviceHash(),
      'imei': await getStoredImei(),
      'metadata': await getStoredMetadata(),
      'registration_timestamp': await _getRegistrationTimestamp(),
      'last_sync': await getLastSyncTimestamp(),
      'is_first_registration': await isFirstRegistration(),
    };
  }

  static Future<DateTime?> _getRegistrationTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt(_keyRegistrationTimestamp);
    if (timestamp == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  /// Clear all device data (for testing/reset)
  static Future<void> clearAllData() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove(_keyDeviceRegistered),
      prefs.remove(_keyDeviceHash),
      prefs.remove(_keyImei),
      prefs.remove(_keyDeviceMetadata),
      prefs.remove(_keyRegistrationTimestamp),
      prefs.remove(_keyLastSyncTimestamp),
      prefs.remove(_keySyncQueue),
      prefs.remove(_keyFailedSyncs),
      prefs.remove(_keyIsFirstRegistration),
    ]);
  }
}
