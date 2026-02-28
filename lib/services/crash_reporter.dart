import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_logger.dart';

class CrashReporter {
  static const String _keyCrashEvents = 'crash_events_v1';
  static const int _maxCrashEvents = 80;
  static bool _initialized = false;

  static final ValueNotifier<int> crashCountNotifier = ValueNotifier<int>(0);

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await _refreshCrashCount();

    final previousHandler = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      unawaited(
        _record(
          source: 'flutter_error',
          message: details.exceptionAsString(),
          stack: details.stack,
          fatal: true,
        ),
      );
      previousHandler?.call(details);
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      unawaited(
        _record(
          source: 'platform_error',
          message: error.toString(),
          stack: stack,
          fatal: true,
        ),
      );
      return true;
    };
  }

  static void recordZoneError(Object error, StackTrace stack) {
    unawaited(
      _record(
        source: 'zone_error',
        message: error.toString(),
        stack: stack,
        fatal: true,
      ),
    );
  }

  static Future<void> recordNonFatal({
    required String source,
    required String message,
    StackTrace? stack,
  }) async {
    await _record(source: source, message: message, stack: stack, fatal: false);
  }

  static Future<List<Map<String, dynamic>>> getRecentEvents({
    int limit = 20,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyCrashEvents);
    if (raw == null || raw.trim().isEmpty) return <Map<String, dynamic>>[];
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! List) return <Map<String, dynamic>>[];
      return parsed
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false)
          .reversed
          .take(limit)
          .toList(growable: false);
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  static Future<void> clearEvents() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyCrashEvents);
    crashCountNotifier.value = 0;
  }

  static Future<void> _record({
    required String source,
    required String message,
    StackTrace? stack,
    required bool fatal,
  }) async {
    final now = DateTime.now();
    final event = <String, dynamic>{
      'ts': now.toUtc().toIso8601String(),
      'source': source,
      'fatal': fatal,
      'message': _truncate(message, 1200),
      'stack': _truncate(stack?.toString() ?? '', 2400),
    };

    AppLogger.log(
      'CRASH_CAPTURED[$source][fatal=$fatal]: ${_truncate(message, 240)}',
    );

    final prefs = await SharedPreferences.getInstance();
    List<dynamic> list = <dynamic>[];
    final raw = prefs.getString(_keyCrashEvents);
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) list = decoded;
      } catch (_) {
        list = <dynamic>[];
      }
    }
    list.add(event);
    if (list.length > _maxCrashEvents) {
      list = list.sublist(list.length - _maxCrashEvents);
    }
    await prefs.setString(_keyCrashEvents, jsonEncode(list));
    crashCountNotifier.value = list.length;
  }

  static Future<void> _refreshCrashCount() async {
    final events = await getRecentEvents(limit: _maxCrashEvents);
    crashCountNotifier.value = events.length;
  }

  static String _truncate(String value, int maxLength) {
    if (value.length <= maxLength) return value;
    return '${value.substring(0, maxLength)}...';
  }
}
