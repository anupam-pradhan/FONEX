import 'package:flutter/foundation.dart';

/// A simple in-app logger to capture debug logs
/// so they can be viewed without USB debugging.
class AppLogger {
  static final List<String> _logs = [];

  // To notify listeners when new logs arrive
  static final ValueNotifier<int> logUpdateNotifier = ValueNotifier<int>(0);

  static void log(String message) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    final logMessage = '[$timestamp] $message';

    _logs.add(logMessage);

    // Keep only the last 500 logs to prevent memory issues
    if (_logs.length > 500) {
      _logs.removeAt(0);
    }

    // Also print to standard console if connected
    debugPrint(logMessage);

    // Notify listeners
    logUpdateNotifier.value++;
  }

  static List<String> get logs => List.unmodifiable(_logs);

  static String toMultilineText() => _logs.join('\n');

  static void clear() {
    _logs.clear();
    logUpdateNotifier.value++;
  }
}
