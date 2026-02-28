// =============================================================================
// DEVICE STATE MANAGER
// =============================================================================
// Manages lock/unlock/paid states with 100% accuracy and sync between layers
// =============================================================================

import 'dart:async';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_logger.dart';

class DeviceStateManager {
  static final DeviceStateManager _instance = DeviceStateManager._internal();

  factory DeviceStateManager() => _instance;

  DeviceStateManager._internal();

  static const String _channel = 'device.lock/channel';
  static const String _keyDeviceLocked = 'device_locked';
  static const String _keyPaidInFull = 'is_paid_in_full';
  static const String _keyLastStateSync = 'last_state_sync_ms';
  static const String _keyLockReason = 'lock_reason';

  late MethodChannel _methodChannel;

  void initialize() {
    _methodChannel = const MethodChannel(_channel);
  }

  /// Get exact lock state from native layer
  Future<bool> getActualLockState() async {
    try {
      final isLocked = await _methodChannel
          .invokeMethod<bool>('isDeviceLocked')
          .timeout(const Duration(seconds: 5));
      return isLocked ?? false;
    } on TimeoutException {
      AppLogger.log('Timeout reading native lock state');
      return false;
    } on PlatformException catch (e) {
      AppLogger.log('Error reading native lock state: $e');
      return false;
    }
  }

  /// Get exact paid-in-full state from native layer
  Future<bool> getActualPaidState() async {
    try {
      final isPaid = await _methodChannel
          .invokeMethod<bool>('isPaidInFull')
          .timeout(const Duration(seconds: 5));
      return isPaid ?? false;
    } on TimeoutException {
      AppLogger.log('Timeout reading native paid state');
      return false;
    } on PlatformException catch (e) {
      AppLogger.log('Error reading native paid state: $e');
      return false;
    }
  }

  /// Synchronize app state with native state
  /// Returns: (isLocked, isPaidInFull) from native layer
  Future<(bool, bool)> syncStateWithNative() async {
    final nativeLocked = await getActualLockState();
    final nativePaid = await getActualPaidState();

    final prefs = await SharedPreferences.getInstance();
    final persistedLocked = prefs.getBool(_keyDeviceLocked) ?? false;
    final persistedPaid = prefs.getBool(_keyPaidInFull) ?? false;

    // Update persisted state if native state differs
    if (persistedLocked != nativeLocked) {
      await prefs.setBool(_keyDeviceLocked, nativeLocked);
      AppLogger.log(
        'Lock state synced: persisted=$persistedLocked, native=$nativeLocked',
      );
    }

    if (persistedPaid != nativePaid) {
      await prefs.setBool(_keyPaidInFull, nativePaid);
      AppLogger.log(
        'Paid state synced: persisted=$persistedPaid, native=$nativePaid',
      );
    }

    // Update last sync timestamp
    await prefs.setInt(
      _keyLastStateSync,
      DateTime.now().millisecondsSinceEpoch,
    );

    return (nativeLocked, nativePaid);
  }

  /// Engage device lock (with full sync)
  /// Requires Device Owner permissions on native side
  Future<bool> engageLock({String reason = 'EMI not paid'}) async {
    try {
      AppLogger.log('Engaging device lock: reason=$reason');

      // Try to lock on native side with timeout
      final started = await _methodChannel
          .invokeMethod<bool>('startDeviceLock')
          .timeout(const Duration(seconds: 10));
      if (started != true) {
        AppLogger.log(
          'Native lock failed: Device Owner not set or policy denied',
        );
        return false;
      }

      // Update persisted state after successful native lock
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.setBool(_keyDeviceLocked, true),
        prefs.setString(_keyLockReason, reason),
        prefs.setInt(_keyLastStateSync, DateTime.now().millisecondsSinceEpoch),
      ]);

      AppLogger.log('Device lock engaged successfully');
      return true;
    } on TimeoutException {
      AppLogger.log('Timeout engaging device lock');
      return false;
    } on PlatformException catch (e) {
      AppLogger.log('Error engaging device lock: $e');
      return false;
    }
  }

  /// Disengage device lock (with full sync)
  /// Clears lock and resets EMI timer for new window
  Future<bool> disengageLock({
    bool resetTimerAnchor = true,
    DateTime? newTimerAnchor,
  }) async {
    try {
      AppLogger.log('Disengaging device lock');

      // Try to unlock on native side with timeout
      final stopped = await _methodChannel
          .invokeMethod<bool>('stopDeviceLock')
          .timeout(const Duration(seconds: 10));
      if (stopped != true) {
        AppLogger.log('Native unlock failed');
        return false;
      }

      // Update persisted state after successful native unlock
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyDeviceLocked, false);
      await prefs.remove(_keyLockReason);

      if (resetTimerAnchor) {
        // Reset EMI timer anchor to NOW for fresh window
        final anchor = newTimerAnchor ?? DateTime.now();
        await prefs.setInt('timer_anchor_ms', anchor.millisecondsSinceEpoch);
      }

      await prefs.setInt(
        _keyLastStateSync,
        DateTime.now().millisecondsSinceEpoch,
      );

      AppLogger.log('Device unlock successful');
      return true;
    } on TimeoutException {
      AppLogger.log('Timeout disengaging device lock');
      return false;
    } on PlatformException catch (e) {
      AppLogger.log('Error disengaging device lock: $e');
      return false;
    }
  }

  /// Mark device as paid in full
  /// Removes all restrictions and prevents future locking
  Future<bool> markPaidInFull() async {
    try {
      AppLogger.log('Marking device as paid in full');

      // Update native side
      await _methodChannel.invokeMethod('setPaidInFull', {'paid': true});

      // Update persisted state
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.setBool(_keyPaidInFull, true),
        prefs.setBool(_keyDeviceLocked, false),
        prefs.remove(_keyLockReason),
        prefs.remove('timer_anchor_ms'),
        prefs.remove('timer_window_days'),
        prefs.setInt(_keyLastStateSync, DateTime.now().millisecondsSinceEpoch),
      ]);

      AppLogger.log('Device marked as paid in full');
      return true;
    } on PlatformException catch (e) {
      AppLogger.log('Error marking paid in full: $e');
      return false;
    }
  }

  /// Mark device as back in EMI mode (unpaid)
  /// Re-enables timer and future locking capability
  Future<bool> markAsEmiPending({
    int windowDays = 30,
    DateTime? timerAnchor,
  }) async {
    try {
      AppLogger.log('Marking device as EMI pending: window=$windowDays days');

      // Update native side
      await _methodChannel.invokeMethod('setPaidInFull', {'paid': false});

      // Update persisted state
      final prefs = await SharedPreferences.getInstance();
      final persistedAnchorMs = prefs.getInt('timer_anchor_ms');
      final anchor =
          timerAnchor ??
          (persistedAnchorMs != null
              ? DateTime.fromMillisecondsSinceEpoch(persistedAnchorMs)
              : DateTime.now());
      await Future.wait([
        prefs.setBool(_keyPaidInFull, false),
        prefs.setBool(_keyDeviceLocked, false),
        prefs.remove(_keyLockReason),
        prefs.setInt('timer_anchor_ms', anchor.millisecondsSinceEpoch),
        prefs.setInt('timer_window_days', windowDays),
        prefs.setInt(_keyLastStateSync, DateTime.now().millisecondsSinceEpoch),
      ]);

      AppLogger.log('Device marked as EMI pending');
      return true;
    } on PlatformException catch (e) {
      AppLogger.log('Error marking as EMI pending: $e');
      return false;
    }
  }

  /// Get lock reason (why device was locked)
  Future<String?> getLockReason() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyLockReason);
  }

  /// Get when state was last synced with native layer
  Future<DateTime?> getLastStateSync() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_keyLastStateSync);
    return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }

  /// Get current state (from persisted storage, not native)
  Future<(bool isLocked, bool isPaidInFull)> getPersistedState() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      prefs.getBool(_keyDeviceLocked) ?? false,
      prefs.getBool(_keyPaidInFull) ?? false,
    );
  }

  /// Get debug state info
  Future<String> getDebugInfo() async {
    final (nativeLocked, nativePaid) = await syncStateWithNative();
    final (persistedLocked, persistedPaid) = await getPersistedState();
    final lockReason = await getLockReason();
    final lastSync = await getLastStateSync();

    return '''
Device State Debug Info:
  Native Lock State: $nativeLocked
  Native Paid State: $nativePaid
  Persisted Lock State: $persistedLocked
  Persisted Paid State: $persistedPaid
  Lock Reason: $lockReason
  Last Sync: ${lastSync?.toIso8601String() ?? 'never'}
  Current UTC: ${DateTime.now().toUtc().toIso8601String()}
  States Match: ${nativeLocked == persistedLocked && nativePaid == persistedPaid}
''';
  }
}
