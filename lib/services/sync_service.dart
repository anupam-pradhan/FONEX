// =============================================================================
// OPTIMIZED SYNC SERVICE
// =============================================================================
// Enterprise-level sync service with queue, retry, and batch operations
// Handles offline scenarios, network failures, and server errors gracefully
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../config.dart';
import 'device_storage_service.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  Timer? _syncTimer;
  bool _isSyncing = false;
  final int _maxRetries = 3;
  final int _syncIntervalSeconds = 300; // 5 minutes default
  final int _batchSize = 10; // Process 10 items at a time

  // ===========================================================================
  // INITIALIZATION & LIFECYCLE
  // ===========================================================================

  /// Initialize sync service and start periodic sync
  void initialize() {
    _startPeriodicSync();
    // Process any pending queue items
    _processSyncQueue();
  }

  /// Stop sync service
  void dispose() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  /// Start periodic sync timer
  void _startPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(
      Duration(seconds: _syncIntervalSeconds),
      (_) => _processSyncQueue(),
    );
  }

  // ===========================================================================
  // DEVICE REGISTRATION & CHECK-IN
  // ===========================================================================

  /// Register device on first check-in (auto-save to local DB)
  /// Returns true if registration was successful
  Future<bool> registerDevice({
    required String deviceHash,
    required String imei,
    required Map<String, dynamic> metadata,
  }) async {
    try {
      // Check if already registered locally
      final isRegistered = await DeviceStorageService.isDeviceRegistered();
      
      if (!isRegistered) {
        // Save to local storage first (offline-first approach)
        await DeviceStorageService.saveDeviceRegistration(
          deviceHash: deviceHash,
          imei: imei,
          metadata: metadata,
        );
        debugPrint('✅ Device registration saved locally');
      }

      // Try to sync with server
      final syncSuccess = await _syncRegistrationToServer(
        deviceHash: deviceHash,
        imei: imei,
        metadata: metadata,
      );

      if (syncSuccess) {
        await DeviceStorageService.markFirstRegistrationComplete();
        await DeviceStorageService.updateLastSyncTimestamp();
        debugPrint('✅ Device registration synced to server');
        return true;
      } else {
        // If sync fails, queue it for later retry
        await DeviceStorageService.addToSyncQueue({
          'type': 'registration',
          'device_hash': deviceHash,
          'imei': imei,
          'metadata': metadata,
        });
        debugPrint('⚠️ Device registration queued for retry');
        return false; // Will retry later
      }
    } catch (e) {
      debugPrint('❌ Error during device registration: $e');
      await DeviceStorageService.trackFailedSync('Registration error: $e');
      return false;
    }
  }

  /// Sync registration to server
  Future<bool> _syncRegistrationToServer({
    required String deviceHash,
    required String imei,
    required Map<String, dynamic> metadata,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${FonexConfig.serverBaseUrl}/checkin'),
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'FONEX-Device/1.0',
        },
        body: jsonEncode({
          'device_hash': deviceHash,
          'imei': imei,
          'is_locked': false,
          'days_remaining': FonexConfig.lockAfterDays,
          'metadata': metadata,
          'timestamp': DateTime.now().toIso8601String(),
          'is_first_registration': true, // Flag for backend
        }),
      ).timeout(Duration(seconds: FonexConfig.apiTimeoutSeconds));

      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      } else {
        debugPrint('Server returned status: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('Network error during registration sync: $e');
      return false;
    }
  }

  /// Perform device check-in with optimized retry logic
  Future<Map<String, dynamic>?> performCheckIn({
    required String deviceHash,
    required String imei,
    required bool isLocked,
    required int daysRemaining,
    required Map<String, dynamic> metadata,
  }) async {
    // Ensure device is registered locally first
    final isRegistered = await DeviceStorageService.isDeviceRegistered();
    if (!isRegistered) {
      // Auto-register if not registered
      await registerDevice(
        deviceHash: deviceHash,
        imei: imei,
        metadata: metadata,
      );
    }

    // Perform check-in with retry logic
    for (int attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        final response = await http.post(
          Uri.parse('${FonexConfig.serverBaseUrl}/checkin'),
          headers: {
            'Content-Type': 'application/json',
            'User-Agent': 'FONEX-Device/1.0',
          },
          body: jsonEncode({
            'device_hash': deviceHash,
            'imei': imei,
            'is_locked': isLocked,
            'days_remaining': daysRemaining,
            'metadata': metadata,
            'timestamp': DateTime.now().toIso8601String(),
          }),
        ).timeout(Duration(seconds: FonexConfig.apiTimeoutSeconds));

        if (response.statusCode == 200) {
          await DeviceStorageService.updateLastSyncTimestamp();
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          return data;
        } else if (response.statusCode >= 500 && attempt < _maxRetries - 1) {
          // Retry on server errors with exponential backoff
          await Future.delayed(Duration(seconds: (attempt + 1) * 2));
          continue;
        } else {
          // Queue for later retry
          await DeviceStorageService.addToSyncQueue({
            'type': 'checkin',
            'device_hash': deviceHash,
            'imei': imei,
            'is_locked': isLocked,
            'days_remaining': daysRemaining,
            'metadata': metadata,
          });
          return null;
        }
      } catch (e) {
        if (attempt < _maxRetries - 1) {
          // Retry with exponential backoff
          await Future.delayed(Duration(seconds: (attempt + 1) * 2));
          continue;
        } else {
          // Queue for later retry
          await DeviceStorageService.addToSyncQueue({
            'type': 'checkin',
            'device_hash': deviceHash,
            'imei': imei,
            'is_locked': isLocked,
            'days_remaining': daysRemaining,
            'metadata': metadata,
          });
          await DeviceStorageService.trackFailedSync('Check-in error: $e');
          return null;
        }
      }
    }
    return null;
  }

  // ===========================================================================
  // SYNC QUEUE PROCESSING
  // ===========================================================================

  /// Process pending sync queue items
  Future<void> _processSyncQueue() async {
    if (_isSyncing) {
      debugPrint('⏳ Sync already in progress, skipping...');
      return;
    }

    _isSyncing = true;
    try {
      final queue = await DeviceStorageService.getSyncQueue();
      if (queue.isEmpty) {
        return;
      }

      debugPrint('📤 Processing sync queue: ${queue.length} items');

      // Process items in batches
      final batches = <List<Map<String, dynamic>>>[];
      for (int i = 0; i < queue.length; i += _batchSize) {
        final end = (i + _batchSize < queue.length) ? i + _batchSize : queue.length;
        batches.add(queue.sublist(i, end));
      }

      for (int batchIndex = 0; batchIndex < batches.length; batchIndex++) {
        final batch = batches[batchIndex];
        await _processBatch(batch, batchIndex * _batchSize);
        // Small delay between batches to avoid overwhelming server
        if (batchIndex < batches.length - 1) {
          await Future.delayed(Duration(milliseconds: 500));
        }
      }
    } catch (e) {
      debugPrint('❌ Error processing sync queue: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Process a batch of sync items
  Future<void> _processBatch(
    List<Map<String, dynamic>> batch,
    int startIndex,
  ) async {
    for (int i = 0; i < batch.length; i++) {
      final item = batch[i];
      final queueIndex = startIndex + i;
      final retryCount = item['retry_count'] as int? ?? 0;

      // Skip if retried too many times
      if (retryCount >= _maxRetries) {
        debugPrint('⚠️ Skipping item after $retryCount retries');
        await DeviceStorageService.removeFromSyncQueue(queueIndex);
        continue;
      }

      try {
        final type = item['type'] as String? ?? 'checkin';
        bool success = false;

        if (type == 'registration') {
          success = await _syncRegistrationToServer(
            deviceHash: item['device_hash'] as String,
            imei: item['imei'] as String,
            metadata: item['metadata'] as Map<String, dynamic>? ?? {},
          );
        } else if (type == 'checkin') {
          final result = await performCheckIn(
            deviceHash: item['device_hash'] as String,
            imei: item['imei'] as String,
            isLocked: item['is_locked'] as bool? ?? false,
            daysRemaining: item['days_remaining'] as int? ?? 0,
            metadata: item['metadata'] as Map<String, dynamic>? ?? {},
          );
          success = result != null;
        }

        if (success) {
          await DeviceStorageService.removeFromSyncQueue(queueIndex);
          debugPrint('✅ Synced item: $type');
        } else {
          await DeviceStorageService.incrementRetryCount(queueIndex);
        }
      } catch (e) {
        debugPrint('❌ Error syncing item: $e');
        await DeviceStorageService.incrementRetryCount(queueIndex);
      }
    }
  }

  // ===========================================================================
  // MANUAL SYNC TRIGGERS
  // ===========================================================================

  /// Manually trigger sync (called from UI)
  Future<bool> manualSync() async {
    debugPrint('🔄 Manual sync triggered');
    await _processSyncQueue();
    final queue = await DeviceStorageService.getSyncQueue();
    return queue.isEmpty;
  }

  /// Force sync registration (for testing/recovery)
  Future<bool> forceSyncRegistration() async {
    final deviceHash = await DeviceStorageService.getStoredDeviceHash();
    final imei = await DeviceStorageService.getStoredImei();
    final metadata = await DeviceStorageService.getStoredMetadata();

    if (deviceHash == null || imei == null) {
      return false;
    }

    return await _syncRegistrationToServer(
      deviceHash: deviceHash,
      imei: imei,
      metadata: metadata ?? {},
    );
  }

  // ===========================================================================
  // STATUS & DIAGNOSTICS
  // ===========================================================================

  /// Get sync status
  Future<Map<String, dynamic>> getSyncStatus() async {
    final queue = await DeviceStorageService.getSyncQueue();
    final lastSync = await DeviceStorageService.getLastSyncTimestamp();
    final failedCount = await DeviceStorageService.getFailedSyncCount();
    final isRegistered = await DeviceStorageService.isDeviceRegistered();

    return {
      'is_registered': isRegistered,
      'queue_size': queue.length,
      'last_sync': lastSync?.toIso8601String(),
      'failed_syncs': failedCount,
      'is_syncing': _isSyncing,
    };
  }
}
