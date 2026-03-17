import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

class CommandAuthResult {
  const CommandAuthResult({
    required this.allowed,
    required this.reason,
    this.signatureChecked = false,
  });

  final bool allowed;
  final String reason;
  final bool signatureChecked;
}

class CommandSecurityService {
  CommandSecurityService._internal();
  static final CommandSecurityService _instance =
      CommandSecurityService._internal();
  factory CommandSecurityService() => _instance;

  static const String _keySeenCommands = 'signed_command_seen_ids';
  static const int _maxSeenCommands = 300;
  static const int _futureSkewSeconds = 60;

  static const Set<String> _protectedActions = <String>{
    'LOCK',
    'UNLOCK',
    'EXTEND',
    'EXTEND_DAYS',
    'PAID',
    'PAID_FULL',
    'PAID_IN_FULL',
    'MARK_PAID_IN_FULL',
  };

  Future<CommandAuthResult> validateAndRecord({
    required Map<String, dynamic> payload,
    required String action,
    required String matchedDeviceId,
    required String source,
    String? secretOverride,
    bool? enforceSignedOverride,
    int? maxAgeSecondsOverride,
    DateTime? nowOverride,
  }) async {
    final normalizedAction = action.trim().toUpperCase();
    if (!_protectedActions.contains(normalizedAction)) {
      return const CommandAuthResult(
        allowed: true,
        reason: 'action_not_guarded',
      );
    }

    final now = nowOverride ?? DateTime.now().toUtc();
    final enforceSigned =
        enforceSignedOverride ?? FonexConfig.enforceSignedCommands;
    final secret = (secretOverride ?? FonexConfig.commandSigningSecret).trim();
    final maxAgeSeconds =
        maxAgeSecondsOverride ?? FonexConfig.commandSignatureMaxAgeSeconds;

    final commandId = _firstNonEmpty(payload, const [
      'command_id',
      'id',
      'commandId',
    ]);
    final signature = _firstNonEmpty(payload, const [
      'command_signature',
      'signature',
      'sig',
    ]);
    final nonce = _firstNonEmpty(payload, const ['command_nonce', 'nonce']);
    final targetDevice = _firstNonEmpty(payload, const [
      'device_id',
      'device_hash',
      'deviceId',
      'deviceHash',
    ]);
    final issuedAtSeconds = _parseEpochSeconds(
      _firstNonNull(payload, const [
        'command_ts',
        'issued_at',
        'timestamp',
        'created_at',
      ]),
    );

    if (targetDevice.isNotEmpty &&
        matchedDeviceId.isNotEmpty &&
        targetDevice != matchedDeviceId) {
      return CommandAuthResult(
        allowed: false,
        reason: 'device_mismatch:$source',
      );
    }

    if (commandId.isNotEmpty && await _isReplay(commandId)) {
      return CommandAuthResult(
        allowed: false,
        reason: 'replay_detected:$source',
      );
    }

    final signaturePresent = signature.isNotEmpty;
    final shouldVerify = enforceSigned || signaturePresent;
    if (!shouldVerify) {
      if (commandId.isNotEmpty) {
        await _markSeen(commandId);
      }
      return CommandAuthResult(
        allowed: true,
        reason: 'unsigned_allowed:$source',
      );
    }

    if (secret.isEmpty) {
      return CommandAuthResult(
        allowed: false,
        reason: 'missing_signing_secret:$source',
      );
    }
    if (!signaturePresent || commandId.isEmpty || issuedAtSeconds == null) {
      return CommandAuthResult(
        allowed: false,
        reason: 'missing_signature_fields:$source',
      );
    }

    final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;
    final ageSeconds = nowSeconds - issuedAtSeconds;
    if (ageSeconds < -_futureSkewSeconds || ageSeconds > maxAgeSeconds) {
      return CommandAuthResult(
        allowed: false,
        reason: 'signature_time_invalid:$source',
      );
    }

    final canonicalTarget = targetDevice.isNotEmpty
        ? targetDevice
        : matchedDeviceId;
    final canonical =
        '$commandId|$normalizedAction|$canonicalTarget|$issuedAtSeconds|$nonce';
    if (!_isSignatureMatch(
      secret: secret,
      canonical: canonical,
      received: signature,
    )) {
      return CommandAuthResult(
        allowed: false,
        reason: 'signature_mismatch:$source',
      );
    }

    await _markSeen(commandId);
    return CommandAuthResult(
      allowed: true,
      reason: 'signature_verified:$source',
      signatureChecked: true,
    );
  }

  String _firstNonEmpty(Map<String, dynamic> payload, List<String> keys) {
    for (final key in keys) {
      final value = payload[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  Object? _firstNonNull(Map<String, dynamic> payload, List<String> keys) {
    for (final key in keys) {
      if (payload.containsKey(key) && payload[key] != null) {
        return payload[key];
      }
    }
    return null;
  }

  int? _parseEpochSeconds(Object? value) {
    if (value == null) return null;
    if (value is num) {
      final v = value.toInt();
      return v > 1000000000000 ? (v ~/ 1000) : v;
    }
    final raw = value.toString().trim();
    if (raw.isEmpty) return null;
    final parsedInt = int.tryParse(raw);
    if (parsedInt != null) {
      return parsedInt > 1000000000000 ? (parsedInt ~/ 1000) : parsedInt;
    }
    final parsedDate = DateTime.tryParse(raw);
    if (parsedDate != null) {
      return parsedDate.toUtc().millisecondsSinceEpoch ~/ 1000;
    }
    return null;
  }

  bool _isSignatureMatch({
    required String secret,
    required String canonical,
    required String received,
  }) {
    final mac = Hmac(sha256, utf8.encode(secret));
    final digest = mac.convert(utf8.encode(canonical)).bytes;
    final expectedHex = _toHex(digest);
    final expectedBase64 = base64Encode(digest);
    final expectedBase64Url = base64UrlEncode(digest).replaceAll('=', '');

    final normalizedReceived = received.trim();
    return _constantTimeEquals(normalizedReceived.toLowerCase(), expectedHex) ||
        _constantTimeEquals(normalizedReceived, expectedBase64) ||
        _constantTimeEquals(
          normalizedReceived.replaceAll('=', ''),
          expectedBase64Url,
        );
  }

  String _toHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  Future<bool> _isReplay(String commandId) async {
    final seen = await _loadSeen();
    return seen.contains(commandId);
  }

  Future<void> _markSeen(String commandId) async {
    final prefs = await SharedPreferences.getInstance();
    final seen = await _loadSeen();
    if (seen.contains(commandId)) return;
    final updated = <String>[commandId, ...seen];
    if (updated.length > _maxSeenCommands) {
      updated.removeRange(_maxSeenCommands, updated.length);
    }
    await prefs.setStringList(_keySeenCommands, updated);
  }

  Future<List<String>> _loadSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keySeenCommands) ?? const <String>[];
  }
}
