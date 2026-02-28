// =============================================================================
// FONEX CONFIGURATION FILE
// =============================================================================
// Update these values according to your store and server setup
// =============================================================================

class FonexConfig {
  // ===========================================================================
  // SERVER CONFIGURATION
  // ===========================================================================

  /// Backend server base URL
  /// Update this to your actual server URL
  static const String serverBaseUrl =
      'https://v0-fonex-backend-system-k6.vercel.app/api/v1/devices';

  /// API timeout in seconds
  static const int apiTimeoutSeconds = 10;

  /// Server check-in interval in minutes
  static const int serverCheckInIntervalMinutes = 5;

  /// Supabase realtime configuration (set using --dart-define in production)
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://itwyfrwkhohdrgpboagf.supabase.co',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml0d3lmcndraG9oZHJncGJvYWdmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE1OTczODQsImV4cCI6MjA4NzE3MzM4NH0.sYiwReiVjaRtwVr2rMsppJHpGpA-dkQFjIByZ61HAU4',
  );

  /// Device secret used for command ACK calls
  static const String deviceSecret = String.fromEnvironment(
    'DEVICE_SECRET',
    defaultValue:
        'bd2d3ee11180dc690715abf92a51308096625b0c16b48da07d651c8151d1e3c9',
  );

  /// Device command ACK endpoint path
  static const String deviceAckPath = '/api/device-ack';

  // ===========================================================================
  // STORE INFORMATION
  // ===========================================================================

  /// Store name (displayed on wallpaper and lock screen)
  static const String storeName = 'Fonex Powerd By Roy Communication';

  /// Store address (optional, for display)
  static const String storeAddress =
      'Narayanpur, Namkhana,  West Bengal - 743347';

  /// Primary support phone number
  static const String supportPhone1 = '+918388855549';

  /// Secondary support phone number
  static const String supportPhone2 = '+919635252455';

  // ===========================================================================
  // EMI CONFIGURATION
  // ===========================================================================

  /// Number of days before device locks if EMI not paid
  static const int lockAfterDays = 30;

  /// SIM absent grace period (days before locking)
  static const int simAbsentLockDays = 7;

  // ===========================================================================
  // SECURITY CONFIGURATION
  // ===========================================================================

  /// Maximum PIN attempts before cooldown
  static const int maxPinAttempts = 3;

  /// Cooldown period in seconds after max attempts
  static const int cooldownSeconds = 30;

  // ===========================================================================
  // APP CONFIGURATION
  // ===========================================================================

  /// App version
  static const String appVersion = '1.0.0';

  /// Channel name for native communication
  static const String channelName = 'device.lock/channel';

  // ===========================================================================
  // ADVANCED SETTINGS (Usually don't need to change)
  // ===========================================================================

  /// SharedPreferences keys
  static const String keyLastVerified = 'last_verified';
  static const String keyDeviceLocked = 'device_locked';
  static const String keySimAbsentSince = 'sim_absent_since';
  static const String keyPaidInFull = 'is_paid_in_full';

  // ===========================================================================
  // VALIDATION
  // ===========================================================================

  /// Validate configuration on app start
  static bool validate() {
    if (serverBaseUrl.isEmpty) {
      throw Exception('Server base URL is not configured');
    }
    if (storeName.isEmpty) {
      throw Exception('Store name is not configured');
    }
    if (supportPhone1.isEmpty) {
      throw Exception('Support phone number 1 is not configured');
    }
    if (lockAfterDays <= 0) {
      throw Exception('Lock after days must be greater than 0');
    }
    return true;
  }
}
