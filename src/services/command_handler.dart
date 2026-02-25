// =============================================================================
// COMMAND HANDLER SERVICE
// =============================================================================
//// =============================================================================
// COMMAND HANDLER SERVICE
// =============================================================================
//// =============================================================================
// IMPROVED REALTIME COMMAND SERVICE
// =============================================================================
// Enhanced version with better connection handling, error recovery, and logging
// =============================================================================

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
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;

  bool _isStarted = false;
  bool _isReconnecting = false;
  bool _isSubscribed = false;
  int _reconnectAttempt = 0;
  String? _deviceId;
  final Set<String> _acceptedDeviceIds = <String>{};
  Future<void> Function(DeviceRealtimeCommand command)? _commandHandler;

  final Set<String> _processedCommandIds = <String>{};
  final Set<String> _inFlightCommandIds = <String>{};

  bool get isStarted => _isStarted;
  bool get isSubscribed => _isSubscribed;

  Future<void> start({
    required String deviceId,
    List<String> acceptedDeviceIds = const <String>[],
    required Future<void> Function(DeviceRealtimeCommand command) onCommand,
  }) async {
    if (_isStarted) {
      AppLogger.log('Realtime service already started');
      return;
    }

    if (deviceId.isEmpty) {
      AppLogger.log('Realtime disabled: empty device id');
      return;
    }
    
    // Validate Supabase configuration
    if (FonexConfig.supabaseUrl.isEmpty ||
        FonexConfig.supabaseAnonKey.isEmpty) {
      AppLogger.log(
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

    AppLogger.log('Starting RealtimeCommandService for device: $deviceId');
    AppLogger.log('Accepted device IDs: $_acceptedDeviceIds');

    await _loadProcessedCommandIds();
    _listenConnectivityChanges();
    await _subscribeToCommands();
    
    // Start heartbeat to maintain connection
    _startHeartbeat();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (_isStarted && !_isReconnecting) {
        // Send a small request to keep connection alive
        _ensureConnectionAlive();
      }
    });
  }

  Future<void> _ensureConnectionAlive() async {
    try {
      final supabase = Supabase.instance.client;
      // Simple query to keep connection alive
      await supabase.from('device_commands').select('id').limit(1);
    } catch (e) {
      AppLogger.log('Heartbeat check failed: $e');
      // If heartbeat fails, try to reconnect
      _scheduleReconnect(const Duration(seconds: 1));
    }
  }

  void onAppResumed() {
    AppLogger.log('App resumed - ensuring realtime connection');
    if (!_isStarted) return;
    _scheduleReconnect(const Duration(milliseconds: 300));
  }

  Future<void> dispose() async {
    AppLogger.log('Disposing RealtimeCommandService');
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
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
    AppLogger.log('Ensuring realtime connection');
    _scheduleReconnect(const Duration(milliseconds: 200));
  }

  void sendCommandAck({
    required String commandId,
    required String command,
    String? deviceId,
    Map<String, dynamic>? additionalData,
  }) {
    if (commandId.isEmpty) return;
    unawaited(
      _sendCommandAckInternal(
        commandId: commandId,
        command: command,
        deviceId: deviceId,
        additionalData: additionalData,
      ),
    );
  }

  Future<void> _subscribeToCommands() async {
    final deviceId = _deviceId;
    if (deviceId == null || deviceId.isEmpty) {
      AppLogger.log('Cannot subscribe - no device ID');
      return;
    }

    AppLogger.log('Attempting to subscribe to realtime commands for device: $deviceId');
    
    await _unsubscribe();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    try {
      final supabase = Supabase.instance.client;
      
      // Close any existing channels
      await supabase.removeAllChannels();
      
      final channelName = 'device-commands-$deviceId';
      AppLogger.log('Creating channel: $channelName');
      
      final channel = supabase
          .channel(channelName)
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'device_commands',
            callback: _handleInsertEvent,
          );

      channel.subscribe((status, [error]) {
        AppLogger.log('Realtime subscription status: $status, error: $error');
        
        if (status == RealtimeSubscribeStatus.subscribed) {
          _reconnectAttempt = 0;
          _isSubscribed = true;
          AppLogger.log('✅ Realtime subscribed for device $deviceId');
          return;
        }

        if (status == RealtimeSubscribeStatus.channelError ||
            status == RealtimeSubscribeStatus.timedOut ||
            status == RealtimeSubscribeStatus.closed) {
          _isSubscribed = false;
          AppLogger.log(
            '❌ Realtime disconnected ($status): ${error ?? 'no error details'}',
          );
          _scheduleReconnect(_nextReconnectDelay());
        }
      });

      _channel = channel;
    } catch (e, stackTrace) {
      AppLogger.log('Failed to subscribe to realtime: $e');
      AppLogger.log('$stackTrace');
      _scheduleReconnect(_nextReconnectDelay());
    }
  }

  Future<void> _unsubscribe() async {
    final existing = _channel;
    _channel = null;
    _isSubscribed = false;
    
    if (existing != null) {
      try {
        AppLogger.log('Removing realtime channel');
        await Supabase.instance.client.removeChannel(existing);
        AppLogger.log('Realtime channel removed successfully');
      } catch (e) {
        AppLogger.log('Failed to remove realtime channel: $e');
      }
    }
  }

  void _handleInsertEvent(PostgresChangePayload payload) {
    try {
      AppLogger.log('Received realtime payload: ${payload.newRecord}');
      
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
      final rowDeviceCandidates = <String>{
        _normalize(row['device_id']),
        _normalize(row['deviceId']),
        _normalize(row['device_hash']),
        _normalize(row['deviceHash']),
      }..removeWhere((id) => id.isEmpty);
      
      final matchedDeviceId = rowDeviceCandidates.firstWhere(
        _acceptedDeviceIds.contains,
        orElse: () => '',
      );

      AppLogger.log('Processing command: $command, ID: $commandId, device candidates: $rowDeviceCandidates, matched: $matchedDeviceId');

      if (commandId.isEmpty) {
        AppLogger.log('Skipping command - empty command ID');
        return;
      }
      
      if (matchedDeviceId.isEmpty) {
        if (command == 'LOCK' || command == 'UNLOCK' || command == 'EXTEND_EMI' || command == 'MARK_PAID') {
          AppLogger.log(
            'Realtime command ignored due to device mismatch. '
            'rowIds=$rowDeviceCandidates acceptedIds=$_acceptedDeviceIds commandId=$commandId command=$command',
          );
        }
        return;
      }
      
      // Process all valid commands, not just LOCK/UNLOCK
      if (_processedCommandIds.contains(commandId) ||
          _inFlightCommandIds.contains(commandId)) {
        AppLogger.log('Command $commandId already processed or in flight');
        return;
      }

      _inFlightCommandIds.add(commandId);
      final event = DeviceRealtimeCommand(
        commandId: commandId,
        command: command,
        deviceId: matchedDeviceId,
        rawRecord: row,
      );
      
      AppLogger.log('Executing command: $command with data: $row');
      unawaited(_executeCommand(event));
    } catch (e, stackTrace) {
      AppLogger.log('Failed to parse realtime payload: $e');
      AppLogger.log('$stackTrace');
    }
  }

  Future<void> _executeCommand(DeviceRealtimeCommand command) async {
    try {
      AppLogger.log('Executing command: ${command.command} with data: ${command.rawRecord}');
      
      final handler = _commandHandler;
      if (handler == null) {
        AppLogger.log('No command handler registered');
        return;
      }
      
      await handler(command);
      AppLogger.log('Command ${command.commandId} executed successfully');
      await _markCommandProcessed(command.commandId);
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
      ConnectivityResult result,
    ) {
      AppLogger.log('Connectivity changed: $result');
      if (result != ConnectivityResult.none) {
        AppLogger.log('Network available - scheduling reconnect');
        _scheduleReconnect(const Duration(milliseconds: 500));
      }
    });
  }

  void _scheduleReconnect(Duration delay) {
    if (!_isStarted) {
      AppLogger.log('Not scheduling reconnect - service not started');
      return;
    }
    
    AppLogger.log('Scheduling reconnect in $delay');
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      unawaited(_reconnect());
    });
  }

  Future<void> _reconnect() async {
    if (!_isStarted || _isReconnecting) {
      AppLogger.log('Not reconnecting - service not started or already reconnecting');
      return;
    }
    
    AppLogger.log('Attempting to reconnect to realtime service');
    final isOnline = await _hasNetworkConnectivity();
    if (!isOnline) {
      AppLogger.log('No network connectivity - scheduling next reconnect');
      _scheduleReconnect(_nextReconnectDelay());
      return;
    }

    _isReconnecting = true;
    try {
      AppLogger.log('Reconnecting to realtime service');
      await _subscribeToCommands();
    } catch (e) {
      AppLogger.log('Reconnection failed: $e');
      _scheduleReconnect(_nextReconnectDelay());
    } finally {
      _isReconnecting = false;
    }
  }

  Duration _nextReconnectDelay() {
    final attempt = _reconnectAttempt++;
    final seconds = min(30, 1 << min(attempt, 5)); // Max 30 seconds
    AppLogger.log('Next reconnect delay: ${seconds}s (attempt $attempt)');
    return Duration(seconds: seconds);
  }

  Future<void> _markCommandProcessed(String commandId) async {
    _processedCommandIds.add(commandId);
    while (_processedCommandIds.length > _maxProcessedCommands) {
      _processedCommandIds.remove(_processedCommandIds.first);
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _processedCommandIdsKey,
        _processedCommandIds.toList(growable: false),
      );
    } catch (e) {
      AppLogger.log('Failed to save processed command IDs: $e');
    }
  }

  Future<void> _loadProcessedCommandIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList(_processedCommandIdsKey) ?? <String>[];
      _processedCommandIds
        ..clear()
        ..addAll(stored);
      AppLogger.log('Loaded ${_processedCommandIds.length} processed command IDs');
    } catch (e) {
      AppLogger.log('Failed to load processed command IDs: $e');
    }
  }

  Future<void> _sendCommandAckInternal({
    required String commandId,
    required String command,
    String? deviceId,
    Map<String, dynamic>? additionalData,
  }) async {
    final resolvedDeviceId = deviceId ?? _deviceId ?? '';
    if (resolvedDeviceId.isEmpty) {
      AppLogger.log('ACK skipped: No device ID');
      return;
    }
    
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
      if (additionalData != null) ...additionalData,
    };

    AppLogger.log('Sending command ACK: $body');

    const maxAttempts = 5;
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      final isOnline = await _hasNetworkConnectivity();
      if (!isOnline) {
        AppLogger.log('No network connectivity for ACK (attempt ${attempt + 1})');
        if (attempt == maxAttempts - 1) break;
        final delaySeconds = pow(2, attempt).toInt();
        await Future.delayed(Duration(seconds: delaySeconds));
        continue;
      }

      try {
        final response = await http
            .post(ackUri, headers: headers, body: jsonEncode(body))
            .timeout(const Duration(seconds: 10));
            
        AppLogger.log('ACK response status: ${response.statusCode}, body: ${response.body}');
        
        if (response.statusCode >= 200 && response.statusCode < 300) {
          AppLogger.log('✅ ACK sent successfully for command $commandId');
          return;
        } else {
          AppLogger.log('ACK failed with status ${response.statusCode}: ${response.body}');
        }
      } catch (e) {
        AppLogger.log('ACK network error (attempt ${attempt + 1}): $e');
        // Exponential backoff is applied below.
      }

      if (attempt == maxAttempts - 1) {
        AppLogger.log('❌ ACK failed for command $commandId after $maxAttempts attempts');
        break;
      }
      
      final delaySeconds = pow(2, attempt).toInt();
      AppLogger.log('Retrying ACK in $delaySeconds seconds');
      await Future.delayed(Duration(seconds: delaySeconds));
    }
  }

  String _normalize(dynamic value) {
    if (value == null) return '';
    return value.toString().trim();
  }

  bool _isOnlineResult(ConnectivityResult result) {
    return result != ConnectivityResult.none;
  }

  Future<bool> _hasNetworkConnectivity() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return _isOnlineResult(result);
    } catch (e) {
      AppLogger.log('Error checking connectivity: $e');
      return false; // Assume offline on error
    }
  }
}// =============================================================================
// IMPROVED REALTIME COMMAND SERVICE
// =============================================================================
// Enhanced version with better connection handling, error recovery, and logging
// =============================================================================

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
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;

  bool _isStarted = false;
  bool _isReconnecting = false;
  bool _isSubscribed = false;
  int _reconnectAttempt = 0;
  String? _deviceId;
  final Set<String> _acceptedDeviceIds = <String>{};
  Future<void> Function(DeviceRealtimeCommand command)? _commandHandler;

  final Set<String> _processedCommandIds = <String>{};
  final Set<String> _inFlightCommandIds = <String>{};

  bool get isStarted => _isStarted;
  bool get isSubscribed => _isSubscribed;

  Future<void> start({
    required String deviceId,
    List<String> acceptedDeviceIds = const <String>[],
    required Future<void> Function(DeviceRealtimeCommand command) onCommand,
  }) async {
    if (_isStarted) {
      AppLogger.log('Realtime service already started');
      return;
    }

    if (deviceId.isEmpty) {
      AppLogger.log('Realtime disabled: empty device id');
      return;
    }
    
    // Validate Supabase configuration
    if (FonexConfig.supabaseUrl.isEmpty ||
        FonexConfig.supabaseAnonKey.isEmpty) {
      AppLogger.log(
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

    AppLogger.log('Starting RealtimeCommandService for device: $deviceId');
    AppLogger.log('Accepted device IDs: $_acceptedDeviceIds');

    await _loadProcessedCommandIds();
    _listenConnectivityChanges();
    await _subscribeToCommands();
    
    // Start heartbeat to maintain connection
    _startHeartbeat();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (_isStarted && !_isReconnecting) {
        // Send a small request to keep connection alive
        _ensureConnectionAlive();
      }
    });
  }

  Future<void> _ensureConnectionAlive() async {
    try {
      final supabase = Supabase.instance.client;
      // Simple query to keep connection alive
      await supabase.from('device_commands').select('id').limit(1);
    } catch (e) {
      AppLogger.log('Heartbeat check failed: $e');
      // If heartbeat fails, try to reconnect
      _scheduleReconnect(const Duration(seconds: 1));
    }
  }

  void onAppResumed() {
    AppLogger.log('App resumed - ensuring realtime connection');
    if (!_isStarted) return;
    _scheduleReconnect(const Duration(milliseconds: 300));
  }

  Future<void> dispose() async {
    AppLogger.log('Disposing RealtimeCommandService');
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
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
    AppLogger.log('Ensuring realtime connection');
    _scheduleReconnect(const Duration(milliseconds: 200));
  }

  void sendCommandAck({
    required String commandId,
    required String command,
    String? deviceId,
    Map<String, dynamic>? additionalData,
  }) {
    if (commandId.isEmpty) return;
    unawaited(
      _sendCommandAckInternal(
        commandId: commandId,
        command: command,
        deviceId: deviceId,
        additionalData: additionalData,
      ),
    );
  }

  Future<void> _subscribeToCommands() async {
    final deviceId = _deviceId;
    if (deviceId == null || deviceId.isEmpty) {
      AppLogger.log('Cannot subscribe - no device ID');
      return;
    }

    AppLogger.log('Attempting to subscribe to realtime commands for device: $deviceId');
    
    await _unsubscribe();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    try {
      final supabase = Supabase.instance.client;
      
      // Close any existing channels
      await supabase.removeAllChannels();
      
      final channelName = 'device-commands-$deviceId';
      AppLogger.log('Creating channel: $channelName');
      
      final channel = supabase
          .channel(channelName)
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'device_commands',
            callback: _handleInsertEvent,
          );

      channel.subscribe((status, [error]) {
        AppLogger.log('Realtime subscription status: $status, error: $error');
        
        if (status == RealtimeSubscribeStatus.subscribed) {
          _reconnectAttempt = 0;
          _isSubscribed = true;
          AppLogger.log('✅ Realtime subscribed for device $deviceId');
          return;
        }

        if (status == RealtimeSubscribeStatus.channelError ||
            status == RealtimeSubscribeStatus.timedOut ||
            status == RealtimeSubscribeStatus.closed) {
          _isSubscribed = false;
          AppLogger.log(
            '❌ Realtime disconnected ($status): ${error ?? 'no error details'}',
          );
          _scheduleReconnect(_nextReconnectDelay());
        }
      });

      _channel = channel;
    } catch (e, stackTrace) {
      AppLogger.log('Failed to subscribe to realtime: $e');
      AppLogger.log('$stackTrace');
      _scheduleReconnect(_nextReconnectDelay());
    }
  }

  Future<void> _unsubscribe() async {
    final existing = _channel;
    _channel = null;
    _isSubscribed = false;
    
    if (existing != null) {
      try {
        AppLogger.log('Removing realtime channel');
        await Supabase.instance.client.removeChannel(existing);
        AppLogger.log('Realtime channel removed successfully');
      } catch (e) {
        AppLogger.log('Failed to remove realtime channel: $e');
      }
    }
  }

  void _handleInsertEvent(PostgresChangePayload payload) {
    try {
      AppLogger.log('Received realtime payload: ${payload.newRecord}');
      
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
      final rowDeviceCandidates = <String>{
        _normalize(row['device_id']),
        _normalize(row['deviceId']),
        _normalize(row['device_hash']),
        _normalize(row['deviceHash']),
      }..removeWhere((id) => id.isEmpty);
      
      final matchedDeviceId = rowDeviceCandidates.firstWhere(
        _acceptedDeviceIds.contains,
        orElse: () => '',
      );

      AppLogger.log('Processing command: $command, ID: $commandId, device candidates: $rowDeviceCandidates, matched: $matchedDeviceId');

      if (commandId.isEmpty) {
        AppLogger.log('Skipping command - empty command ID');
        return;
      }
      
      if (matchedDeviceId.isEmpty) {
        if (command == 'LOCK' || command == 'UNLOCK' || command == 'EXTEND_EMI' || command == 'MARK_PAID') {
          AppLogger.log(
            'Realtime command ignored due to device mismatch. '
            'rowIds=$rowDeviceCandidates acceptedIds=$_acceptedDeviceIds commandId=$commandId command=$command',
          );
        }
        return;
      }
      
      // Process all valid commands, not just LOCK/UNLOCK
      if (_processedCommandIds.contains(commandId) ||
          _inFlightCommandIds.contains(commandId)) {
        AppLogger.log('Command $commandId already processed or in flight');
        return;
      }

      _inFlightCommandIds.add(commandId);
      final event = DeviceRealtimeCommand(
        commandId: commandId,
        command: command,
        deviceId: matchedDeviceId,
        rawRecord: row,
      );
      
      AppLogger.log('Executing command: $command with data: $row');
      unawaited(_executeCommand(event));
    } catch (e, stackTrace) {
      AppLogger.log('Failed to parse realtime payload: $e');
      AppLogger.log('$stackTrace');
    }
  }

  Future<void> _executeCommand(DeviceRealtimeCommand command) async {
    try {
      AppLogger.log('Executing command: ${command.command} with data: ${command.rawRecord}');
      
      final handler = _commandHandler;
      if (handler == null) {
        AppLogger.log('No command handler registered');
        return;
      }
      
      await handler(command);
      AppLogger.log('Command ${command.commandId} executed successfully');
      await _markCommandProcessed(command.commandId);
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
      ConnectivityResult result,
    ) {
      AppLogger.log('Connectivity changed: $result');
      if (result != ConnectivityResult.none) {
        AppLogger.log('Network available - scheduling reconnect');
        _scheduleReconnect(const Duration(milliseconds: 500));
      }
    });
  }

  void _scheduleReconnect(Duration delay) {
    if (!_isStarted) {
      AppLogger.log('Not scheduling reconnect - service not started');
      return;
    }
    
    AppLogger.log('Scheduling reconnect in $delay');
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      unawaited(_reconnect());
    });
  }

  Future<void> _reconnect() async {
    if (!_isStarted || _isReconnecting) {
      AppLogger.log('Not reconnecting - service not started or already reconnecting');
      return;
    }
    
    AppLogger.log('Attempting to reconnect to realtime service');
    final isOnline = await _hasNetworkConnectivity();
    if (!isOnline) {
      AppLogger.log('No network connectivity - scheduling next reconnect');
      _scheduleReconnect(_nextReconnectDelay());
      return;
    }

    _isReconnecting = true;
    try {
      AppLogger.log('Reconnecting to realtime service');
      await _subscribeToCommands();
    } catch (e) {
      AppLogger.log('Reconnection failed: $e');
      _scheduleReconnect(_nextReconnectDelay());
    } finally {
      _isReconnecting = false;
    }
  }

  Duration _nextReconnectDelay() {
    final attempt = _reconnectAttempt++;
    final seconds = min(30, 1 << min(attempt, 5)); // Max 30 seconds
    AppLogger.log('Next reconnect delay: ${seconds}s (attempt $attempt)');
    return Duration(seconds: seconds);
  }

  Future<void> _markCommandProcessed(String commandId) async {
    _processedCommandIds.add(commandId);
    while (_processedCommandIds.length > _maxProcessedCommands) {
      _processedCommandIds.remove(_processedCommandIds.first);
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _processedCommandIdsKey,
        _processedCommandIds.toList(growable: false),
      );
    } catch (e) {
      AppLogger.log('Failed to save processed command IDs: $e');
    }
  }

  Future<void> _loadProcessedCommandIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getStringList(_processedCommandIdsKey) ?? <String>[];
      _processedCommandIds
        ..clear()
        ..addAll(stored);
      AppLogger.log('Loaded ${_processedCommandIds.length} processed command IDs');
    } catch (e) {
      AppLogger.log('Failed to load processed command IDs: $e');
    }
  }

  Future<void> _sendCommandAckInternal({
    required String commandId,
    required String command,
    String? deviceId,
    Map<String, dynamic>? additionalData,
  }) async {
    final resolvedDeviceId = deviceId ?? _deviceId ?? '';
    if (resolvedDeviceId.isEmpty) {
      AppLogger.log('ACK skipped: No device ID');
      return;
    }
    
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
      if (additionalData != null) ...additionalData,
    };

    AppLogger.log('Sending command ACK: $body');

    const maxAttempts = 5;
    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      final isOnline = await _hasNetworkConnectivity();
      if (!isOnline) {
        AppLogger.log('No network connectivity for ACK (attempt ${attempt + 1})');
        if (attempt == maxAttempts - 1) break;
        final delaySeconds = pow(2, attempt).toInt();
        await Future.delayed(Duration(seconds: delaySeconds));
        continue;
      }

      try {
        final response = await http
            .post(ackUri, headers: headers, body: jsonEncode(body))
            .timeout(const Duration(seconds: 10));
            
        AppLogger.log('ACK response status: ${response.statusCode}, body: ${response.body}');
        
        if (response.statusCode >= 200 && response.statusCode < 300) {
          AppLogger.log('✅ ACK sent successfully for command $commandId');
          return;
        } else {
          AppLogger.log('ACK failed with status ${response.statusCode}: ${response.body}');
        }
      } catch (e) {
        AppLogger.log('ACK network error (attempt ${attempt + 1}): $e');
        // Exponential backoff is applied below.
      }

      if (attempt == maxAttempts - 1) {
        AppLogger.log('❌ ACK failed for command $commandId after $maxAttempts attempts');
        break;
      }
      
      final delaySeconds = pow(2, attempt).toInt();
      AppLogger.log('Retrying ACK in $delaySeconds seconds');
      await Future.delayed(Duration(seconds: delaySeconds));
    }
  }

  String _normalize(dynamic value) {
    if (value == null) return '';
    return value.toString().trim();
  }

  bool _isOnlineResult(ConnectivityResult result) {
    return result != ConnectivityResult.none;
  }

  Future<bool> _hasNetworkConnectivity() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return _isOnlineResult(result);
    } catch (e) {
      AppLogger.log('Error checking connectivity: $e');
      return false; // Assume offline on error
    }
  }
}g