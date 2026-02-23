import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

class DeviceRealtimeCommand {
  const DeviceRealtimeCommand({
    required this.commandId,
    required this.command,
    required this.deviceId,
    required this.rawRecord,
  });

  final String commandId;
  final String command;
  final String deviceId;
  final Map<String, dynamic> rawRecord;
}

class RealtimeCommandService {
  RealtimeCommandService._internal();
  static final RealtimeCommandService _instance =
      RealtimeCommandService._internal();
  factory RealtimeCommandService() => _instance;

  static const String _processedCommandIdsKey = 'processed_command_ids';
  static const int _maxProcessedCommands = 200;

  RealtimeChannel? _channel;
  StreamSubscription<dynamic>? _connectivitySubscription;
  Timer? _reconnectTimer;

  bool _isStarted = false;
  bool _isReconnecting = false;
  String? _deviceId;
  Future<void> Function(DeviceRealtimeCommand command)? _commandHandler;

  final Set<String> _processedCommandIds = <String>{};
  final Set<String> _inFlightCommandIds = <String>{};

  bool get isStarted => _isStarted;

  Future<void> start({
    required String deviceId,
    required Future<void> Function(DeviceRealtimeCommand command) onCommand,
  }) async {
    if (_isStarted) return;

    if (deviceId.isEmpty) {
      debugPrint('Realtime disabled: empty device id');
      return;
    }
    if (FonexConfig.supabaseUrl.isEmpty ||
        FonexConfig.supabaseAnonKey.isEmpty) {
      debugPrint(
        'Realtime disabled: SUPABASE_URL/SUPABASE_ANON_KEY are not configured',
      );
      return;
    }

    _deviceId = deviceId;
    _commandHandler = onCommand;
    _isStarted = true;

    await _loadProcessedCommandIds();
    _listenConnectivityChanges();
    await _subscribeToCommands();
  }

  void onAppResumed() {
    if (!_isStarted) return;
    _scheduleReconnect(const Duration(milliseconds: 300));
  }

  Future<void> dispose() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    await _unsubscribe();
    _isStarted = false;
  }

  void sendCommandAck({
    required String commandId,
    required String command,
    String? deviceId,
  }) {
    if (commandId.isEmpty) return;
    unawaited(
      _sendCommandAckInternal(
        commandId: commandId,
        command: command,
        deviceId: deviceId,
      ),
    );
  }

  Future<void> _subscribeToCommands() async {
    final deviceId = _deviceId;
    if (deviceId == null || deviceId.isEmpty) return;

    await _unsubscribe();

    final channelName = 'device-commands-$deviceId';
    final supabase = Supabase.instance.client;
    final channel = supabase
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'device_commands',
          callback: _handleInsertEvent,
        );

    channel.subscribe((status, [error]) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        debugPrint('Realtime subscribed for device $deviceId');
        return;
      }

      if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut ||
          status == RealtimeSubscribeStatus.closed) {
        debugPrint(
          'Realtime disconnected ($status): ${error ?? 'no error details'}',
        );
        _scheduleReconnect(const Duration(seconds: 2));
      }
    });

    _channel = channel;
  }

  Future<void> _unsubscribe() async {
    final existing = _channel;
    _channel = null;
    if (existing != null) {
      try {
        await Supabase.instance.client.removeChannel(existing);
      } catch (e) {
        debugPrint('Failed to remove realtime channel: $e');
      }
    }
  }

  void _handleInsertEvent(PostgresChangePayload payload) {
    try {
      final dynamic newRecord = payload.newRecord;
      if (newRecord is! Map) {
        debugPrint('Ignoring realtime payload with invalid record format');
        return;
      }

      final row = Map<String, dynamic>.from(newRecord);
      final commandId = _normalize(
        row['id'] ?? row['command_id'] ?? row['commandId'],
      );
      final command = _normalize(row['command']).toUpperCase();
      final rowDeviceId = _normalize(
        row['device_id'] ?? row['deviceId'] ?? row['device_hash'],
      );
      final activeDeviceId = _deviceId ?? '';

      if (commandId.isEmpty ||
          rowDeviceId.isEmpty ||
          rowDeviceId != activeDeviceId) {
        return;
      }
      if (command != 'LOCK' && command != 'UNLOCK') return;
      if (_processedCommandIds.contains(commandId) ||
          _inFlightCommandIds.contains(commandId)) {
        return;
      }

      _inFlightCommandIds.add(commandId);
      final event = DeviceRealtimeCommand(
        commandId: commandId,
        command: command,
        deviceId: rowDeviceId,
        rawRecord: row,
      );
      unawaited(_executeCommand(event));
    } catch (e, stackTrace) {
      debugPrint('Failed to parse realtime payload: $e');
      debugPrint('$stackTrace');
    }
  }

  Future<void> _executeCommand(DeviceRealtimeCommand command) async {
    try {
      final handler = _commandHandler;
      if (handler == null) return;
      await handler(command);
      await _markCommandProcessed(command.commandId);
    } catch (e, stackTrace) {
      debugPrint('Realtime command failed ${command.commandId}: $e');
      debugPrint('$stackTrace');
    } finally {
      _inFlightCommandIds.remove(command.commandId);
    }
  }

  void _listenConnectivityChanges() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      dynamic result,
    ) {
      if (_isOnlineResult(result)) {
        _scheduleReconnect(const Duration(milliseconds: 500));
      }
    });
  }

  void _scheduleReconnect(Duration delay) {
    if (!_isStarted) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      unawaited(_reconnect());
    });
  }

  Future<void> _reconnect() async {
    if (!_isStarted || _isReconnecting) return;
    _isReconnecting = true;
    try {
      await _subscribeToCommands();
    } finally {
      _isReconnecting = false;
    }
  }

  Future<void> _markCommandProcessed(String commandId) async {
    _processedCommandIds.add(commandId);
    while (_processedCommandIds.length > _maxProcessedCommands) {
      _processedCommandIds.remove(_processedCommandIds.first);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _processedCommandIdsKey,
      _processedCommandIds.toList(growable: false),
    );
  }

  Future<void> _loadProcessedCommandIds() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_processedCommandIdsKey) ?? <String>[];
    _processedCommandIds
      ..clear()
      ..addAll(stored);
  }

  Future<void> _sendCommandAckInternal({
    required String commandId,
    required String command,
    String? deviceId,
  }) async {
    final resolvedDeviceId = deviceId ?? _deviceId ?? '';
    if (resolvedDeviceId.isEmpty) return;
    if (FonexConfig.deviceSecret.isEmpty) {
      debugPrint('ACK skipped: DEVICE_SECRET is not configured');
      return;
    }

    final baseUri = Uri.parse(FonexConfig.serverBaseUrl);
    final ackUri = baseUri.replace(
      path: FonexConfig.deviceAckPath,
      queryParameters: null,
    );

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'x-device-secret': FonexConfig.deviceSecret,
    };
    final body = <String, dynamic>{
      'commandId': commandId,
      'device_id': resolvedDeviceId,
      'command': command,
      'status': 'executed',
      'executed_at': DateTime.now().toIso8601String(),
    };

    const maxAttempts = 5;
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      final isOnline = await _hasNetworkConnectivity();
      if (!isOnline) {
        if (attempt == maxAttempts - 1) break;
        final delaySeconds = pow(2, attempt).toInt();
        await Future.delayed(Duration(seconds: delaySeconds));
        continue;
      }

      try {
        final response = await http
            .post(ackUri, headers: headers, body: jsonEncode(body))
            .timeout(const Duration(seconds: 8));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return;
        }
      } catch (_) {
        // Exponential backoff is applied below.
      }

      if (attempt == maxAttempts - 1) break;
      final delaySeconds = pow(2, attempt).toInt();
      await Future.delayed(Duration(seconds: delaySeconds));
    }

    debugPrint('ACK failed for command $commandId after $maxAttempts attempts');
  }

  String _normalize(dynamic value) => value?.toString().trim() ?? '';

  bool _isOnlineResult(dynamic result) {
    if (result is ConnectivityResult) {
      return result != ConnectivityResult.none;
    }
    if (result is List<ConnectivityResult>) {
      return result.any((item) => item != ConnectivityResult.none);
    }
    return true;
  }

  Future<bool> _hasNetworkConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    return _isOnlineResult(result);
  }
}
