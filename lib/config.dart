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
  static const String serverBaseUrl = 'https://fonex-backend-mobile-system.vercel.app/api/v1/devices';
  
  /// API timeout in seconds
  static const int apiTimeoutSeconds = 10;
  
  /// Server check-in interval in minutes
  static const int serverCheckInIntervalMinutes = 5;
  
  // ===========================================================================
  // STORE INFORMATION
  // ===========================================================================
  
  /// Store name (displayed on wallpaper and lock screen)
  static const String storeName = 'Roy Communication';
  
  /// Store address (optional, for display)
  static const String storeAddress = 'Visit our store for EMI payment';
  
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
