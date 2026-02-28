import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fonex/services/app_logger.dart';
import 'package:fonex/services/crash_reporter.dart';

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

class AckQueueItem {
  const AckQueueItem({
    required this.commandId,
    required this.command,
    required this.deviceId,
    required this.queuedAt,
    required this.retryCount,
    this.lastStatusCode,
    this.lastResult,
  });

  final String commandId;
  final String command;
  final String deviceId;
  final DateTime queuedAt;
  final int retryCount;
  final int? lastStatusCode;
  final String? lastResult;

  AckQueueItem copyWith({
    int? retryCount,
    int? lastStatusCode,
    String? lastResult,
  }) {
    return AckQueueItem(
      commandId: commandId,
      command: command,
      deviceId: deviceId,
      queuedAt: queuedAt,
      retryCount: retryCount ?? this.retryCount,
      lastStatusCode: lastStatusCode ?? this.lastStatusCode,
      lastResult: lastResult ?? this.lastResult,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'command_id': commandId,
      'command': command,
      'device_id': deviceId,
      'queued_at': queuedAt.toUtc().toIso8601String(),
      'retry_count': retryCount,
      if (lastStatusCode != null) 'last_status_code': lastStatusCode,
      if (lastResult != null) 'last_result': lastResult,
    };
  }

  static AckQueueItem? fromJson(Map<String, dynamic> json) {
    final commandId = (json['command_id'] ?? '').toString().trim();
    final command = (json['command'] ?? '').toString().trim();
    final deviceId = (json['device_id'] ?? '').toString().trim();
    if (commandId.isEmpty || command.isEmpty || deviceId.isEmpty) {
      return null;
    }
    final queuedAtRaw = (json['queued_at'] ?? '').toString().trim();
    final queuedAt =
        DateTime.tryParse(queuedAtRaw)?.toLocal() ?? DateTime.now();
    final retryCountRaw = json['retry_count'];
    final retryCount = retryCountRaw is num ? retryCountRaw.toInt() : 0;
    final statusRaw = json['last_status_code'];
    final lastStatusCode = statusRaw is num ? statusRaw.toInt() : null;
    final lastResult = json['last_result']?.toString();
    return AckQueueItem(
      commandId: commandId,
      command: command,
      deviceId: deviceId,
      queuedAt: queuedAt,
      retryCount: retryCount,
      lastStatusCode: lastStatusCode,
      lastResult: lastResult,
    );
  }
}

class RealtimeDiagnostics {
  const RealtimeDiagnostics({
    required this.started,
    required this.subscribed,
    required this.reconnecting,
    required this.reconnectAttempt,
    required this.pendingAckCount,
    required this.lastStatus,
    this.lastDisconnectReason,
    this.lastSubscribedAt,
    this.lastCommandId,
    this.lastCommand,
    this.lastCommandStage,
    this.lastAckResult,
    this.lastAckStatusCode,
    this.lastAckAttempts,
    this.lastAckAt,
  });

  final bool started;
  final bool subscribed;
  final bool reconnecting;
  final int reconnectAttempt;
  final int pendingAckCount;
  final String lastStatus;
  final String? lastDisconnectReason;
  final DateTime? lastSubscribedAt;
  final String? lastCommandId;
  final String? lastCommand;
  final String? lastCommandStage;
  final String? lastAckResult;
  final int? lastAckStatusCode;
  final int? lastAckAttempts;
  final DateTime? lastAckAt;

  factory RealtimeDiagnostics.initial() {
    return const RealtimeDiagnostics(
      started: false,
      subscribed: false,
      reconnecting: false,
      reconnectAttempt: 0,
      pendingAckCount: 0,
      lastStatus: 'idle',
    );
  }

  RealtimeDiagnostics copyWith({
    bool? started,
    bool? subscribed,
    bool? reconnecting,
    int? reconnectAttempt,
    int? pendingAckCount,
    String? lastStatus,
    String? lastDisconnectReason,
    DateTime? lastSubscribedAt,
    String? lastCommandId,
    String? lastCommand,
    String? lastCommandStage,
    String? lastAckResult,
    int? lastAckStatusCode,
    int? lastAckAttempts,
    DateTime? lastAckAt,
  }) {
    return RealtimeDiagnostics(
      started: started ?? this.started,
      subscribed: subscribed ?? this.subscribed,
      reconnecting: reconnecting ?? this.reconnecting,
      reconnectAttempt: reconnectAttempt ?? this.reconnectAttempt,
      pendingAckCount: pendingAckCount ?? this.pendingAckCount,
      lastStatus: lastStatus ?? this.lastStatus,
      lastDisconnectReason: lastDisconnectReason ?? this.lastDisconnectReason,
      lastSubscribedAt: lastSubscribedAt ?? this.lastSubscribedAt,
      lastCommandId: lastCommandId ?? this.lastCommandId,
      lastCommand: lastCommand ?? this.lastCommand,
      lastCommandStage: lastCommandStage ?? this.lastCommandStage,
      lastAckResult: lastAckResult ?? this.lastAckResult,
      lastAckStatusCode: lastAckStatusCode ?? this.lastAckStatusCode,
      lastAckAttempts: lastAckAttempts ?? this.lastAckAttempts,
      lastAckAt: lastAckAt ?? this.lastAckAt,
    );
  }
}

class AckSendResult {
  const AckSendResult({
    required this.success,
    required this.attempts,
    this.statusCode,
    this.responseBody,
  });

  final bool success;
  final int attempts;
  final int? statusCode;
  final String? responseBody;
}

class RealtimeCommandService {
  RealtimeCommandService._internal();
  static final RealtimeCommandService _instance =
      RealtimeCommandService._internal();
  factory RealtimeCommandService() => _instance;

  static const String _processedCommandIdsKey = 'processed_command_ids';
  static const String _pendingAcksKey = 'pending_command_acks';
  static const int _maxProcessedCommands = 200;
  static const int _maxPendingAcks = 250;
  static final ValueNotifier<RealtimeDiagnostics> diagnosticsNotifier =
      ValueNotifier<RealtimeDiagnostics>(RealtimeDiagnostics.initial());

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
  final List<AckQueueItem> _pendingAckQueue = <AckQueueItem>[];

  bool get isStarted => _isStarted;
  bool get isSubscribed => _isSubscribed;
  List<AckQueueItem> get pendingAckQueue =>
      List<AckQueueItem>.unmodifiable(_pendingAckQueue);

  static String _redactSecret(String secret) {
    final trimmed = secret.trim();
    if (trimmed.isEmpty) return '[EMPTY]';
    if (trimmed.length <= 8) return '[REDACTED]';
    final prefix = trimmed.substring(0, 4);
    final suffix = trimmed.substring(trimmed.length - 4);
    return '$prefix...$suffix';
  }

  void _updateDiagnostics(
    RealtimeDiagnostics Function(RealtimeDiagnostics current) updater,
  ) {
    diagnosticsNotifier.value = updater(diagnosticsNotifier.value);
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
    _updateDiagnostics(
      (current) => current.copyWith(
        started: true,
        lastStatus: 'starting',
      ),
    );

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
    await _loadPendingAckQueue();
    _listenConnectivityChanges();
    await _subscribeToCommands();
    unawaited(retryPendingAcks());
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
    _updateDiagnostics(
      (current) => current.copyWith(
        started: false,
        subscribed: false,
        reconnecting: false,
        lastStatus: 'stopped',
      ),
    );
  }

  void ensureConnected() {
    if (!_isStarted) return;
    if (_isSubscribed || _isReconnecting) return;
    _scheduleReconnect(const Duration(milliseconds: 200));
    unawaited(retryPendingAcks());
  }

  Future<void> reconnectNow() async {
    if (!_isStarted) return;
    _scheduleReconnect(Duration.zero);
    await retryPendingAcks();
  }

  Future<void> clearPendingAckQueue() async {
    _pendingAckQueue.clear();
    await _savePendingAckQueue();
    _updateDiagnostics(
      (current) => current.copyWith(
        pendingAckCount: 0,
        lastStatus: 'ack_queue_cleared',
      ),
    );
  }

  Future<bool> sendCommandAck({
    required String commandId,
    required String command,
    String? deviceId,
  }) async {
    if (commandId.isEmpty) return false;
    final result = await _sendCommandAckInternal(
      commandId: commandId,
      command: command,
      deviceId: deviceId,
    );
    final resolvedDeviceId = deviceId ?? _deviceId ?? '';
    if (result.success) {
      await _removePendingAck(commandId);
    } else if (resolvedDeviceId.isNotEmpty) {
      await _upsertPendingAck(
        commandId: commandId,
        command: command,
        deviceId: resolvedDeviceId,
        attemptCount: result.attempts,
        statusCode: result.statusCode,
        result: result.responseBody ?? 'ack_failed',
      );
    }
    return result.success;
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
    _updateDiagnostics(
      (current) => current.copyWith(
        lastStatus: 'subscribe_requested',
        reconnecting: false,
      ),
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
        _updateDiagnostics(
          (current) => current.copyWith(
            subscribed: true,
            reconnecting: false,
            reconnectAttempt: 0,
            lastStatus: 'subscribed',
            lastDisconnectReason: 'none',
            lastSubscribedAt: DateTime.now(),
          ),
        );
        return;
      }

      if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut ||
          status == RealtimeSubscribeStatus.closed) {
        _isSubscribed = false;
        final reason = '$status: ${error ?? 'no error details'}';
        debugPrint(
          'Realtime disconnected ($status token=$lifecycleToken): '
          '${error ?? 'no error details'}',
        );
        _updateDiagnostics(
          (current) => current.copyWith(
            subscribed: false,
            reconnecting: true,
            reconnectAttempt: _reconnectAttempt + 1,
            lastStatus: 'disconnected',
            lastDisconnectReason: reason,
          ),
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
    _updateDiagnostics(
      (current) => current.copyWith(
        subscribed: false,
        lastStatus: 'unsubscribed',
      ),
    );
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
      _updateDiagnostics(
        (current) => current.copyWith(
          lastCommandId: commandId,
          lastCommand: command,
          lastCommandStage: 'received',
          lastStatus: 'command_received',
        ),
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
      _updateDiagnostics(
        (current) => current.copyWith(
          lastCommandId: command.commandId,
          lastCommand: command.command,
          lastCommandStage: 'dispatch',
          lastStatus: 'command_dispatch',
        ),
      );
      await handler(command);
      await _markCommandProcessed(command.commandId);
      AppLogger.log(
        'Realtime command completed: id=${command.commandId} '
        'command=${command.command}',
      );
      _updateDiagnostics(
        (current) => current.copyWith(
          lastCommandId: command.commandId,
          lastCommand: command.command,
          lastCommandStage: 'completed',
          lastStatus: 'command_completed',
        ),
      );
    } catch (e, stackTrace) {
      AppLogger.log('Realtime command failed ${command.commandId}: $e');
      AppLogger.log('$stackTrace');
      unawaited(
        CrashReporter.recordNonFatal(
          source: 'realtime_command',
          message: 'Command ${command.commandId} failed: $e',
          stack: stackTrace,
        ),
      );
      _updateDiagnostics(
        (current) => current.copyWith(
          lastCommandId: command.commandId,
          lastCommand: command.command,
          lastCommandStage: 'failed',
          lastStatus: 'command_failed',
        ),
      );
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
        unawaited(retryPendingAcks());
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
    _updateDiagnostics(
      (current) => current.copyWith(
        reconnecting: true,
        reconnectAttempt: _reconnectAttempt,
        lastStatus: 'reconnecting',
      ),
    );
    try {
      await _subscribeToCommands();
    } finally {
      _isReconnecting = false;
      _updateDiagnostics(
        (current) => current.copyWith(
          reconnecting: false,
        ),
      );
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

  Future<void> _loadPendingAckQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingAcksKey);
    _pendingAckQueue.clear();
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              final parsed = AckQueueItem.fromJson(
                Map<String, dynamic>.from(item),
              );
              if (parsed != null) {
                _pendingAckQueue.add(parsed);
              }
            }
          }
        }
      } catch (e) {
        AppLogger.log('Failed to load pending ACK queue: $e');
      }
    }
    _updateDiagnostics(
      (current) => current.copyWith(
        pendingAckCount: _pendingAckQueue.length,
      ),
    );
  }

  Future<void> _savePendingAckQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      _pendingAckQueue.map((item) => item.toJson()).toList(growable: false),
    );
    await prefs.setString(_pendingAcksKey, encoded);
    _updateDiagnostics(
      (current) => current.copyWith(
        pendingAckCount: _pendingAckQueue.length,
      ),
    );
  }

  Future<void> _upsertPendingAck({
    required String commandId,
    required String command,
    required String deviceId,
    required int attemptCount,
    int? statusCode,
    String? result,
  }) async {
    final existingIndex = _pendingAckQueue.indexWhere(
      (item) => item.commandId == commandId,
    );
    if (existingIndex >= 0) {
      final existing = _pendingAckQueue[existingIndex];
      _pendingAckQueue[existingIndex] = existing.copyWith(
        retryCount: existing.retryCount + attemptCount,
        lastStatusCode: statusCode,
        lastResult: result,
      );
    } else {
      _pendingAckQueue.add(
        AckQueueItem(
          commandId: commandId,
          command: command,
          deviceId: deviceId,
          queuedAt: DateTime.now(),
          retryCount: attemptCount,
          lastStatusCode: statusCode,
          lastResult: result,
        ),
      );
      while (_pendingAckQueue.length > _maxPendingAcks) {
        final dropped = _pendingAckQueue.removeAt(0);
        AppLogger.log(
          'Pending ACK queue limit reached. Dropped oldest command '
          '${dropped.commandId}',
        );
      }
    }
    await _savePendingAckQueue();
  }

  Future<void> _removePendingAck(String commandId) async {
    _pendingAckQueue.removeWhere((item) => item.commandId == commandId);
    await _savePendingAckQueue();
  }

  Future<int> retryPendingAcks({int maxItems = 5}) async {
    if (_pendingAckQueue.isEmpty) return 0;
    final items = _pendingAckQueue.take(maxItems).toList(growable: false);
    int successCount = 0;

    for (final item in items) {
      final result = await _sendCommandAckInternal(
        commandId: item.commandId,
        command: item.command,
        deviceId: item.deviceId,
        maxAttempts: 2,
      );
      if (result.success) {
        successCount++;
        await _removePendingAck(item.commandId);
      } else {
        await _upsertPendingAck(
          commandId: item.commandId,
          command: item.command,
          deviceId: item.deviceId,
          attemptCount: result.attempts,
          statusCode: result.statusCode,
          result: result.responseBody ?? 'retry_failed',
        );
      }
    }

    _updateDiagnostics(
      (current) => current.copyWith(
        lastStatus: successCount > 0
            ? 'pending_ack_retry_success'
            : 'pending_ack_retry_no_success',
      ),
    );
    return successCount;
  }

  Future<AckSendResult> _sendCommandAckInternal({
    required String commandId,
    required String command,
    String? deviceId,
    int maxAttempts = 5,
  }) async {
    final resolvedDeviceId = deviceId ?? _deviceId ?? '';
    if (resolvedDeviceId.isEmpty) {
      return const AckSendResult(success: false, attempts: 0);
    }
    if (FonexConfig.deviceSecret.isEmpty) {
      AppLogger.log('ACK skipped: DEVICE_SECRET is not configured');
      return const AckSendResult(success: false, attempts: 0);
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

    int attemptsUsed = 0;
    int? lastStatusCode;
    String? lastBody;

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      attemptsUsed = attempt + 1;
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
        lastStatusCode = response.statusCode;
        lastBody = response.body;
        AppLogger.log(
          'ACK response attempt ${attempt + 1}/$maxAttempts: '
          'commandId=$commandId status=${response.statusCode} '
          'body=${response.body}',
        );
        _updateDiagnostics(
          (current) => current.copyWith(
            lastAckAt: DateTime.now(),
            lastAckAttempts: attempt + 1,
            lastAckStatusCode: response.statusCode,
            lastAckResult: response.body,
            lastStatus: 'ack_attempt',
          ),
        );
        if (response.statusCode >= 200 && response.statusCode < 300) {
          AppLogger.log(
            'ACK success: commandId=$commandId command=$command '
            'url=$ackUri',
          );
          _updateDiagnostics(
            (current) => current.copyWith(
              lastAckAt: DateTime.now(),
              lastAckAttempts: attempt + 1,
              lastAckStatusCode: response.statusCode,
              lastAckResult: 'success',
              lastStatus: 'ack_success',
            ),
          );
          return AckSendResult(
            success: true,
            attempts: attempt + 1,
            statusCode: response.statusCode,
            responseBody: response.body,
          );
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
        _updateDiagnostics(
          (current) => current.copyWith(
            lastAckAt: DateTime.now(),
            lastAckAttempts: attempt + 1,
            lastAckStatusCode: null,
            lastAckResult: 'exception',
            lastStatus: 'ack_exception',
          ),
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
    _updateDiagnostics(
      (current) => current.copyWith(
        lastAckAt: DateTime.now(),
        lastAckAttempts: attemptsUsed,
        lastAckStatusCode: lastStatusCode,
        lastAckResult: lastBody ?? 'failed',
        lastStatus: 'ack_failed',
      ),
    );
    unawaited(
      CrashReporter.recordNonFatal(
        source: 'command_ack',
        message:
            'ACK failed for $commandId attempts=$attemptsUsed status=$lastStatusCode',
      ),
    );
    return AckSendResult(
      success: false,
      attempts: attemptsUsed,
      statusCode: lastStatusCode,
      responseBody: lastBody,
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
