// =============================================================================
// OPTIMIZED SYNC SERVICE
// =============================================================================
// Enterprise-level sync service with queue, retry, and batch operations
// Handles offline scenarios, network failures, and server errors gracefully
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'package:fonex/services/app_logger.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import 'device_storage_service.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  Timer? _syncTimer;
  bool _isSyncing = false;
  bool _isProcessingFromQueue = false;
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
        AppLogger.log('✅ Device registration saved locally');
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
        AppLogger.log('✅ Device registration synced to server');
        return true;
      } else {
        // If sync fails, queue it for later retry
        await DeviceStorageService.addToSyncQueue({
          'type': 'registration',
          'device_hash': deviceHash,
          'imei': imei,
          'metadata': metadata,
        });
        AppLogger.log('⚠️ Device registration queued for retry');
        return false; // Will retry later
      }
    } catch (e) {
      AppLogger.log('❌ Error during device registration: $e');
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
      final response = await http
          .post(
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
          )
          .timeout(Duration(seconds: FonexConfig.apiTimeoutSeconds));

      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      } else {
        AppLogger.log('Server returned status: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      AppLogger.log('Network error during registration sync: $e');
      return false;
    }
  }

  Future<void> _queueCheckInForRetry({
    required String deviceHash,
    required String imei,
    required DateTime lastSeenAt,
    String? deviceId,
    int? batteryLevel,
    bool? isLocked,
    int? daysRemaining,
    Map<String, dynamic>? metadata,
  }) async {
    if (_isProcessingFromQueue) return;
    final queueItem = <String, dynamic>{
      'type': 'checkin',
      'device_hash': deviceHash,
      'imei': imei,
      'last_seen': lastSeenAt.toIso8601String(),
      if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
      if (batteryLevel != null) 'battery': batteryLevel,
      if (isLocked != null) 'is_locked': isLocked,
      if (daysRemaining != null) 'days_remaining': daysRemaining,
      if (metadata != null && metadata.isNotEmpty) 'metadata': metadata,
    };
    await DeviceStorageService.addToSyncQueue(queueItem);
  }

  /// Perform device check-in with optimized retry logic
  Future<Map<String, dynamic>?> performCheckIn({
    required String deviceHash,
    required String imei,
    String? deviceId,
    int? batteryLevel,
    DateTime? lastSeen,
    bool? isLocked,
    int? daysRemaining,
    Map<String, dynamic>? metadata,
  }) async {
    final checkinUri = Uri.parse('${FonexConfig.serverBaseUrl}/checkin');

    // Ensure device is registered locally first
    final isRegistered = await DeviceStorageService.isDeviceRegistered();
    if (!isRegistered) {
      // Auto-register if not registered
      await registerDevice(
        deviceHash: deviceHash,
        imei: imei,
        metadata: metadata ?? {},
      );
    }

    // Perform check-in with retry logic
    for (int attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        final payload = <String, dynamic>{
          'device_hash': deviceHash,
          if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
          'imei': imei,
          'battery': batteryLevel,
          'last_seen': (lastSeen ?? DateTime.now()).toIso8601String(),
          'timestamp': DateTime.now().toIso8601String(),
        };
        if (isLocked != null) payload['is_locked'] = isLocked;
        if (daysRemaining != null) payload['days_remaining'] = daysRemaining;
        if (metadata != null && metadata.isNotEmpty) {
          payload['metadata'] = metadata;
        }

        AppLogger.log(
          'Check-in request attempt ${attempt + 1}/$_maxRetries: '
          'url=$checkinUri body=${jsonEncode(payload)}',
        );
        final response = await http
            .post(
              checkinUri,
              headers: {
                'Content-Type': 'application/json',
                'User-Agent': 'FONEX-Device/1.0',
              },
              body: jsonEncode(payload),
            )
            .timeout(Duration(seconds: FonexConfig.apiTimeoutSeconds));
        AppLogger.log(
          'Check-in response attempt ${attempt + 1}/$_maxRetries: '
          'status=${response.statusCode} body=${response.body}',
        );

        if (response.statusCode == 200) {
          await DeviceStorageService.updateLastSyncTimestamp();
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          return data;
        } else if (response.statusCode >= 500 && attempt < _maxRetries - 1) {
          // Retry on server errors with exponential backoff
          await Future.delayed(Duration(seconds: (attempt + 1) * 2));
          continue;
        } else {
          // Queue for later retry — but not if we're already processing from queue
          await _queueCheckInForRetry(
            deviceHash: deviceHash,
            imei: imei,
            lastSeenAt: lastSeen ?? DateTime.now(),
            deviceId: deviceId,
            batteryLevel: batteryLevel,
            isLocked: isLocked,
            daysRemaining: daysRemaining,
            metadata: metadata,
          );
          AppLogger.log(
            'Check-in queued after non-2xx response: status=${response.statusCode}',
          );
          return null;
        }
      } catch (e) {
        AppLogger.log(
          'Check-in request exception attempt ${attempt + 1}/$_maxRetries: $e',
        );
        if (attempt < _maxRetries - 1) {
          // Retry with exponential backoff
          await Future.delayed(Duration(seconds: (attempt + 1) * 2));
          continue;
        } else {
          // Queue for later retry — but not if we're already processing from queue
          await _queueCheckInForRetry(
            deviceHash: deviceHash,
            imei: imei,
            lastSeenAt: lastSeen ?? DateTime.now(),
            deviceId: deviceId,
            batteryLevel: batteryLevel,
            isLocked: isLocked,
            daysRemaining: daysRemaining,
            metadata: metadata,
          );
          if (!_isProcessingFromQueue) {
            await DeviceStorageService.trackFailedSync('Check-in error: $e');
          }
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
      AppLogger.log('⏳ Sync already in progress, skipping...');
      return;
    }

    _isSyncing = true;
    try {
      final queue = await DeviceStorageService.getSyncQueue();
      if (queue.isEmpty) {
        return;
      }

      AppLogger.log('📤 Processing sync queue: ${queue.length} items');

      // Process items in batches
      final batches = <List<Map<String, dynamic>>>[];
      for (int i = 0; i < queue.length; i += _batchSize) {
        final end = (i + _batchSize < queue.length)
            ? i + _batchSize
            : queue.length;
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
      AppLogger.log('❌ Error processing sync queue: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Process a batch of sync items
  Future<void> _processBatch(
    List<Map<String, dynamic>> batch,
    int startIndex,
  ) async {
    _isProcessingFromQueue = true;
    final indicesToRemove = <int>[];
    final indicesToRetry = <int>[];

    try {
      for (int i = 0; i < batch.length; i++) {
        final item = batch[i];
        final queueIndex = startIndex + i;
        final retryCount = item['retry_count'] as int? ?? 0;

        // Skip if retried too many times
        if (retryCount >= _maxRetries) {
          AppLogger.log('⚠️ Skipping item after $retryCount retries');
          indicesToRemove.add(queueIndex);
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
            final rawLastSeen = item['last_seen'] as String?;
            final result = await performCheckIn(
              deviceHash: item['device_hash'] as String,
              imei: item['imei'] as String,
              deviceId: item['device_id'] as String?,
              batteryLevel: item['battery'] as int?,
              lastSeen: rawLastSeen != null
                  ? DateTime.tryParse(rawLastSeen)
                  : null,
              isLocked: item['is_locked'] as bool?,
              daysRemaining: item['days_remaining'] as int?,
              metadata: item['metadata'] as Map<String, dynamic>? ?? {},
            );
            success = result != null;
          }

          if (success) {
            indicesToRemove.add(queueIndex);
            AppLogger.log('✅ Synced item: $type');
          } else {
            indicesToRetry.add(queueIndex);
          }
        } catch (e) {
          AppLogger.log('❌ Error syncing item: $e');
          indicesToRetry.add(queueIndex);
        }
      }

      // Apply queue mutations from highest index to lowest, so each operation
      // remains valid even when remove and retry targets overlap in one batch.
      final actionByIndex = <int, bool>{}; // true=remove, false=retry
      for (final idx in indicesToRetry) {
        actionByIndex[idx] = false;
      }
      for (final idx in indicesToRemove) {
        actionByIndex[idx] = true;
      }
      final sortedIndices = actionByIndex.keys.toList()
        ..sort((a, b) => b.compareTo(a));
      for (final idx in sortedIndices) {
        if (actionByIndex[idx] == true) {
          await DeviceStorageService.removeFromSyncQueue(idx);
        } else {
          await DeviceStorageService.incrementRetryCount(idx);
        }
      }
    } finally {
      _isProcessingFromQueue = false;
    }
  }

  // ===========================================================================
  // MANUAL SYNC TRIGGERS
  // ===========================================================================

  /// Manually trigger sync (called from UI)
  Future<bool> manualSync() async {
    AppLogger.log('🔄 Manual sync triggered');
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
