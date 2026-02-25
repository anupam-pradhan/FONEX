// =============================================================================
// SUPABASE REALTIME COMMAND LISTENER
// =============================================================================
// Uses Supabase Realtime (already included) - NO additional services needed
// Listens for lock/unlock commands and executes them
// =============================================================================

import 'dart:async';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_logger.dart';

class SupabaseCommandListener {
  static final SupabaseCommandListener _instance =
      SupabaseCommandListener._internal();

  factory SupabaseCommandListener() => _instance;

  SupabaseCommandListener._internal();

  static const String _channel = 'device.lock/channel';
  late MethodChannel _methodChannel;
  RealtimeChannel? _realtimeChannel;
  bool _isListening = false;
  final Set<String> _processedCommands = {};

  void initialize() {
    _methodChannel = const MethodChannel(_channel);
  }

  /// Start listening for commands via Supabase Realtime
  /// This uses your existing Supabase setup (no additional config needed!)
  Future<void> startListening(String deviceId) async {
    if (_isListening) return;

    try {
      final supabase = Supabase.instance.client;

      // Subscribe to device_commands table for this device
      _realtimeChannel = supabase
          .channel('device_commands:device_id=eq.$deviceId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'device_commands',
            callback: _handleCommand,
          );

      _realtimeChannel!.subscribe((status, [error]) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          _isListening = true;
          AppLogger.log('✅ Listening for commands via Supabase');
        } else if (status == RealtimeSubscribeStatus.channelError) {
          _isListening = false;
          AppLogger.log('⚠️ Command listener disconnected, will retry...');
          Future.delayed(const Duration(seconds: 5), () {
            if (!_isListening) {
              startListening(deviceId);
            }
          });
        }
      });

      AppLogger.log(
        '🚀 Supabase command listener started for device: $deviceId',
      );
    } catch (e) {
      AppLogger.log('Error starting listener: $e');
    }
  }

  /// Handle incoming command from Supabase
  void _handleCommand(PostgresChangePayload payload) {
    try {
      final data = Map<String, dynamic>.from(
        payload.newRecord as Map<dynamic, dynamic>,
      );

      final commandId = data['id']?.toString() ?? '';
      final command = (data['command']?.toString() ?? '').toUpperCase();

      if (commandId.isEmpty || command.isEmpty) return;

      // Skip if already processed
      if (_processedCommands.contains(commandId)) return;
      _processedCommands.add(commandId);

      AppLogger.log('🔔 Command received: $command (ID: $commandId)');

      if (command == 'LOCK') {
        _executeLock();
      } else if (command == 'UNLOCK') {
        _executeUnlock();
      }

      // Mark as processed in Supabase
      _markProcessed(commandId);
    } catch (e) {
      AppLogger.log('Error processing command: $e');
    }
  }

  /// Execute LOCK command
  Future<void> _executeLock() async {
    try {
      AppLogger.log('🔒 Executing LOCK...');
      final result = await _methodChannel.invokeMethod<bool>('startDeviceLock');
      if (result == true) {
        AppLogger.log('✅ Device LOCKED successfully');
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('device_locked', true);
      } else {
        AppLogger.log('❌ Lock failed - Device Owner not set?');
      }
    } on PlatformException catch (e) {
      AppLogger.log('Platform error during lock: $e');
    }
  }

  /// Execute UNLOCK command
  Future<void> _executeUnlock() async {
    try {
      AppLogger.log('🔓 Executing UNLOCK...');
      final result = await _methodChannel.invokeMethod<bool>('stopDeviceLock');
      if (result == true) {
        AppLogger.log('✅ Device UNLOCKED successfully');
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('device_locked', false);
      } else {
        AppLogger.log('❌ Unlock failed');
      }
    } on PlatformException catch (e) {
      AppLogger.log('Platform error during unlock: $e');
    }
  }

  /// Mark command as processed in Supabase
  Future<void> _markProcessed(String commandId) async {
    try {
      await Supabase.instance.client
          .from('device_commands')
          .update({
            'processed': true,
            'processed_at': DateTime.now().toIso8601String(),
          })
          .eq('id', commandId);
    } catch (e) {
      AppLogger.log('Error marking command processed: $e');
    }
  }

  /// Stop listening
  Future<void> stopListening() async {
    try {
      if (_realtimeChannel != null) {
        await Supabase.instance.client.removeChannel(_realtimeChannel!);
      }
      _isListening = false;
      AppLogger.log('Stopped listening for commands');
    } catch (e) {
      AppLogger.log('Error stopping listener: $e');
    }
  }

  bool get isListening => _isListening;
}
