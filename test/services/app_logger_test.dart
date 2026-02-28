import 'package:flutter_test/flutter_test.dart';
import 'package:fonex/services/app_logger.dart';

void main() {
  group('AppLogger guardrails', () {
    setUp(() {
      AppLogger.clear();
    });

    test('keeps bounded log count', () {
      for (int i = 0; i < 900; i++) {
        AppLogger.log('log-$i');
      }

      expect(AppLogger.logs.length <= 800, isTrue);
    });

    test('clear removes all logs', () {
      AppLogger.log('hello');
      expect(AppLogger.logs, isNotEmpty);
      AppLogger.clear();
      expect(AppLogger.logs, isEmpty);
    });
  });
}
