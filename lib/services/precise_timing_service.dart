// =============================================================================
// PRECISE TIMING SERVICE
// =============================================================================
// Handles EMI timer calculations with millisecond precision, no rounding errors
// =============================================================================

import 'package:shared_preferences/shared_preferences.dart';
import 'app_logger.dart';

class PreciseTimingService {
  static final PreciseTimingService _instance =
      PreciseTimingService._internal();

  factory PreciseTimingService() => _instance;

  PreciseTimingService._internal();

  static const String _keyAnchorTime = 'timer_anchor_ms';
  static const String _keyWindowDays = 'timer_window_days';
  static const String _keyLockTimestamp = 'lock_timestamp_ms';

  /// Initialize timer with anchor time (when EMI window started)
  /// anchor: the moment the EMI window started
  Future<void> initializeTimer({
    required int windowDays,
    DateTime? anchor,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final effectiveAnchor =
        anchor ?? DateTime.now().toUtc(); // Use current time if not provided
    final anchorMs = effectiveAnchor.millisecondsSinceEpoch;

    await Future.wait([
      prefs.setInt(_keyAnchorTime, anchorMs),
      prefs.setInt(_keyWindowDays, windowDays),
    ]);

    AppLogger.log(
      'Timer initialized: window=$windowDays days, anchor=${effectiveAnchor.toIso8601String()}',
    );
  }

  /// Get remaining days with millisecond precision
  /// Returns: (remaining_days, remaining_seconds_within_current_day)
  Future<(int, int)> getRemainingDaysAndSeconds() async {
    final prefs = await SharedPreferences.getInstance();
    final anchorMs = prefs.getInt(_keyAnchorTime);
    final windowDays = prefs.getInt(_keyWindowDays);

    if (anchorMs == null || windowDays == null) {
      return (windowDays ?? 30, 0);
    }

    final anchor = DateTime.fromMillisecondsSinceEpoch(anchorMs);
    final now = DateTime.now().toUtc();
    final elapsedMs = now.millisecondsSinceEpoch - anchor.millisecondsSinceEpoch;
    const msPerDay = 24 * 60 * 60 * 1000;

    final elapsedDays = (elapsedMs / msPerDay).floor();
    final remainingDays = (windowDays - elapsedDays).clamp(0, windowDays);
    final secondsInCurrentDay = ((elapsedMs % msPerDay) ~/ 1000).toInt();

    return (remainingDays, secondsInCurrentDay);
  }

  /// Get exact remaining time as DateTime
  Future<DateTime?> getRemainingDeadline() async {
    final prefs = await SharedPreferences.getInstance();
    final anchorMs = prefs.getInt(_keyAnchorTime);
    final windowDays = prefs.getInt(_keyWindowDays);

    if (anchorMs == null || windowDays == null) return null;

    final anchor = DateTime.fromMillisecondsSinceEpoch(anchorMs);
    return anchor.add(Duration(days: windowDays));
  }

  /// Check if timer has expired
  Future<bool> hasExpired() async {
    final (remaining, _) = await getRemainingDaysAndSeconds();
    return remaining <= 0;
  }

  /// Extend EMI window by adding days (keeps anchor, increases window)
  Future<void> extendWindow(int additionalDays) async {
    final prefs = await SharedPreferences.getInstance();
    final currentWindow = prefs.getInt(_keyWindowDays) ?? 30;
    final newWindow = currentWindow + additionalDays;

    await prefs.setInt(_keyWindowDays, newWindow);
    AppLogger.log('EMI window extended: +$additionalDays days (total: $newWindow)');
  }

  /// Reset timer (used when payment is made but device still in EMI)
  Future<void> resetTimer(int windowDays) async {
    final prefs = await SharedPreferences.getInstance();
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    await Future.wait([
      prefs.setInt(_keyAnchorTime, nowMs),
      prefs.setInt(_keyWindowDays, windowDays),
      prefs.remove(_keyLockTimestamp),
    ]);

    AppLogger.log('Timer reset: window=$windowDays days');
  }

  /// Mark device as locked (for status tracking)
  Future<void> markAsLocked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _keyLockTimestamp,
      DateTime.now().millisecondsSinceEpoch,
    );
    AppLogger.log('Device marked as locked at ${DateTime.now().toIso8601String()}');
  }

  /// Get when device was locked
  Future<DateTime?> getLockTime() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_keyLockTimestamp);
    return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }

  /// Clear all timer data (for testing or reset)
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove(_keyAnchorTime),
      prefs.remove(_keyWindowDays),
      prefs.remove(_keyLockTimestamp),
    ]);
    AppLogger.log('Timer data cleared');
  }

  /// Sync server-provided remaining days (for accurate sync with backend)
  /// This ensures the app stays in sync with server calculations
  Future<void> syncWithServerRemainingDays(
    int serverRemainingDays, {
    DateTime? referenceTime,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final currentWindow = prefs.getInt(_keyWindowDays) ?? 30;

    // Create new anchor based on server's remaining days
    final reference = referenceTime ?? DateTime.now().toUtc();
    final newAnchor = reference.subtract(
      Duration(days: currentWindow - serverRemainingDays),
    );

    await prefs.setInt(_keyAnchorTime, newAnchor.millisecondsSinceEpoch);

    AppLogger.log(
      'Timer synced with server: remaining=$serverRemainingDays days, window=$currentWindow days',
    );
  }

  /// Get debug info about current timer state
  Future<String> getDebugInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final anchorMs = prefs.getInt(_keyAnchorTime);
    final windowDays = prefs.getInt(_keyWindowDays);
    final lockMs = prefs.getInt(_keyLockTimestamp);

    if (anchorMs == null) {
      return 'Timer not initialized';
    }

    final anchor = DateTime.fromMillisecondsSinceEpoch(anchorMs);
    final (remaining, secondsInDay) = await getRemainingDaysAndSeconds();
    final deadline = await getRemainingDeadline();
    final lockTime = lockMs != null
        ? DateTime.fromMillisecondsSinceEpoch(lockMs).toIso8601String()
        : 'not locked';

    return '''
Timer Debug Info:
  Window: $windowDays days
  Anchor: ${anchor.toIso8601String()}
  Deadline: ${deadline?.toIso8601String()}
  Remaining: $remaining days, ${(secondsInDay / 3600).toStringAsFixed(2)} hours
  Locked at: $lockTime
  Current UTC: ${DateTime.now().toUtc().toIso8601String()}
''';
  }
}
