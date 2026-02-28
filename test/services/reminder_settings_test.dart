import 'package:flutter_test/flutter_test.dart';
import 'package:fonex/main.dart';

void main() {
  group('ReminderSettings mapping', () {
    test('profile raw conversion', () {
      expect(
        ReminderSettings.profileFromRaw('frequent'),
        ReminderProfile.frequent,
      );
      expect(
        ReminderSettings.profileFromRaw('minimal'),
        ReminderProfile.minimal,
      );
      expect(
        ReminderSettings.profileFromRaw('unknown'),
        ReminderProfile.balanced,
      );
      expect(
        ReminderSettings.profileToRaw(ReminderProfile.balanced),
        'balanced',
      );
    });

    test('language raw conversion', () {
      expect(
        ReminderSettings.languageFromRaw('bn'),
        ReminderLanguage.bn,
      );
      expect(
        ReminderSettings.languageFromRaw('en'),
        ReminderLanguage.en,
      );
      expect(
        ReminderSettings.languageFromRaw('other'),
        ReminderLanguage.both,
      );
      expect(
        ReminderSettings.languageToRaw(ReminderLanguage.both),
        'both',
      );
    });
  });
}

