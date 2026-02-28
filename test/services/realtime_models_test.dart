import 'package:flutter_test/flutter_test.dart';
import 'package:fonex/services/realtime_command_service.dart';

void main() {
  group('AckQueueItem serialization', () {
    test('round-trips through json', () {
      final item = AckQueueItem(
        commandId: 'cmd-123',
        command: 'LOCK',
        deviceId: '445564',
        queuedAt: DateTime(2026, 2, 28, 12, 0, 0),
        retryCount: 3,
        lastStatusCode: 500,
        lastResult: 'server_error',
      );

      final parsed = AckQueueItem.fromJson(item.toJson());
      expect(parsed, isNotNull);
      expect(parsed!.commandId, 'cmd-123');
      expect(parsed.command, 'LOCK');
      expect(parsed.deviceId, '445564');
      expect(parsed.retryCount, 3);
      expect(parsed.lastStatusCode, 500);
      expect(parsed.lastResult, 'server_error');
    });

    test('returns null for invalid payload', () {
      final parsed = AckQueueItem.fromJson(<String, dynamic>{
        'command_id': '',
        'command': '',
        'device_id': '',
      });
      expect(parsed, isNull);
    });
  });
}

