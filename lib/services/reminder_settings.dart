enum ReminderProfile { balanced, frequent, minimal }

enum ReminderLanguage { both, bn, en }

class ReminderSettings {
  static ReminderProfile profileFromRaw(String? value) {
    switch (value) {
      case 'frequent':
        return ReminderProfile.frequent;
      case 'minimal':
        return ReminderProfile.minimal;
      default:
        return ReminderProfile.balanced;
    }
  }

  static String profileToRaw(ReminderProfile profile) {
    switch (profile) {
      case ReminderProfile.frequent:
        return 'frequent';
      case ReminderProfile.minimal:
        return 'minimal';
      case ReminderProfile.balanced:
        return 'balanced';
    }
  }

  static ReminderLanguage languageFromRaw(String? value) {
    switch (value) {
      case 'bn':
        return ReminderLanguage.bn;
      case 'en':
        return ReminderLanguage.en;
      default:
        return ReminderLanguage.both;
    }
  }

  static String languageToRaw(ReminderLanguage language) {
    switch (language) {
      case ReminderLanguage.bn:
        return 'bn';
      case ReminderLanguage.en:
        return 'en';
      case ReminderLanguage.both:
        return 'both';
    }
  }
}

