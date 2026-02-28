import 'package:flutter/foundation.dart';

/// A simple in-app logger to capture debug logs
/// so they can be viewed without USB debugging.
class AppLogger {
  static const int _maxLogs = 800;
  static const int _maxBufferedChars = 120000;
  static final List<String> _logs = [];
  static int _bufferedChars = 0;

  // To notify listeners when new logs arrive
  static final ValueNotifier<int> logUpdateNotifier = ValueNotifier<int>(0);

  static void log(String message) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    final logMessage = '[$timestamp] $message';

    _logs.add(logMessage);
    _bufferedChars += logMessage.length;

    // Guardrail: bound log count and memory footprint to reduce lag.
    while (_logs.length > _maxLogs || _bufferedChars > _maxBufferedChars) {
      final removed = _logs.removeAt(0);
      _bufferedChars -= removed.length;
      if (_bufferedChars < 0) _bufferedChars = 0;
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
    _bufferedChars = 0;
    logUpdateNotifier.value++;
  }
}
