import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fonex/services/app_logger.dart';

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
  bool _isSubscribed = false;
  int _reconnectAttempt = 0;
  int _channelLifecycleToken = 0;
  String? _deviceId;
  final Set<String> _acceptedDeviceIds = <String>{};
  Future<void> Function(DeviceRealtimeCommand command)? _commandHandler;

  final Set<String> _processedCommandIds = <String>{};
  final Set<String> _inFlightCommandIds = <String>{};

  bool get isStarted => _isStarted;
  bool get isSubscribed => _isSubscribed;

  static String _redactSecret(String secret) {
    final trimmed = secret.trim();
    if (trimmed.isEmpty) return '[EMPTY]';
    if (trimmed.length <= 8) return '[REDACTED]';
    final prefix = trimmed.substring(0, 4);
    final suffix = trimmed.substring(trimmed.length - 4);
    return '$prefix...$suffix';
  }

  Future<void> start({
    required String deviceId,
    List<String> acceptedDeviceIds = const <String>[],
    required Future<void> Function(DeviceRealtimeCommand command) onCommand,
  }) async {
    if (_isStarted) return;

    if (deviceId.isEmpty) {
      AppLogger.log('Realtime disabled: empty device id');
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
    _reconnectAttempt = 0;
    _acceptedDeviceIds
      ..clear()
      ..addAll(
        <String>{
          deviceId,
          ...acceptedDeviceIds,
        }.map((id) => id.trim()).where((id) => id.isNotEmpty),
      );
    _commandHandler = onCommand;
    _isStarted = true;

    AppLogger.log(
      'Realtime start: supabase=${FonexConfig.supabaseUrl} '
      'backend=${FonexConfig.serverBaseUrl} '
      'ackPath=${FonexConfig.deviceAckPath}',
    );
    AppLogger.log(
      'Realtime accepted IDs (exact match): '
      '${_acceptedDeviceIds.toList(growable: false)}',
    );

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
    _acceptedDeviceIds.clear();
    _reconnectAttempt = 0;
    _isSubscribed = false;
    _isStarted = false;
  }

  void ensureConnected() {
    if (!_isStarted) return;
    if (_isSubscribed || _isReconnecting) return;
    _scheduleReconnect(const Duration(milliseconds: 200));
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
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    final channelName = 'device-commands-$deviceId';
    final supabase = Supabase.instance.client;
    final lifecycleToken = ++_channelLifecycleToken;
    final channel = supabase
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'device_commands',
          callback: _handleInsertEvent,
        );

    AppLogger.log(
      'Realtime subscribe requested: '
      'schema=public table=device_commands channel=$channelName '
      'token=$lifecycleToken',
    );

    channel.subscribe((status, [error]) {
      if (lifecycleToken != _channelLifecycleToken) {
        return;
      }
      if (status == RealtimeSubscribeStatus.subscribed) {
        _reconnectAttempt = 0;
        _isSubscribed = true;
        AppLogger.log(
          'Realtime subscribed: schema=public table=device_commands '
          'device=$deviceId acceptedIds=$_acceptedDeviceIds token=$lifecycleToken',
        );
        return;
      }

      if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut ||
          status == RealtimeSubscribeStatus.closed) {
        _isSubscribed = false;
        debugPrint(
          'Realtime disconnected ($status token=$lifecycleToken): '
          '${error ?? 'no error details'}',
        );
        _scheduleReconnect(_nextReconnectDelay());
      }
    });

    _channel = channel;
  }

  Future<void> _unsubscribe() async {
    final existing = _channel;
    _channelLifecycleToken++;
    _channel = null;
    _isSubscribed = false;
    if (existing != null) {
      try {
        await Supabase.instance.client.removeChannel(existing);
      } catch (e) {
        AppLogger.log('Failed to remove realtime channel: $e');
      }
    }
  }

  void _handleInsertEvent(PostgresChangePayload payload) {
    try {
      final dynamic newRecord = payload.newRecord;
      if (newRecord is! Map) {
        AppLogger.log('Ignoring realtime payload with invalid record format');
        return;
      }

      final row = Map<String, dynamic>.from(newRecord);
      final commandId = _normalize(
        row['id'] ?? row['command_id'] ?? row['commandId'],
      );
      final command = _normalize(row['command']).toUpperCase();
      final normalizedDeviceId = _normalize(row['device_id']);
      final normalizedDeviceHash = _normalize(row['device_hash']);
      final rowDeviceId = normalizedDeviceId.isNotEmpty
          ? normalizedDeviceId
          : _normalize(row['deviceId']);
      final rowDeviceHash = normalizedDeviceHash.isNotEmpty
          ? normalizedDeviceHash
          : _normalize(row['deviceHash']);

      final exactDeviceHashMatch =
          rowDeviceHash.isNotEmpty &&
          _acceptedDeviceIds.contains(rowDeviceHash);
      final exactDeviceIdMatch =
          rowDeviceId.isNotEmpty && _acceptedDeviceIds.contains(rowDeviceId);
      final matchedDeviceId = exactDeviceHashMatch
          ? rowDeviceHash
          : (exactDeviceIdMatch ? rowDeviceId : '');
      final rowDeviceCandidates = <String>{rowDeviceId, rowDeviceHash}
        ..removeWhere((id) => id.isEmpty);

      if (commandId.isEmpty) {
        return;
      }

      AppLogger.log(
        'Realtime event received: id=$commandId command=$command '
        'rowDeviceId=$rowDeviceId rowDeviceHash=$rowDeviceHash '
        'hashExactMatch=$exactDeviceHashMatch idExactMatch=$exactDeviceIdMatch',
      );
      if (matchedDeviceId.isEmpty) {
        if (command == 'LOCK' || command == 'UNLOCK') {
          AppLogger.log(
            'Realtime command ignored due to exact device mismatch. '
            'rowIds=$rowDeviceCandidates acceptedIds=$_acceptedDeviceIds '
            'commandId=$commandId command=$command',
          );
        }
        return;
      }
      if (command != 'LOCK' && command != 'UNLOCK') return;
      if (_processedCommandIds.contains(commandId) ||
          _inFlightCommandIds.contains(commandId)) {
        AppLogger.log('Realtime command skipped (duplicate): id=$commandId');
        return;
      }

      _inFlightCommandIds.add(commandId);
      final event = DeviceRealtimeCommand(
        commandId: commandId,
        command: command,
        deviceId: matchedDeviceId,
        rawRecord: row,
      );
      unawaited(_executeCommand(event));
    } catch (e, stackTrace) {
      AppLogger.log('Failed to parse realtime payload: $e');
      AppLogger.log('$stackTrace');
    }
  }

  Future<void> _executeCommand(DeviceRealtimeCommand command) async {
    try {
      final handler = _commandHandler;
      if (handler == null) return;
      AppLogger.log(
        'Realtime command dispatch: id=${command.commandId} '
        'command=${command.command} matchedDevice=${command.deviceId}',
      );
      await handler(command);
      await _markCommandProcessed(command.commandId);
      AppLogger.log(
        'Realtime command completed: id=${command.commandId} '
        'command=${command.command}',
      );
    } catch (e, stackTrace) {
      AppLogger.log('Realtime command failed ${command.commandId}: $e');
      AppLogger.log('$stackTrace');
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
    final isOnline = await _hasNetworkConnectivity();
    if (!isOnline) {
      _scheduleReconnect(_nextReconnectDelay());
      return;
    }

    _isReconnecting = true;
    try {
      await _subscribeToCommands();
    } finally {
      _isReconnecting = false;
    }
  }

  Duration _nextReconnectDelay() {
    final attempt = _reconnectAttempt++;
    final seconds = min(10, 1 << min(attempt, 3));
    return Duration(seconds: seconds);
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
      AppLogger.log('ACK skipped: DEVICE_SECRET is not configured');
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
    final redactedHeaders = <String, String>{
      ...headers,
      'x-device-secret': _redactSecret(FonexConfig.deviceSecret),
    };
    final executedAt = DateTime.now().toUtc().toIso8601String().replaceFirst(
      RegExp(r'\.\d+Z$'),
      'Z',
    );
    final body = <String, dynamic>{
      'commandId': commandId,
      'device_id': resolvedDeviceId,
      'command': command,
      'status': 'executed',
      'executed_at': executedAt,
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
        AppLogger.log(
          'ACK response attempt ${attempt + 1}/$maxAttempts: '
          'commandId=$commandId status=${response.statusCode} '
          'body=${response.body}',
        );
        if (response.statusCode >= 200 && response.statusCode < 300) {
          AppLogger.log(
            'ACK success: commandId=$commandId command=$command '
            'url=$ackUri',
          );
          return;
        }
        AppLogger.log(
          'ACK non-2xx request details: '
          'url=$ackUri headers=$redactedHeaders body=${jsonEncode(body)}',
        );
      } catch (_) {
        AppLogger.log(
          'ACK request exception attempt ${attempt + 1}/$maxAttempts '
          'for commandId=$commandId',
        );
        AppLogger.log(
          'ACK exception request details: '
          'url=$ackUri headers=$redactedHeaders body=${jsonEncode(body)}',
        );
        // Exponential backoff is applied below.
      }

      if (attempt == maxAttempts - 1) break;
      final delaySeconds = pow(2, attempt).toInt();
      await Future.delayed(Duration(seconds: delaySeconds));
    }

    AppLogger.log(
      'ACK failed for command $commandId after $maxAttempts attempts',
    );
    AppLogger.log(
      'ACK final failed request details: '
      'url=$ackUri headers=$redactedHeaders body=${jsonEncode(body)}',
    );
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
