import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fonex/services/command_security_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('CommandSecurityService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('allows unsigned command when enforcement is disabled', () async {
      final result = await CommandSecurityService().validateAndRecord(
        payload: <String, dynamic>{
          'command_id': 'cmd-unsigned-1',
          'device_id': 'dev-1',
        },
        action: 'LOCK',
        matchedDeviceId: 'dev-1',
        source: 'test',
        enforceSignedOverride: false,
      );

      expect(result.allowed, isTrue);
      expect(result.reason, contains('unsigned_allowed'));
    });

    test('rejects unsigned command when enforcement is enabled', () async {
      final result = await CommandSecurityService().validateAndRecord(
        payload: <String, dynamic>{
          'command_id': 'cmd-unsigned-2',
          'device_id': 'dev-1',
        },
        action: 'LOCK',
        matchedDeviceId: 'dev-1',
        source: 'test',
        enforceSignedOverride: true,
        secretOverride: 'top-secret',
      );

      expect(result.allowed, isFalse);
      expect(result.reason, contains('missing_signature_fields'));
    });

    test('accepts valid signed command and blocks replay', () async {
      const secret = 'my-signing-secret';
      const commandId = 'cmd-signed-1';
      const deviceId = 'dev-1';
      const action = 'LOCK';
      const issuedAt = 1_800_000_000;
      const nonce = 'xyz';
      final canonical = '$commandId|$action|$deviceId|$issuedAt|$nonce';
      final signature = hmacSha256Hex(secret, canonical);

      final payload = <String, dynamic>{
        'command_id': commandId,
        'device_id': deviceId,
        'command_ts': issuedAt,
        'command_nonce': nonce,
        'command_signature': signature,
      };

      final firstResult = await CommandSecurityService().validateAndRecord(
        payload: payload,
        action: action,
        matchedDeviceId: deviceId,
        source: 'test',
        enforceSignedOverride: true,
        secretOverride: secret,
        maxAgeSecondsOverride: 999999,
        nowOverride: DateTime.fromMillisecondsSinceEpoch(issuedAt * 1000),
      );
      expect(firstResult.allowed, isTrue);
      expect(firstResult.signatureChecked, isTrue);

      final replayResult = await CommandSecurityService().validateAndRecord(
        payload: payload,
        action: action,
        matchedDeviceId: deviceId,
        source: 'test',
        enforceSignedOverride: true,
        secretOverride: secret,
        maxAgeSecondsOverride: 999999,
        nowOverride: DateTime.fromMillisecondsSinceEpoch(issuedAt * 1000),
      );
      expect(replayResult.allowed, isFalse);
      expect(replayResult.reason, contains('replay_detected'));
    });
  });
}

String hmacSha256Hex(String secret, String canonical) {
  final digest = Hmac(
    sha256,
    utf8.encode(secret),
  ).convert(utf8.encode(canonical)).bytes;
  return digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
