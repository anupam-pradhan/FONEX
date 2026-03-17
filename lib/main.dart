import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:convert';
import 'config.dart';
import 'services/app_logger.dart';
import 'services/command_security_service.dart';
import 'services/device_storage_service.dart';
import 'services/realtime_command_service.dart';
import 'services/sync_service.dart';
import 'services/device_state_manager.dart';
import 'services/crash_reporter.dart';
import 'services/reminder_settings.dart';
// SupabaseCommandListener removed: it duplicated RealtimeCommandService and
// lacked device_id filtering, causing commands for other devices to execute
// locally and every command to be processed twice.
// =============================================================================
// FONEX Powered by Roy Communication — Device Control System
// =============================================================================
// Production-ready device lock for mobile retail financing.
// Uses Device Owner + DevicePolicyManager + Lock Task (no root, no Accessibility).
// =============================================================================

// Use configuration from config.dart
const String _channelName = FonexConfig.channelName;
const int _lockAfterDays = FonexConfig.lockAfterDays;
const int _simAbsentLockDays = FonexConfig.simAbsentLockDays;
const int _maxPinAttempts = FonexConfig.maxPinAttempts;
const int _cooldownSeconds = FonexConfig.cooldownSeconds;
const String _keyLastVerified = FonexConfig.keyLastVerified;
const String _keyDeviceLocked = FonexConfig.keyDeviceLocked;
const String _keySimAbsentSince = FonexConfig.keySimAbsentSince;
const String _keyLockWindowDays = 'lock_window_days';
const String _keyTimerAnchorMs = 'timer_anchor_ms';
const String _keyBackgroundPromptShown = 'background_prompt_shown';
const int _fallbackServerCheckSeconds = 60;
const String _serverBaseUrl = FonexConfig.serverBaseUrl;
const String _supportPhone1 = FonexConfig.supportPhone1;
const String _supportPhone2 = FonexConfig.supportPhone2;
const String _storeName = FonexConfig.storeName;
const String _keyReminderEnabled = 'notif_reminder_enabled';
const String _keyReminderProfile = 'notif_reminder_profile';
const String _keyReminderLanguage = 'notif_reminder_language';
const String _keyLastNotifSignature = 'last_notif_signature';
const String _keyLastNotifMs = 'last_notif_ms';
const String _keySupportUnlockUntilMs = 'support_unlock_until_ms';
const String _keyAntiKillAutoStartDone = 'antikill_autostart_done';
const String _keyAntiKillBatteryDone = 'antikill_battery_done';

// =============================================================================
// DEVICE HASH UTILITY — Offline Algorithmic PIN Generation
// =============================================================================
class DeviceHashUtil {
  static const String _keySalt = 'device_hash_salt';
  static const String _keyStableHash = 'device_hash_stable';

  static Future<String> getDeviceHash() async {
    final prefs = await SharedPreferences.getInstance();
    final stableHash = prefs.getString(_keyStableHash);
    if (stableHash != null && RegExp(r'^\d{6}$').hasMatch(stableHash)) {
      return stableHash;
    }

    String? salt = prefs.getString(_keySalt);
    if (salt == null) {
      final random = Random.secure();
      const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      salt = String.fromCharCodes(
        Iterable.generate(
          8,
          (_) => chars.codeUnitAt(random.nextInt(chars.length)),
        ),
      );
      await prefs.setString(_keySalt, salt);
    }

    final now = DateTime.now();
    final data = '$salt-${now.year}-${now.month}';

    int hash = 5381;
    for (int i = 0; i < data.length; i++) {
      hash = ((hash << 5) + hash) + data.codeUnitAt(i);
      hash = hash & 0xFFFFFFFF; // 32-bit simulated bounds
    }
    final computedHash = (hash.abs() % 1000000).toString().padLeft(6, '0');
    await prefs.setString(_keyStableHash, computedHash);
    return computedHash;
  }

  static String getExpectedPin(String deviceHash) {
    if (deviceHash == '------') return '------';
    int hash = int.parse(deviceHash);
    int pin = (hash * 73 + 123456) % 1000000;
    return pin.toString().padLeft(6, '0');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CrashReporter.initialize();
  if (FonexConfig.supabaseUrl.isNotEmpty &&
      FonexConfig.supabaseAnonKey.isNotEmpty) {
    try {
      await Supabase.initialize(
        url: FonexConfig.supabaseUrl,
        anonKey: FonexConfig.supabaseAnonKey,
      );
    } catch (e) {
      AppLogger.log('Supabase initialization failed: $e');
    }
  } else {
    debugPrint(
      'Supabase realtime is disabled (missing SUPABASE_URL or SUPABASE_ANON_KEY).',
    );
  }

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runZonedGuarded(
    () {
      runApp(const FonexApp());
    },
    (error, stack) {
      CrashReporter.recordZoneError(error, stack);
    },
  );
}

// =============================================================================
// COLOR PALETTE
// =============================================================================
class FonexColors {
  static const bg = Color(0xFF06080F);
  static const surface = Color(0xFF0E1219);
  static const card = Color(0xFF141B27);
  static const cardBorder = Color(0xFF1E2A3A);
  static const accent = Color(0xFF3B82F6);
  static const accentLight = Color(0xFF60A5FA);
  static const accentDark = Color(0xFF1D4ED8);
  static const purple = Color(0xFF8B5CF6);
  static const cyan = Color(0xFF22D3EE);
  static const green = Color(0xFF22C55E);
  static const red = Color(0xFFEF4444);
  static const orange = Color(0xFFF59E0B);
  static const textPrimary = Color(0xFFF1F5F9);
  static const textSecondary = Color(0xFF94A3B8);
  static const textMuted = Color(0xFF475569);
}

// =============================================================================
// APP ROOT
// =============================================================================
class FonexApp extends StatelessWidget {
  const FonexApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FONEX',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: FonexColors.bg,
        colorScheme: ColorScheme.dark(
          surface: FonexColors.bg,
          primary: FonexColors.accent,
          secondary: FonexColors.purple,
        ),
      ),
      home: const DeviceControlHome(),
    );
  }
}

// =============================================================================
// ANIMATED GRADIENT BACKGROUND
// =============================================================================
class AnimatedGradientBg extends StatefulWidget {
  final Widget child;
  final List<Color> colors;

  const AnimatedGradientBg({
    super.key,
    required this.child,
    this.colors = const [
      Color(0xFF06080F),
      Color(0xFF0A1628),
      Color(0xFF0F0A28),
      Color(0xFF06080F),
    ],
  });

  @override
  State<AnimatedGradientBg> createState() => _AnimatedGradientBgState();
}

class _AnimatedGradientBgState extends State<AnimatedGradientBg>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          constraints: const BoxConstraints.expand(),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment(
                0.5 + 0.5 * sin(_controller.value * pi),
                1.0 + 0.3 * cos(_controller.value * pi),
              ),
              colors: widget.colors,
            ),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

// =============================================================================
// FLOATING PARTICLES — subtle ambient effect
// =============================================================================
class FloatingParticles extends StatefulWidget {
  final int count;
  const FloatingParticles({super.key, this.count = 20});

  @override
  State<FloatingParticles> createState() => _FloatingParticlesState();
}

class _FloatingParticlesState extends State<FloatingParticles>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<_Particle> _particles;
  final _random = Random();

  @override
  void initState() {
    super.initState();
    _particles = List.generate(widget.count, (_) => _Particle(_random));
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          size: MediaQuery.of(context).size,
          painter: _ParticlePainter(_particles, _controller.value),
        );
      },
    );
  }
}

class _Particle {
  final double x, y, size, speed, opacity;
  _Particle(Random r)
    : x = r.nextDouble(),
      y = r.nextDouble(),
      size = 1.0 + r.nextDouble() * 2.5,
      speed = 0.2 + r.nextDouble() * 0.8,
      opacity = 0.05 + r.nextDouble() * 0.15;
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double animValue;
  _ParticlePainter(this.particles, this.animValue);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final dy = (p.y + animValue * p.speed) % 1.0;
      final paint = Paint()
        ..color = FonexColors.accent.withValues(alpha: p.opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawCircle(
        Offset(p.x * size.width, dy * size.height),
        p.size,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// =============================================================================
// GLASSMORPHIC CARD
// =============================================================================
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? borderColor;
  final double borderRadius;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.borderColor,
    this.borderRadius = 20,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        color: FonexColors.card.withValues(alpha: 0.7),
        border: Border.all(
          color: borderColor ?? FonexColors.cardBorder.withValues(alpha: 0.5),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

// =============================================================================
// GLOW ICON
// =============================================================================
class GlowIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final double containerSize;

  const GlowIcon({
    super.key,
    required this.icon,
    required this.color,
    this.size = 28,
    this.containerSize = 56,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: containerSize,
      height: containerSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: 0.25),
            color.withValues(alpha: 0.05),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.2),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Icon(icon, color: color, size: size),
    );
  }
}

// =============================================================================
// FONEX LOGO — uses real brand image
// =============================================================================
class FonexLogo extends StatelessWidget {
  final double size;
  const FonexLogo({super.key, this.size = 56});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: FonexColors.accent.withValues(alpha: 0.35),
            blurRadius: 20,
            spreadRadius: 2,
          ),
          BoxShadow(
            color: FonexColors.purple.withValues(alpha: 0.2),
            blurRadius: 30,
            spreadRadius: 4,
          ),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/images/fonex-logo.jpeg',
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: size,
            height: size,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [FonexColors.accent, FonexColors.purple],
              ),
            ),
            child: Center(
              child: Text(
                'F',
                style: GoogleFonts.inter(
                  fontSize: size * 0.45,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// WALLPAPER WITH STORE NAME AND DUE INFO
// =============================================================================
class StoreWallpaper extends StatelessWidget {
  final String storeName;
  final int daysRemaining;
  final bool isLocked;
  final DateTime? nextPaymentDate;
  final Widget child;

  const StoreWallpaper({
    super.key,
    required this.storeName,
    required this.daysRemaining,
    required this.isLocked,
    this.nextPaymentDate,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final warningColor = isLocked
        ? FonexColors.red
        : daysRemaining <= 7
        ? FonexColors.orange
        : FonexColors.accent;
    final warningText = isLocked
        ? 'DEVICE LOCKED • DUE AMOUNT PENDING'
        : 'DUE AMOUNT PENDING • PAY BEFORE DUE DATE';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            FonexColors.bg,
            FonexColors.surface,
            FonexColors.card,
            FonexColors.bg,
          ],
        ),
      ),
      child: Stack(
        children: [
          // Background pattern
          Positioned.fill(
            child: CustomPaint(painter: _WallpaperPatternPainter()),
          ),
          // Store info overlay at top
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      FonexColors.card.withValues(alpha: 0.95),
                      FonexColors.card.withValues(alpha: 0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            storeName,
                            style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: FonexColors.textPrimary,
                              letterSpacing: 1,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Due Payment Notice',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: FonexColors.textSecondary,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isLocked
                            ? FonexColors.red.withValues(alpha: 0.2)
                            : daysRemaining <= 7
                            ? FonexColors.orange.withValues(alpha: 0.2)
                            : FonexColors.green.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isLocked
                              ? FonexColors.red
                              : daysRemaining <= 7
                              ? FonexColors.orange
                              : FonexColors.green,
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        children: [
                          Text(
                            isLocked ? 'LOCKED' : '$daysRemaining Days',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isLocked
                                  ? FonexColors.red
                                  : daysRemaining <= 7
                                  ? FonexColors.orange
                                  : FonexColors.green,
                            ),
                          ),
                          if (nextPaymentDate != null && !isLocked)
                            Text(
                              'Due: ${_formatDate(nextPaymentDate!)}',
                              style: GoogleFonts.inter(
                                fontSize: 9,
                                color: FonexColors.textMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 78,
            left: 12,
            right: 12,
            child: SafeArea(
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      colors: [
                        warningColor.withValues(alpha: 0.22),
                        warningColor.withValues(alpha: 0.08),
                      ],
                    ),
                    border: Border.all(
                      color: warningColor.withValues(alpha: 0.55),
                    ),
                  ),
                  child: Row(
                    children: [
                      const FonexLogo(size: 20),
                      const SizedBox(width: 8),
                      Icon(
                        isLocked
                            ? Icons.lock_rounded
                            : Icons.warning_amber_rounded,
                        size: 16,
                        color: warningColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          warningText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: FonexColors.textPrimary,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      if (!isLocked)
                        Text(
                          '$daysRemaining d',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: warningColor,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Main content
          child,
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _WallpaperPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = FonexColors.accent.withValues(alpha: 0.03)
      ..style = PaintingStyle.fill;

    // Draw subtle grid pattern
    for (double x = 0; x < size.width; x += 60) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        paint..color = FonexColors.accent.withValues(alpha: 0.02),
      );
    }
    for (double y = 0; y < size.height; y += 60) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        paint..color = FonexColors.accent.withValues(alpha: 0.02),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// =============================================================================
// DEVICE CONTROL HOME — Main controller
// =============================================================================
class DeviceControlHome extends StatefulWidget {
  const DeviceControlHome({super.key});

  @override
  State<DeviceControlHome> createState() => _DeviceControlHomeState();
}

class _DeviceControlHomeState extends State<DeviceControlHome>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel(_channelName);
  static const String _keyReminder30Date = 'reminder_last_30_date';
  static const String _keyReminderSundayDate = 'reminder_last_sunday_date';
  static const String _keyReminderThreeDaysMs = 'reminder_last_3days_ms';
  static const String _keyReminderOneDayMs = 'reminder_last_1day_ms';

  bool _isDeviceOwner = false;
  bool _isDeviceLocked = false;
  bool _isLoading = true;
  bool _isPaidInFull = false;
  int _daysRemaining = 30;
  int _lockWindowDays = _lockAfterDays;
  bool _isServerConnected = false;
  String _serverStatusMessage = 'Connecting...';
  DateTime? _lastServerSync;
  bool _isConnecting = false;
  bool _reminderEnabled = true;
  ReminderProfile _reminderProfile = ReminderProfile.balanced;
  ReminderLanguage _reminderLanguage = ReminderLanguage.both;
  String? _deviceHash;
  String? _realtimeDeviceId;
  bool _isAppInForeground = true;
  int _backgroundHeartbeatTicks = 0;

  Timer? _simCheckTimer;
  Timer? _serverCheckInTimer;
  Timer? _localReminderTimer;

  @override
  void initState() {
    super.initState();
    // Initialize all services
    WidgetsBinding.instance.addObserver(this);
    DeviceStateManager().initialize();
    SyncService().initialize();
    unawaited(_initialize());

    // RealtimeCommandService handles all Supabase realtime commands
    // (SupabaseCommandListener was removed to prevent duplicate processing)

    // Poll SIM state every 60 seconds while app is active (optimized: only when needed)
    _simCheckTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!mounted || _isPaidInFull) return;
      if (!_isAppInForeground) {
        // Background guardrail: SIM checks every 5 minutes max.
        if ((_backgroundHeartbeatTicks % 5) != 0) return;
      }
      _checkSimState();
    });

    // Frequent fallback heartbeat; effective interval remains larger while realtime is healthy.
    _serverCheckInTimer = Timer.periodic(
      const Duration(seconds: _fallbackServerCheckSeconds),
      (_) {
        if (!_isAppInForeground) {
          _backgroundHeartbeatTicks++;
        } else {
          _backgroundHeartbeatTicks = 0;
        }

        RealtimeCommandService().ensureConnected();
        if (!_isAppInForeground) {
          unawaited(RealtimeCommandService().retryPendingAcks(maxItems: 2));
        }
        if (!mounted || _isConnecting) return;
        if (!_isPaidInFull) {
          unawaited(_checkTimerAndLock());
        }

        final realtimeHealthy = RealtimeCommandService().isSubscribed;
        final lastSync = _lastServerSync;
        final requiredIntervalMinutes = _isAppInForeground
            ? FonexConfig.serverCheckInIntervalMinutes
            : 1;
        final minutesSinceLastSync = lastSync == null
            ? requiredIntervalMinutes
            : DateTime.now().difference(lastSync).inMinutes;
        final shouldCheckNow =
            !realtimeHealthy || minutesSinceLastSync >= requiredIntervalMinutes;
        if (shouldCheckNow) {
          unawaited(_serverCheckIn());
        }
      },
    );

    _startLocalReminderEngine();
  }

  @override
  void dispose() {
    _simCheckTimer?.cancel();
    _serverCheckInTimer?.cancel();
    _localReminderTimer?.cancel();
    SyncService().dispose();
    unawaited(RealtimeCommandService().dispose());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// SIM-absent logic: lock only after 7 continuous days without a SIM.
  Future<void> _checkSimState() async {
    if (!_isDeviceOwner || _isDeviceLocked || _isPaidInFull) return;
    if (await _isSupportUnlockWindowActive()) {
      AppLogger.log('SIM lock check skipped: support unlock window is active');
      return;
    }
    try {
      final simState = await _channel.invokeMethod<int>('getSimState');
      final prefs = await SharedPreferences.getInstance();

      if (simState == 1) {
        // SIM_STATE_ABSENT — record first absence if not already recorded
        final absentSince = prefs.getInt(_keySimAbsentSince);
        if (absentSince == null) {
          await prefs.setInt(
            _keySimAbsentSince,
            DateTime.now().millisecondsSinceEpoch,
          );
          AppLogger.log('SIM absent detected — grace period started (7 days).');
        } else {
          final daysMissing = DateTime.now()
              .difference(DateTime.fromMillisecondsSinceEpoch(absentSince))
              .inDays;
          debugPrint(
            'SIM absent for $daysMissing days (lock after $_simAbsentLockDays).',
          );
          if (daysMissing >= _simAbsentLockDays) {
            debugPrint(
              'SIM absent >$_simAbsentLockDays days — locking device.',
            );
            final locked = await _engageDeviceLock();
            if (locked && mounted) {
              setState(() {
                _isDeviceLocked = true;
                _daysRemaining = 0;
              });
            }
          }
        }
      } else {
        // SIM present — clear the absent timer
        if (prefs.containsKey(_keySimAbsentSince)) {
          await prefs.remove(_keySimAbsentSince);
          AppLogger.log('SIM detected — grace period cleared.');
        }
      }
    } on PlatformException catch (e) {
      AppLogger.log('Error checking SIM state: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isAppInForeground = state == AppLifecycleState.resumed;
    if (!_isAppInForeground) {
      return;
    }
    if (mounted) {
      // Debounce rapid state changes
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          unawaited(_reloadReminderSettings());
          unawaited(_refreshLockStateFromNative());
          _checkTimerAndLock();
          _checkSimState();
          unawaited(_ensureConnectivityForLockedMode());
          unawaited(_ensureBackgroundKillProtection(allowUserPrompt: false));
          RealtimeCommandService().onAppResumed();
          RealtimeCommandService().ensureConnected();
          unawaited(_runLocalReminderCheck());
          // Immediate server check-in when app resumes for accurate status
          if (!_isConnecting) unawaited(_serverCheckIn());
        }
      });
    }
  }

  Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final isPaidInFull = prefs.getBool('is_paid_in_full') == true;
    final storedWindow = _readLockWindowDays(prefs);
    _reminderEnabled = prefs.getBool(_keyReminderEnabled) ?? true;
    _reminderProfile = ReminderSettings.profileFromRaw(
      prefs.getString(_keyReminderProfile),
    );
    _reminderLanguage = ReminderSettings.languageFromRaw(
      prefs.getString(_keyReminderLanguage),
    );
    _lockWindowDays = storedWindow;
    _daysRemaining = storedWindow;

    await _checkDeviceOwner();
    await _refreshLockStateFromNative();
    if (isPaidInFull) {
      await _activatePaidInFullMode(refreshOwnerState: true);
    } else {
      await _activateDueAmountMode(days: storedWindow);
    }
    unawaited(_ensureBackgroundKillProtection(allowUserPrompt: true));
    _deviceHash = await DeviceHashUtil.getDeviceHash();
    _realtimeDeviceId = _deviceHash;
    unawaited(_syncNativeDeviceIdentifiers());
    await _startRealtimeListener();
    if (!_isPaidInFull) {
      await _checkTimerAndLock();
    }
    await _runLocalReminderCheck();
    // Attempt server check-in (non-blocking, offline-safe)
    unawaited(_serverCheckIn());
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _syncNativeDeviceIdentifiers() async {
    final deviceHash = _deviceHash?.trim();
    final realtimeDeviceId = _realtimeDeviceId?.trim();
    if (deviceHash == null || deviceHash.isEmpty) return;
    try {
      await _channel.invokeMethod('setDeviceIdentifiers', {
        'device_hash': deviceHash,
        'device_id': (realtimeDeviceId?.isNotEmpty ?? false)
            ? realtimeDeviceId
            : deviceHash,
      });
      AppLogger.log(
        'Native identifiers synced: '
        'device_hash=$deviceHash device_id=${realtimeDeviceId ?? deviceHash}',
      );
    } catch (e) {
      AppLogger.log('Native identifier sync skipped: $e');
    }
  }

  Future<void> _reloadReminderSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _reminderEnabled = prefs.getBool(_keyReminderEnabled) ?? true;
      _reminderProfile = ReminderSettings.profileFromRaw(
        prefs.getString(_keyReminderProfile),
      );
      _reminderLanguage = ReminderSettings.languageFromRaw(
        prefs.getString(_keyReminderLanguage),
      );
    });
  }

  Future<bool> _isSupportUnlockWindowActive() async {
    final prefs = await SharedPreferences.getInstance();
    final untilMs = prefs.getInt(_keySupportUnlockUntilMs) ?? 0;
    return untilMs > DateTime.now().millisecondsSinceEpoch;
  }

  String _localizedText({
    required String bn,
    required String en,
    required ReminderLanguage language,
  }) {
    switch (language) {
      case ReminderLanguage.bn:
        return bn;
      case ReminderLanguage.en:
        return en;
      case ReminderLanguage.both:
        return '$bn | $en';
    }
  }

  void _startLocalReminderEngine() {
    _localReminderTimer?.cancel();
    _localReminderTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      if (!mounted) return;
      unawaited(_runLocalReminderCheck());
    });
  }

  int _profileHoursForThreeDays() {
    switch (_reminderProfile) {
      case ReminderProfile.frequent:
        return 3;
      case ReminderProfile.minimal:
        return 12;
      case ReminderProfile.balanced:
        return 6;
    }
  }

  int _profileHoursForOneDay() {
    switch (_reminderProfile) {
      case ReminderProfile.frequent:
        return 1;
      case ReminderProfile.minimal:
        return 6;
      case ReminderProfile.balanced:
        return 3;
    }
  }

  Future<void> _runLocalReminderCheck() async {
    final prefs = await SharedPreferences.getInstance();
    _reminderEnabled = prefs.getBool(_keyReminderEnabled) ?? true;
    _reminderProfile = ReminderSettings.profileFromRaw(
      prefs.getString(_keyReminderProfile),
    );
    _reminderLanguage = ReminderSettings.languageFromRaw(
      prefs.getString(_keyReminderLanguage),
    );

    if (!_reminderEnabled) return;
    if (!_isDeviceOwner || _isPaidInFull || _isDeviceLocked) return;
    if (await _isSupportUnlockWindowActive()) return;
    if (_daysRemaining <= 0) return;
    final now = DateTime.now();
    final todayKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    // One-time banner when remaining days reaches 30.
    if (_daysRemaining == 30) {
      final last30Date = prefs.getString(_keyReminder30Date);
      if (last30Date != todayKey) {
        _showRemainingDaysReminder(days: _daysRemaining, isUrgent: false);
        await prefs.setString(_keyReminder30Date, todayKey);
      }
      return;
    }

    // Weekly reminder every Sunday when more than 3 days are left.
    if (_reminderProfile != ReminderProfile.minimal &&
        _daysRemaining > 3 &&
        now.weekday == DateTime.sunday) {
      final lastSundayDate = prefs.getString(_keyReminderSundayDate);
      if (lastSundayDate != todayKey) {
        _showRemainingDaysReminder(days: _daysRemaining, isUrgent: false);
        await prefs.setString(_keyReminderSundayDate, todayKey);
      }
      return;
    }

    // 2-3 days remaining: profile-controlled reminder interval.
    if (_daysRemaining <= 3 && _daysRemaining > 1) {
      final lastMs = prefs.getInt(_keyReminderThreeDaysMs) ?? 0;
      final intervalHours = _profileHoursForThreeDays();
      if (lastMs == 0 ||
          now.difference(DateTime.fromMillisecondsSinceEpoch(lastMs)).inHours >=
              intervalHours) {
        _showRemainingDaysReminder(days: _daysRemaining, isUrgent: true);
        await prefs.setInt(_keyReminderThreeDaysMs, now.millisecondsSinceEpoch);
      }
      return;
    }

    // 1 day remaining: profile-controlled reminder interval.
    if (_daysRemaining <= 1) {
      final lastMs = prefs.getInt(_keyReminderOneDayMs) ?? 0;
      final intervalHours = _profileHoursForOneDay();
      if (lastMs == 0 ||
          now.difference(DateTime.fromMillisecondsSinceEpoch(lastMs)).inHours >=
              intervalHours) {
        _showRemainingDaysReminder(days: _daysRemaining, isUrgent: true);
        await prefs.setInt(_keyReminderOneDayMs, now.millisecondsSinceEpoch);
      }
    }
  }

  void _showRemainingDaysReminder({required int days, required bool isUrgent}) {
    final bengaliDays = days <= 0 ? 'আজ শেষ দিন' : '$days দিন বাকি';
    final englishDays = days <= 0 ? 'Last day today' : '$days day(s) remaining';
    final title = isUrgent
        ? _localizedText(
            bn: 'জরুরি রিমাইন্ডার',
            en: 'Urgent Reminder',
            language: _reminderLanguage,
          )
        : _localizedText(
            bn: 'পেমেন্ট রিমাইন্ডার',
            en: 'Payment Reminder',
            language: _reminderLanguage,
          );
    final body = _localizedText(
      bn: '$bengaliDays। অনুগ্রহ করে কিস্তি সময়মতো পরিশোধ করুন।',
      en: '$englishDays. Please pay EMI on time.',
      language: _reminderLanguage,
    );

    _showCommandNotification(title, body);
    AppLogger.log('Local reminder shown: days=$days urgent=$isUrgent');
  }

  int _normalizeLockWindowDays(int days) {
    if (days < 1) return 1;
    if (days > 365) return 365;
    return days;
  }

  int _readLockWindowDays(SharedPreferences prefs) {
    final stored = prefs.getInt(_keyLockWindowDays) ?? _lockAfterDays;
    return _normalizeLockWindowDays(stored);
  }

  int? _parseServerDays(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) return _normalizeLockWindowDays(raw);
    if (raw is num) return _normalizeLockWindowDays(raw.toInt());
    if (raw is String) {
      final trimmed = raw.trim();
      final parsed =
          int.tryParse(trimmed) ??
          int.tryParse(RegExp(r'-?\d+').firstMatch(trimmed)?.group(0) ?? '');
      if (parsed != null) return _normalizeLockWindowDays(parsed);
    }
    return null;
  }

  int _calendarDaysSince(DateTime anchor, {DateTime? now}) {
    final effectiveNow = now ?? DateTime.now();
    final anchorDate = DateTime(anchor.year, anchor.month, anchor.day);
    final nowDate = DateTime(
      effectiveNow.year,
      effectiveNow.month,
      effectiveNow.day,
    );
    return nowDate.difference(anchorDate).inDays.clamp(0, 36500);
  }

  DateTime _resolveCountdownAnchor(SharedPreferences prefs, {DateTime? now}) {
    final effectiveNow = now ?? DateTime.now();
    final anchorMs = prefs.getInt(_keyTimerAnchorMs);
    final verifiedMs = prefs.getInt(_keyLastVerified);
    final resolvedMs =
        anchorMs ?? verifiedMs ?? effectiveNow.millisecondsSinceEpoch;
    return DateTime.fromMillisecondsSinceEpoch(resolvedMs);
  }

  int _calculateRemainingDays(SharedPreferences prefs, int lockWindowDays) {
    final now = DateTime.now();
    final anchor = _resolveCountdownAnchor(prefs, now: now);
    final daysSince = _calendarDaysSince(anchor, now: now);
    return (lockWindowDays - daysSince).clamp(0, lockWindowDays);
  }

  Future<bool> _readNativeDeviceLocked() async {
    try {
      final nativeLocked = await _channel.invokeMethod<bool>('isDeviceLocked');
      return nativeLocked ?? _isDeviceLocked;
    } on PlatformException catch (e) {
      AppLogger.log('Error reading native lock state: $e');
      return _isDeviceLocked;
    }
  }

  Future<void> _refreshLockStateFromNative() async {
    final nativeLocked = await _readNativeDeviceLocked();
    final prefs = await SharedPreferences.getInstance();

    // Don't re-engage lock if recently unlocked (cooldown to prevent race)
    if (nativeLocked) {
      final lastUnlockStr = prefs.getString('last_unlock_ms') ?? '0';
      final lastUnlockMs = int.tryParse(lastUnlockStr) ?? 0;
      if (lastUnlockMs > 0) {
        final msSinceUnlock =
            DateTime.now().millisecondsSinceEpoch - lastUnlockMs;
        if (msSinceUnlock < 30000) {
          // Recently unlocked — native flag may be stale, trust the unlock
          return;
        }
      }
    }

    final persistedLocked = prefs.getBool(_keyDeviceLocked) ?? false;
    if (persistedLocked != nativeLocked) {
      await prefs.setBool(_keyDeviceLocked, nativeLocked);
    }

    if (!mounted) {
      _isDeviceLocked = nativeLocked;
      return;
    }

    if (nativeLocked != _isDeviceLocked) {
      setState(() {
        _isDeviceLocked = nativeLocked;
        if (nativeLocked) {
          _daysRemaining = 0;
        } else {
          final windowDays = _readLockWindowDays(prefs);
          _lockWindowDays = windowDays;
          _daysRemaining = _calculateRemainingDays(prefs, windowDays);
        }
      });
    }
  }

  Future<void> _syncServerRemainingDays(
    int remainingDays, {
    bool allowIncrease = false,
  }) async {
    if (_isPaidInFull || _isDeviceLocked) return;
    final normalizedRemaining = _normalizeLockWindowDays(remainingDays);
    final prefs = await SharedPreferences.getInstance();
    _reminderLanguage = ReminderSettings.languageFromRaw(
      prefs.getString(_keyReminderLanguage),
    );
    final windowDays = _readLockWindowDays(prefs);
    final currentRemaining = _calculateRemainingDays(prefs, windowDays);
    final previousUiRemaining = _daysRemaining;

    // Heartbeat sync should never increase remaining days unless explicitly allowed
    // by a backend "extend" action. This prevents stale server values from
    // pinning the countdown (for example repeatedly returning 7).
    if (!allowIncrease && normalizedRemaining >= currentRemaining) {
      return;
    }

    // Avoid jitter when values are nearly identical during explicit updates.
    if (allowIncrease &&
        normalizedRemaining >= currentRemaining &&
        (normalizedRemaining - currentRemaining) <= 1) {
      return;
    }

    final newWindowDays = windowDays < normalizedRemaining
        ? normalizedRemaining
        : windowDays;
    await prefs.setInt(_keyLockWindowDays, newWindowDays);
    final anchor = DateTime.now().subtract(
      Duration(days: newWindowDays - normalizedRemaining),
    );
    await prefs.setInt(_keyLastVerified, anchor.millisecondsSinceEpoch);
    await prefs.setInt(_keyTimerAnchorMs, anchor.millisecondsSinceEpoch);

    if (mounted) {
      setState(() {
        _lockWindowDays = newWindowDays;
        _daysRemaining = normalizedRemaining;
      });
    }
    AppLogger.log(
      'Server remaining days synced accurately: $normalizedRemaining day(s)',
    );

    if (normalizedRemaining != previousUiRemaining) {
      _showRemainingDaysChangedFromServer(normalizedRemaining);
      unawaited(_runLocalReminderCheck());
    }
  }

  void _showRemainingDaysChangedFromServer(int days) {
    final bengali = '$days দিন বাকি';
    final english = '$days day(s) remaining';
    _showCommandNotification(
      _localizedText(
        bn: 'অবশিষ্ট দিন আপডেট',
        en: 'Remaining Days Updated',
        language: _reminderLanguage,
      ),
      _localizedText(
        bn: '$bengali (সার্ভার থেকে আপডেট)।',
        en: '$english (updated from server).',
        language: _reminderLanguage,
      ),
    );
    AppLogger.log('Remaining days changed from server: $days');
  }

  Future<void> _checkDeviceOwner() async {
    try {
      final isOwner = await _channel.invokeMethod<bool>('isDeviceOwner');
      if (mounted) setState(() => _isDeviceOwner = isOwner ?? false);
    } on PlatformException catch (e) {
      AppLogger.log('Error checking device owner: $e');
      if (mounted) setState(() => _isDeviceOwner = false);
    }
  }

  Future<void> _checkTimerAndLock() async {
    final prefs = await SharedPreferences.getInstance();
    if (await _isSupportUnlockWindowActive()) {
      AppLogger.log(
        'Timer lock check skipped: temporary support unlock is active',
      );
      return;
    }

    // Cooldown: don't re-lock within 30 seconds of an unlock to prevent race conditions
    final lastUnlockStr = prefs.getString('last_unlock_ms') ?? '0';
    final lastUnlockMs = int.tryParse(lastUnlockStr) ?? 0;
    if (lastUnlockMs > 0) {
      final msSinceUnlock =
          DateTime.now().millisecondsSinceEpoch - lastUnlockMs;
      if (msSinceUnlock < 30000) {
        // Recently unlocked — skip re-lock check
        return;
      }
    }

    final lockWindowDays = _readLockWindowDays(prefs);
    _lockWindowDays = lockWindowDays;
    if (_isPaidInFull || prefs.getBool('is_paid_in_full') == true) {
      await prefs.setBool(_keyDeviceLocked, false);
      await prefs.remove(_keySimAbsentSince);
      if (mounted) {
        setState(() {
          _isPaidInFull = true;
          _isDeviceLocked = false;
          _daysRemaining = lockWindowDays;
        });
      }
      return;
    }

    var lastVerifiedMs = prefs.getInt(_keyLastVerified);
    var timerAnchorMs = prefs.getInt(_keyTimerAnchorMs);
    if (lastVerifiedMs == null && timerAnchorMs != null) {
      lastVerifiedMs = timerAnchorMs;
      await prefs.setInt(_keyLastVerified, timerAnchorMs);
    }
    if (lastVerifiedMs != null && timerAnchorMs == null) {
      timerAnchorMs = lastVerifiedMs;
      await prefs.setInt(_keyTimerAnchorMs, lastVerifiedMs);
    }

    if (lastVerifiedMs == null && timerAnchorMs == null) {
      // First run — set initial verification timestamp
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      await prefs.setInt(_keyLastVerified, nowMs);
      await prefs.setInt(_keyTimerAnchorMs, nowMs);
      await prefs.setBool(_keyDeviceLocked, false);
      if (mounted) {
        setState(() {
          _isDeviceLocked = false;
          _daysRemaining = lockWindowDays;
        });
      }
      return;
    }

    final wasLocked = prefs.getBool(_keyDeviceLocked) ?? false;
    final nativeLocked = await _readNativeDeviceLocked();

    // If locked in persisted/native state, keep lock active.
    if (wasLocked || nativeLocked) {
      final locked = nativeLocked ? true : await _engageDeviceLock();
      if (!nativeLocked) {
        await prefs.setBool(_keyDeviceLocked, locked);
      }
      if (locked && mounted) {
        setState(() {
          _isDeviceLocked = true;
          _daysRemaining = 0;
        });
      }
      return;
    }

    // Not locked — check timer expiry
    final effectiveAnchorMs = timerAnchorMs ?? lastVerifiedMs;
    if (effectiveAnchorMs == null) {
      return;
    }
    final anchor = DateTime.fromMillisecondsSinceEpoch(effectiveAnchorMs);
    final daysSince = _calendarDaysSince(anchor);
    final remaining = lockWindowDays - daysSince;

    if (daysSince >= lockWindowDays) {
      final locked = await _engageDeviceLock();
      if (locked && mounted) {
        setState(() {
          _isDeviceLocked = true;
          _daysRemaining = 0;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _isDeviceLocked = false;
          _daysRemaining = remaining.clamp(0, lockWindowDays);
        });
      }
    }
  }

  Future<bool> _engageDeviceLock() async {
    if (_isPaidInFull) return false;
    try {
      final success = await DeviceStateManager().engageLock(
        reason: 'Due amount not paid',
      );
      if (success && mounted) {
        setState(() {
          _isDeviceLocked = true;
          _daysRemaining = 0;
        });
      }
      return success;
    } catch (e) {
      AppLogger.log('Error engaging device lock: $e');
      return false;
    }
  }

  Future<void> _clearReminderState() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove(_keyReminder30Date),
      prefs.remove(_keyReminderSundayDate),
      prefs.remove(_keyReminderThreeDaysMs),
      prefs.remove(_keyReminderOneDayMs),
    ]);
  }

  Future<void> _activatePaidInFullMode({bool refreshOwnerState = false}) async {
    bool success = false;
    try {
      success = await DeviceStateManager().markPaidInFull();
      if (success && mounted) {
        setState(() {
          _isPaidInFull = true;
          _isDeviceLocked = false;
          _daysRemaining = _lockWindowDays;
        });
        AppLogger.log('Paid in full mode activated successfully');
      }
    } catch (e) {
      AppLogger.log('Error activating paid in full mode: $e');
    }

    // Always sync local reminder/payment state from server intent, even if
    // native policy call fails. This prevents stale EMI reminders.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_paid_in_full', true);
    await _clearReminderState();
    if (!success && mounted) {
      setState(() {
        _isPaidInFull = true;
        _isDeviceLocked = false;
      });
      AppLogger.log(
        'Paid-in-full fallback applied locally after native failure.',
      );
    }

    if (refreshOwnerState) {
      await _checkDeviceOwner();
    }
  }

  Future<void> _activateDueAmountMode({
    int? days,
    bool refreshOwnerState = false,
    bool forceResetAnchor = false,
  }) async {
    try {
      final windowDays = days ?? _lockWindowDays;
      final previousRemaining = _daysRemaining;
      final success = await DeviceStateManager().markAsEmiPending(
        windowDays: windowDays,
        timerAnchor: forceResetAnchor ? DateTime.now() : null,
      );

      if (success && mounted) {
        setState(() {
          _isPaidInFull = false;
          _lockWindowDays = windowDays;
          if (!_isDeviceLocked) {
            if (forceResetAnchor) {
              _daysRemaining = windowDays;
            } else {
              _daysRemaining = previousRemaining.clamp(0, windowDays);
            }
          }
        });
        AppLogger.log('Due amount mode activated: window=$windowDays days');
      }
    } catch (e) {
      AppLogger.log('Error activating due amount mode: $e');
    }

    if (refreshOwnerState) {
      await _checkDeviceOwner();
    }
  }

  /// FIX: Properly clear locked flag, reset timer anchor AND last_verified
  /// so _checkTimerAndLock doesn't re-lock after the 30-second cooldown.
  Future<bool> _disengageDeviceLock() async {
    try {
      final success = await DeviceStateManager().disengageLock(
        resetTimerAnchor: true,
      );
      if (success) {
        final prefs = await SharedPreferences.getInstance();
        // Record unlock timestamp so _checkTimerAndLock won't re-lock within cooldown
        await prefs.setString(
          'last_unlock_ms',
          DateTime.now().millisecondsSinceEpoch.toString(),
        );
        // CRITICAL: Reset the timer anchor that _checkTimerAndLock actually uses.
        // Without this, the old expired last_verified causes immediate re-lock
        // once the 30-second cooldown expires.
        await prefs.setInt(
          _keyLastVerified,
          DateTime.now().millisecondsSinceEpoch,
        );
        if (mounted) {
          setState(() {
            _isDeviceLocked = false;
            _daysRemaining = _lockWindowDays;
          });
        }
      }
      return success;
    } catch (e) {
      AppLogger.log('Error disengaging device lock: $e');
      return false;
    }
  }

  Future<void> _startRealtimeListener() async {
    final deviceId = _realtimeDeviceId;
    if (deviceId == null || deviceId.isEmpty) return;
    final acceptedIds = <String>[
      if (_realtimeDeviceId != null) _realtimeDeviceId!,
      if (_deviceHash != null) _deviceHash!,
    ];

    await RealtimeCommandService().start(
      deviceId: deviceId,
      acceptedDeviceIds: acceptedIds,
      onCommand: _handleRealtimeCommand,
    );
  }

  Future<bool> lockDeviceLocally() => _engageDeviceLock();

  Future<bool> unlockDeviceLocally() => _disengageDeviceLock();

  Future<void> _handleRealtimeCommand(DeviceRealtimeCommand command) async {
    AppLogger.log(
      'Realtime command received in UI handler: '
      'id=${command.commandId} command=${command.command} device=${command.deviceId}',
    );

    final authResult = await CommandSecurityService().validateAndRecord(
      payload: command.rawRecord,
      action: command.command,
      matchedDeviceId: command.deviceId,
      source: 'realtime',
    );
    if (!authResult.allowed) {
      AppLogger.log(
        'Realtime command rejected by security policy: '
        'id=${command.commandId} action=${command.command} reason=${authResult.reason}',
      );
      return;
    }

    await _refreshLockStateFromNative();
    bool executed = false;
    switch (command.command) {
      case 'LOCK':
        AppLogger.log('LOCK execution started: commandId=${command.commandId}');
        if (await _isSupportUnlockWindowActive()) {
          AppLogger.log(
            'LOCK skipped: temporary support unlock window is active.',
          );
          executed = true;
          break;
        }
        if (_isPaidInFull) {
          AppLogger.log('Ignoring realtime LOCK: device is paid in full.');
          executed = true;
          break;
        }
        if (!_isDeviceLocked) {
          executed = await lockDeviceLocally();
          if (!executed) {
            AppLogger.log(
              'LOCK execution failed: commandId=${command.commandId}',
            );
            throw Exception('Realtime LOCK execution failed');
          }
          AppLogger.log(
            'LOCK execution succeeded: commandId=${command.commandId}',
          );
          unawaited(_ensureConnectivityForLockedMode());
          if (mounted) {
            setState(() {
              _isDeviceLocked = true;
              _daysRemaining = 0;
            });
          }
          _showCommandNotification(
            'Device Locked',
            'Your device has been locked due to pending payment.',
          );
        } else {
          AppLogger.log(
            'LOCK command already satisfied (device already locked): '
            'commandId=${command.commandId}',
          );
          executed = true;
        }
        break;
      case 'UNLOCK':
        AppLogger.log(
          'UNLOCK execution started: commandId=${command.commandId}',
        );
        if (_isDeviceLocked) {
          executed = await unlockDeviceLocally();
          if (!executed) {
            AppLogger.log(
              'UNLOCK execution failed: commandId=${command.commandId}',
            );
            throw Exception('Realtime UNLOCK execution failed');
          }
          AppLogger.log(
            'UNLOCK execution succeeded: commandId=${command.commandId}',
          );
          // Reset system UI and move app to background so user can use device
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
          if (mounted) {
            setState(() {
              _isDeviceLocked = false;
              _daysRemaining = _lockWindowDays;
            });
          }
          _showCommandNotification(
            'Device Unlocked',
            'Your device has been unlocked. You can use it normally.',
          );
          // Move FONEX to background so user isn't stuck on the app
          try {
            await _channel.invokeMethod('moveToBackground');
          } catch (_) {}
        } else {
          AppLogger.log(
            'UNLOCK command already satisfied (device already unlocked): '
            'commandId=${command.commandId}',
          );
          executed = true;
        }
        break;
      default:
        return;
    }

    if (executed) {
      AppLogger.log(
        'Sending ACK for commandId=${command.commandId} command=${command.command}',
      );
      final ackSucceeded = await sendCommandAck(
        command.commandId,
        command: command.command,
        deviceId: _realtimeDeviceId ?? command.deviceId,
      );
      if (!ackSucceeded) {
        AppLogger.log(
          'ACK failed for commandId=${command.commandId}; '
          'command will not be marked as processed',
        );
        throw Exception('Realtime ACK failed');
      }
    }

    // Push an immediate health/status sync so dashboard state updates quickly.
    unawaited(_serverCheckIn());
  }

  /// Show a notification for a command/action via native channel
  void _showCommandNotification(String title, String body) {
    unawaited(_showCommandNotificationInternal(title, body));
  }

  Future<void> _showCommandNotificationInternal(
    String title,
    String body, {
    Duration dedupeWindow = const Duration(minutes: 30),
  }) async {
    try {
      final normalizedSignature =
          '${title.trim().toLowerCase()}|${body.trim().toLowerCase()}';
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final prefs = await SharedPreferences.getInstance();
      final lastSignature = prefs.getString(_keyLastNotifSignature);
      final lastMs = prefs.getInt(_keyLastNotifMs) ?? 0;
      if (lastSignature == normalizedSignature &&
          (nowMs - lastMs) < dedupeWindow.inMilliseconds) {
        AppLogger.log('Notification deduped: title="$title" body="$body"');
        return;
      }

      await prefs.setString(_keyLastNotifSignature, normalizedSignature);
      await prefs.setInt(_keyLastNotifMs, nowMs);
      await _channel.invokeMethod('showCommandNotification', {
        'title': title,
        'body': body,
      });
    } catch (e) {
      AppLogger.log('Notification error: $e');
    }
  }

  Future<bool> sendCommandAck(
    String commandId, {
    required String command,
    String? deviceId,
  }) {
    return RealtimeCommandService().sendCommandAck(
      commandId: commandId,
      command: command,
      deviceId: deviceId,
    );
  }

  Future<bool> _hasNetworkConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    return result.any((item) => item != ConnectivityResult.none);
  }

  Future<void> _ensureConnectivityForLockedMode() async {
    if (!_isDeviceLocked) return;
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'ensureConnectivityForLock',
      );
      if (result != null) {
        AppLogger.log('Connectivity checked for lock state: $result');
      }
    } catch (e) {
      AppLogger.log('Connectivity recovery skipped: $e');
    }
  }

  Future<void> _ensureBackgroundKillProtection({
    required bool allowUserPrompt,
  }) async {
    try {
      await _channel.invokeMethod('startKeepAliveService');
      await _channel.invokeMethod('scheduleKeepAliveWatchdog');

      if (!allowUserPrompt) return;
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_keyBackgroundPromptShown) == true) return;

      final isIgnoringBatteryOptimizations =
          await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ??
          true;
      if (!isIgnoringBatteryOptimizations) {
        debugPrint(
          'Battery optimization is enabled. User can disable it manually from Settings screen.',
        );
      }
      await prefs.setBool(_keyBackgroundPromptShown, true);
    } catch (e) {
      AppLogger.log('Background protection setup skipped: $e');
    }
  }

  Future<int?> _getBatteryLevel() async {
    try {
      final level = await _channel.invokeMethod<int>('getBatteryLevel');
      if (level == null) return null;
      return level.clamp(0, 100);
    } catch (_) {
      return null;
    }
  }

  /// Backend check-in — optimized sync with auto-registration and queue management
  /// Uses enterprise-level sync service for reliability and offline support
  Future<void> _serverCheckIn() async {
    RealtimeCommandService().ensureConnected();
    if (_isConnecting) return;
    if (!await _hasNetworkConnectivity()) {
      unawaited(_ensureConnectivityForLockedMode());
      if (mounted) {
        setState(() {
          _isServerConnected = false;
          _serverStatusMessage = 'Offline';
        });
      }
      return;
    }

    if (mounted) {
      setState(() => _isConnecting = true);
    } else {
      _isConnecting = true;
    }

    try {
      final deviceHash = _deviceHash ?? await DeviceHashUtil.getDeviceHash();
      _deviceHash = deviceHash;
      String imei = "Not Found";
      Map<String, dynamic> registrationMetadata = {};

      try {
        final info = await _channel.invokeMapMethod<String, dynamic>(
          'getDeviceInfo',
        );
        if (info != null) {
          if (info.containsKey('imei')) imei = info['imei'] as String;
          registrationMetadata = {
            'model': info['deviceModel']?.toString() ?? 'Unknown',
            'manufacturer': info['manufacturer']?.toString() ?? 'Unknown',
            'android_version': info['androidVersion'] ?? 0,
            'is_device_owner': _isDeviceOwner,
          };
        }
      } catch (_) {}

      // Check if this is first registration and auto-save to local DB
      final isRegistered = await DeviceStorageService.isDeviceRegistered();
      if (!isRegistered) {
        debugPrint(
          '🆕 First-time registration detected - auto-saving to local DB...',
        );
        await SyncService().registerDevice(
          deviceHash: deviceHash,
          imei: imei,
          metadata: registrationMetadata,
        );
      }

      // Lightweight heartbeat: status-only update (last_seen + battery)
      final batteryLevel = await _getBatteryLevel();
      final syncService = SyncService();
      final response = await syncService.performCheckIn(
        deviceHash: deviceHash,
        imei: imei,
        deviceId: _realtimeDeviceId ?? deviceHash,
        batteryLevel: batteryLevel,
        lastSeen: DateTime.now(),
        isLocked: _isDeviceLocked,
      );

      if (response != null) {
        await _refreshLockStateFromNative();
        final serverDeviceId = (response['device_id'] ?? response['id'])
            ?.toString()
            .trim();
        if (serverDeviceId != null &&
            serverDeviceId.isNotEmpty &&
            serverDeviceId != _realtimeDeviceId) {
          _realtimeDeviceId = serverDeviceId;
          unawaited(_syncNativeDeviceIdentifiers());
          await RealtimeCommandService().dispose();
          await _startRealtimeListener();
        }

        if (mounted) {
          setState(() {
            _isServerConnected = true;
            _serverStatusMessage = 'Connected';
            _lastServerSync = DateTime.now();
          });
        }

        final paymentStatus = response['payment_status']
            ?.toString()
            .toLowerCase()
            .trim();
        final paidStatuses = <String>{
          'paid',
          'paid_in_full',
          'full_paid',
          'completed',
          'settled',
        };
        final serverPaidInFull =
            response['is_paid_in_full'] == true ||
            response['paid_in_full'] == true ||
            (paymentStatus != null && paidStatuses.contains(paymentStatus));
        final serverLocked =
            response['is_locked'] == true ||
            response['locked'] == true ||
            (response['status']?.toString().toLowerCase() == 'locked');
        final serverTenureDays =
            _parseServerDays(response['days']) ??
            _parseServerDays(response['tenure']);
        final serverRemainingDays = _parseServerDays(
          response['days_remaining'],
        );
        if (serverPaidInFull && !_isPaidInFull) {
          await _activatePaidInFullMode(refreshOwnerState: true);
        } else if (!serverPaidInFull) {
          final wasPaidInFull = _isPaidInFull;
          // Only update EMI mode when needed:
          // - paid -> unpaid transition
          // - explicit tenure window from server
          // Never reuse days_remaining as tenure window.
          if (!_isDeviceLocked && (wasPaidInFull || serverTenureDays != null)) {
            await _activateDueAmountMode(
              days: serverTenureDays,
              forceResetAnchor: wasPaidInFull,
            );
          }
          if (serverRemainingDays != null) {
            await _syncServerRemainingDays(serverRemainingDays);
          }
          if (serverLocked && !_isDeviceLocked) {
            if (await _isSupportUnlockWindowActive()) {
              AppLogger.log(
                'Server lock skipped: temporary support unlock is active.',
              );
            } else {
              final locked = await _engageDeviceLock();
              if (locked && mounted) {
                setState(() {
                  _isDeviceLocked = true;
                  _daysRemaining = 0;
                });
              }
              AppLogger.log('Server state lock sync applied: $locked');
            }
          }
        }

        final rawAction = response['action'] as String? ?? 'none';
        var action = rawAction.toLowerCase();
        if (action != 'none') {
          final authResult = await CommandSecurityService().validateAndRecord(
            payload: response,
            action: action,
            matchedDeviceId: _realtimeDeviceId ?? deviceHash,
            source: 'checkin',
          );
          if (!authResult.allowed) {
            AppLogger.log(
              'Server action rejected by security policy: '
              'action=$action reason=${authResult.reason}',
            );
            action = 'none';
          }
        }

        AppLogger.log('Server check-in response: action=$action');

        switch (action) {
          case 'lock':
            if (!_isPaidInFull) {
              if (await _isSupportUnlockWindowActive()) {
                AppLogger.log(
                  'Server action lock ignored: support unlock window active',
                );
                break;
              }
              await _refreshLockStateFromNative();
              final locked = _isDeviceLocked ? true : await _engageDeviceLock();
              if (locked && mounted) {
                setState(() {
                  _isDeviceLocked = true;
                  _daysRemaining = 0;
                });
                _showCommandNotification(
                  'Device Locked',
                  'Your device has been locked due to pending payment.',
                );
              }
              AppLogger.log('Server action lock applied: $locked');
            }
            break;
          case 'unlock':
            await _refreshLockStateFromNative();
            if (_isDeviceLocked) {
              final unlocked = await _disengageDeviceLock();
              if (unlocked && mounted) {
                SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
                setState(() {
                  _isDeviceLocked = false;
                  _daysRemaining = _lockWindowDays;
                });
                _showCommandNotification(
                  'Device Unlocked',
                  'Your device has been unlocked. You can use it normally.',
                );
                try {
                  await _channel.invokeMethod('moveToBackground');
                } catch (_) {}
              }
              AppLogger.log('Server action unlock applied: $unlocked');
            }
            break;
          case 'extend':
          case 'extend_days':
            final serverRemaining = _parseServerDays(
              response['days_remaining'],
            );
            final serverWindow =
                _parseServerDays(response['days']) ??
                _parseServerDays(response['tenure']);

            // Source of truth: days_remaining from server.
            // Never treat remaining days as "extend by N days" locally.
            if (serverRemaining != null) {
              await _syncServerRemainingDays(
                serverRemaining,
                allowIncrease: true,
              );
              _showCommandNotification(
                'Remaining Days Updated',
                'Your remaining days are now set to $serverRemaining.',
              );
              AppLogger.log(
                'Server action extend_days applied from days_remaining: '
                '$serverRemaining',
              );
              break;
            }

            // Fallback only if backend did not send days_remaining.
            if (serverWindow != null) {
              await _activateDueAmountMode(
                days: serverWindow,
                forceResetAnchor: true,
              );
              _showCommandNotification(
                'Payment Window Updated',
                'Your payment window is now set to $serverWindow days.',
              );
              AppLogger.log(
                'Server action extend_days fallback applied from window days: '
                '$serverWindow',
              );
              break;
            }

            AppLogger.log(
              'Server action extend_days ignored: '
              'no valid days_remaining/days/tenure in response',
            );
            break;
          case 'paid_in_full':
          case 'mark_paid_in_full':
          case 'paid_full':
          case 'paid':
            await _activatePaidInFullMode(refreshOwnerState: true);
            _showCommandNotification(
              'Payment Complete',
              'Your device is now fully paid. All restrictions removed.',
            );
            break;
          case 'none':
            AppLogger.log('No action required from server');
            break;
          default:
            AppLogger.log('Unknown server action: $action');
            break;
        }
      } else {
        // Sync failed but queued for retry by SyncService.
        if (mounted) {
          setState(() {
            _isServerConnected = false;
            _serverStatusMessage = 'Queued for sync';
          });
        }
        AppLogger.log('Check-in queued for retry (offline or server error)');
      }
    } catch (e, stacktrace) {
      if (mounted) {
        setState(() {
          _isServerConnected = false;
          _serverStatusMessage = 'Connection failed';
        });
      }
      AppLogger.log('Error during _serverCheckIn: $e\n$stacktrace');
      unawaited(
        CrashReporter.recordNonFatal(
          source: 'server_check_in',
          message: e.toString(),
          stack: stacktrace,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
      } else {
        _isConnecting = false;
      }
    }
  }

  /// Manual server connection retry
  Future<void> _manualServerConnect() async {
    if (_isConnecting) return;
    setState(() {
      _serverStatusMessage = 'Connecting...';
    });
    await _serverCheckIn();
  }

  // DEV: simulate expiry for the currently configured lock window.
  Future<void> _devSimulateExpiry() async {
    final prefs = await SharedPreferences.getInstance();
    final expiredAnchorMs = DateTime.now()
        .subtract(Duration(days: _lockWindowDays + 1))
        .millisecondsSinceEpoch;
    await prefs.setInt(_keyLastVerified, expiredAnchorMs);
    await prefs.setInt(_keyTimerAnchorMs, expiredAnchorMs);
    await _checkTimerAndLock();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const SplashScreen();

    final nextPaymentDate = _lastServerSync != null
        ? _lastServerSync!.add(Duration(days: _daysRemaining))
        : null;

    return StoreWallpaper(
      storeName: _storeName,
      daysRemaining: _daysRemaining,
      isLocked: _isDeviceLocked,
      nextPaymentDate: nextPaymentDate,
      child: _isDeviceLocked
          ? LockScreen(
              onUnlocked: _disengageDeviceLock,
              storeName: _storeName,
              supportPhone1: _supportPhone1,
              supportPhone2: _supportPhone2,
            )
          : NormalModeScreen(
              isDeviceOwner: _isDeviceOwner,
              isPaidInFull: _isPaidInFull,
              daysRemaining: _daysRemaining,
              lockWindowDays: _lockWindowDays,
              onSimulateExpiry: _devSimulateExpiry,
              isServerConnected: _isServerConnected,
              serverStatusMessage: _serverStatusMessage,
              lastServerSync: _lastServerSync,
              onManualConnect: _manualServerConnect,
              isConnecting: _isConnecting,
            ),
    );
  }

  // Dead code removed: _buildHeroStatus, _buildProgressCard, _buildMiniCard,
  // _showDevTools were duplicated in _NormalModeScreenState and unused here.
}

// =============================================================================
// NORMAL MODE SCREEN — Main dashboard when device is unlocked
// =============================================================================
class NormalModeScreen extends StatefulWidget {
  final bool isDeviceOwner;
  final bool isPaidInFull;
  final int daysRemaining;
  final int lockWindowDays;
  final VoidCallback onSimulateExpiry;
  final bool isServerConnected;
  final String serverStatusMessage;
  final DateTime? lastServerSync;
  final VoidCallback onManualConnect;
  final bool isConnecting;

  const NormalModeScreen({
    super.key,
    required this.isDeviceOwner,
    required this.isPaidInFull,
    required this.daysRemaining,
    required this.lockWindowDays,
    required this.onSimulateExpiry,
    required this.isServerConnected,
    required this.serverStatusMessage,
    this.lastServerSync,
    required this.onManualConnect,
    required this.isConnecting,
  });

  @override
  State<NormalModeScreen> createState() => _NormalModeScreenState();
}

class _NormalModeScreenState extends State<NormalModeScreen> {
  Widget _buildHeroStatus() {
    final isHealthy = widget.isDeviceOwner && widget.daysRemaining > 0;
    return GlassCard(
      padding: const EdgeInsets.all(24),
      borderColor: isHealthy
          ? FonexColors.green.withValues(alpha: 0.3)
          : FonexColors.red.withValues(alpha: 0.3),
      child: Row(
        children: [
          GlowIcon(
            icon: isHealthy ? Icons.check_circle_rounded : Icons.error_rounded,
            color: isHealthy ? FonexColors.green : FonexColors.red,
            size: 30,
            containerSize: 60,
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isHealthy ? 'All Systems Operational' : 'Action Required',
                  style: GoogleFonts.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: FonexColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isHealthy
                      ? 'Device is fully protected and verified'
                      : 'Device protection not configured. Retry Make Owner.',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: FonexColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServerConnectionCard() {
    final statusColor = widget.isServerConnected
        ? FonexColors.green
        : widget.isConnecting
        ? FonexColors.orange
        : FonexColors.red;

    String lastSyncText = 'Never';
    if (widget.lastServerSync != null) {
      final diff = DateTime.now().difference(widget.lastServerSync!);
      if (diff.inMinutes < 1) {
        lastSyncText = 'Just now';
      } else if (diff.inMinutes < 60) {
        lastSyncText = '${diff.inMinutes}m ago';
      } else if (diff.inHours < 24) {
        lastSyncText = '${diff.inHours}h ago';
      } else {
        lastSyncText = '${diff.inDays}d ago';
      }
    }

    return GlassCard(
      padding: const EdgeInsets.all(16),
      borderColor: statusColor.withValues(alpha: 0.3),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor,
              boxShadow: [
                BoxShadow(
                  color: statusColor.withValues(alpha: 0.5),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Server Status',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: FonexColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.serverStatusMessage,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (widget.lastServerSync != null)
                  Text(
                    'Last sync: $lastSyncText',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: FonexColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          if (!widget.isServerConnected && !widget.isConnecting)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20),
              color: FonexColors.accent,
              onPressed: widget.onManualConnect,
              tooltip: 'Retry connection',
            ),
          if (widget.isConnecting)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: FonexColors.orange,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBackgroundHealthCard() {
    return ValueListenableBuilder<RealtimeDiagnostics>(
      valueListenable: RealtimeCommandService.diagnosticsNotifier,
      builder: (context, diagnostics, _) {
        final lastSubscribed = diagnostics.lastSubscribedAt;
        final lastSubscribedText = lastSubscribed == null
            ? 'Never'
            : _formatRelativeTime(lastSubscribed);
        final reconnectReason = diagnostics.lastDisconnectReason ?? 'None';
        final ackStatusText = diagnostics.lastAckStatusCode != null
            ? '${diagnostics.lastAckStatusCode}'
            : '-';
        final ackResult = diagnostics.lastAckResult ?? 'N/A';
        final commandText = diagnostics.lastCommandId == null
            ? 'No command yet'
            : '${diagnostics.lastCommand ?? ''} (${diagnostics.lastCommandId})';

        return GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.health_and_safety_rounded,
                    color: FonexColors.cyan,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Background Health Monitor',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: FonexColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildHealthRow(
                'Realtime',
                diagnostics.subscribed ? 'Subscribed' : diagnostics.lastStatus,
              ),
              _buildHealthRow('Last subscribe', lastSubscribedText),
              _buildHealthRow('Reconnect reason', reconnectReason),
              _buildHealthRow('Last command', commandText),
              _buildHealthRow(
                'ACK',
                'attempts=${diagnostics.lastAckAttempts ?? 0}, status=$ackStatusText',
              ),
              _buildHealthRow('Last ACK result', ackResult),
              _buildHealthRow(
                'Pending ACK queue',
                '${diagnostics.pendingAckCount}',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHealthRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: FonexColors.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: FonexColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatRelativeTime(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Widget _buildProgressCard() {
    final urgentColor = widget.daysRemaining <= 7
        ? FonexColors.red
        : widget.daysRemaining <= 14
        ? FonexColors.orange
        : FonexColors.accent;

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule_rounded, color: urgentColor, size: 20),
              const SizedBox(width: 10),
              Text(
                'Verification Countdown',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: FonexColors.textPrimary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: urgentColor.withValues(alpha: 0.12),
                ),
                child: Text(
                  '${widget.daysRemaining} days',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: urgentColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (widget.daysRemaining / widget.lockWindowDays).clamp(
                0.0,
                1.0,
              ),
              minHeight: 8,
              backgroundColor: FonexColors.cardBorder,
              valueColor: AlwaysStoppedAnimation<Color>(urgentColor),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Last verified',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: FonexColors.textMuted,
                ),
              ),
              Text(
                'Locks in ${widget.daysRemaining} days',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: FonexColors.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniCard({
    required IconData icon,
    required Color color,
    required String label,
  }) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      borderRadius: 16,
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: FonexColors.textSecondary,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmiInfoRow(String label, String value, [Color? valueColor]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: FonexColors.textSecondary,
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: valueColor ?? FonexColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFullEmiDetailsCard() {
    final nextPaymentDate = DateTime.now().add(
      Duration(days: widget.daysRemaining > 0 ? widget.daysRemaining : 0),
    );
    final urgentColor = widget.daysRemaining <= 7
        ? FonexColors.red
        : widget.daysRemaining <= 14
        ? FonexColors.orange
        : FonexColors.green;

    return GlassCard(
      padding: const EdgeInsets.all(20),
      borderColor: urgentColor.withValues(alpha: 0.32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long_rounded, size: 18, color: urgentColor),
              const SizedBox(width: 8),
              Text(
                'Full Due Information',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: FonexColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildEmiInfoRow('Store', _storeName),
          const Divider(color: FonexColors.cardBorder),
          _buildEmiInfoRow('Support 1', _supportPhone1),
          const Divider(color: FonexColors.cardBorder),
          _buildEmiInfoRow('Support 2', _supportPhone2),
          const Divider(color: FonexColors.cardBorder),
          _buildEmiInfoRow('Payment Period', '${widget.lockWindowDays} days'),
          const Divider(color: FonexColors.cardBorder),
          _buildEmiInfoRow(
            'Days Remaining',
            '${widget.daysRemaining} days',
            urgentColor,
          ),
          const Divider(color: FonexColors.cardBorder),
          _buildEmiInfoRow(
            'Next Due Date',
            _formatDate(nextPaymentDate),
            urgentColor,
          ),
          const Divider(color: FonexColors.cardBorder),
          _buildEmiInfoRow(
            'Status',
            widget.daysRemaining > 0 ? 'Active' : 'Locked',
            widget.daysRemaining > 0 ? FonexColors.green : FonexColors.red,
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: FonexColors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: FonexColors.orange.withValues(alpha: 0.4),
              ),
            ),
            child: Text(
              'Please clear the due amount before the due date to avoid device lock.',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: FonexColors.textPrimary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) => '${date.day}/${date.month}/${date.year}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          AnimatedGradientBg(
            child: Stack(
              children: [
                const FloatingParticles(count: 12),
                SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        Row(
                          children: [
                            const FonexLogo(size: 48),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ShaderMask(
                                    shaderCallback: (b) => const LinearGradient(
                                      colors: [
                                        FonexColors.accentLight,
                                        FonexColors.purple,
                                      ],
                                    ).createShader(b),
                                    child: Text(
                                      'FONEX',
                                      style: GoogleFonts.inter(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w900,
                                        color: Colors.white,
                                        letterSpacing: 4,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    'Device Control System',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: FonexColors.textSecondary,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.info_outline_rounded,
                                color: FonexColors.textSecondary,
                              ),
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const DeviceInfoScreen(),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.settings_rounded,
                                color: FonexColors.textSecondary,
                              ),
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const SettingsScreen(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        _buildHeroStatus(),
                        const SizedBox(height: 16),
                        _buildServerConnectionCard(),
                        const SizedBox(height: 16),
                        _buildBackgroundHealthCard(),
                        const SizedBox(height: 16),
                        _buildProgressCard(),
                        const SizedBox(height: 16),
                        _buildFullEmiDetailsCard(),
                        const SizedBox(height: 24),
                        // Feature cards
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PaymentScheduleScreen(
                                      daysRemaining: widget.daysRemaining,
                                      lockWindowDays: widget.lockWindowDays,
                                      isPaidInFull: widget.isPaidInFull,
                                      lastServerSync: widget.lastServerSync,
                                    ),
                                  ),
                                ),
                                child: _buildMiniCard(
                                  icon: Icons.calendar_today_rounded,
                                  color: FonexColors.purple,
                                  label: 'Payment\nSchedule',
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const DeviceInfoScreen(),
                                  ),
                                ),
                                child: _buildMiniCard(
                                  icon: Icons.phone_android_rounded,
                                  color: FonexColors.cyan,
                                  label: 'Device\nInfo',
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildMiniCard(
                                icon: Icons.payment_rounded,
                                color: widget.isDeviceOwner
                                    ? FonexColors.green
                                    : FonexColors.orange,
                                label: widget.isDeviceOwner
                                    ? 'Due\nActive'
                                    : 'Setup\nRequired',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        // QR Code Card
                        GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const QRCodeScreen(),
                            ),
                          ),
                          child: GlassCard(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              children: [
                                Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: FonexColors.accent.withValues(
                                      alpha: 0.15,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.qr_code_rounded,
                                    color: FonexColors.accent,
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Device QR Code',
                                        style: GoogleFonts.inter(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: FonexColors.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Show QR code for easy identification',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: FonexColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  color: FonexColors.textMuted,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Dead code removed: _buildHeroStatus, _buildProgressCard, _buildMiniCard,
  // _showDevTools were duplicated in _NormalModeScreenState and unused here.
}

// =============================================================================
// SPLASH SCREEN — Premium animated loading
// =============================================================================
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeIn;
  late Animation<double> _scaleUp;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..forward();
    _fadeIn = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _scaleUp = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FonexColors.bg,
      body: AnimatedGradientBg(
        child: Stack(
          children: [
            const FloatingParticles(count: 10),
            Center(
              child: FadeTransition(
                opacity: _fadeIn,
                child: ScaleTransition(
                  scale: _scaleUp,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const FonexLogo(size: 90),
                      const SizedBox(height: 28),
                      ShaderMask(
                        shaderCallback: (b) => const LinearGradient(
                          colors: [FonexColors.accentLight, FonexColors.purple],
                        ).createShader(b),
                        child: Text(
                          'FONEX',
                          style: GoogleFonts.inter(
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 8,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _storeName,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: FonexColors.textSecondary,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 48),
                      SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: FonexColors.accent.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// LOCK SCREEN — Fullscreen branded lock with animated effects
// =============================================================================
class LockScreen extends StatefulWidget {
  final Future<bool> Function() onUnlocked;
  final String storeName;
  final String supportPhone1;
  final String supportPhone2;

  const LockScreen({
    super.key,
    required this.onUnlocked,
    required this.storeName,
    required this.supportPhone1,
    required this.supportPhone2,
  });

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with TickerProviderStateMixin {
  static const _channel = MethodChannel(_channelName);

  late AnimationController _pulseController;
  late AnimationController _entryController;
  late Animation<double> _pulse;
  late Animation<double> _fadeIn;
  late Animation<Offset> _slideUp;

  int _unlockTapCount = 0;
  Timer? _tapResetTimer;
  Timer? _screenOffTimer;
  String _deviceHash = '------';

  @override
  void initState() {
    super.initState();
    _loadDeviceHash();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();
    _fadeIn = CurvedAnimation(parent: _entryController, curve: Curves.easeOut);
    _slideUp = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _entryController, curve: Curves.easeOutCubic),
        );

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _scheduleAutoScreenOff();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _entryController.dispose();
    _tapResetTimer?.cancel();
    _screenOffTimer?.cancel();
    // Reset system UI so user isn't stuck in immersive mode after unlock
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _loadDeviceHash() async {
    final hash = await DeviceHashUtil.getDeviceHash();
    if (mounted) setState(() => _deviceHash = hash);
  }

  void _handleSecretTap() {
    _scheduleAutoScreenOff();
    _unlockTapCount++;
    _tapResetTimer?.cancel();
    _tapResetTimer = Timer(const Duration(seconds: 3), () {
      _unlockTapCount = 0;
    });
    if (_unlockTapCount >= 5) {
      _unlockTapCount = 0;
      _showPinScreen();
    }
  }

  void _showPinScreen() {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => OwnerPinScreen(
          onUnlocked: widget.onUnlocked,
          deviceHash: _deviceHash,
        ),
        transitionsBuilder: (_, a, __, child) {
          return FadeTransition(
            opacity: a,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.05),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: a, curve: Curves.easeOut)),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  void _showPaymentQr() {
    _scheduleAutoScreenOff();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: FonexColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: FonexColors.cardBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  'Scan to Pay Due',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: FonexColors.textPrimary,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  icon: const Icon(
                    Icons.close_rounded,
                    color: FonexColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.asset(
                'assets/images/payment_qr_code/bharat_pay.jpg',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(
                  height: 220,
                  alignment: Alignment.center,
                  color: FonexColors.card,
                  child: Text(
                    'Payment QR not found',
                    style: GoogleFonts.inter(
                      color: FonexColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Show payment screenshot at ${widget.storeName} after payment.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: FonexColors.textSecondary,
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  void _scheduleAutoScreenOff() {
    _screenOffTimer?.cancel();
    _screenOffTimer = Timer(const Duration(minutes: 1), () async {
      try {
        await _channel.invokeMethod('lockScreenNow');
      } catch (e) {
        AppLogger.log('Auto screen off skipped: $e');
      }
    });
  }

  String _poweredByLine(String rawStoreName) {
    final cleaned = rawStoreName.trim().replaceAll(
      RegExp(r'\bpowerd\b', caseSensitive: false),
      'Powered',
    );
    if (cleaned.isEmpty) {
      return 'FONEX Powered by Roy Communication';
    }
    if (RegExp(r'\bpowered\s+by\b', caseSensitive: false).hasMatch(cleaned)) {
      return cleaned;
    }
    return 'Powered by $cleaned';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _scheduleAutoScreenOff(),
          child: AnimatedGradientBg(
            colors: const [
              Color(0xFF06080F),
              Color(0xFF1A0A0A),
              Color(0xFF0A0A1A),
              Color(0xFF06080F),
            ],
            child: Stack(
              children: [
                const FloatingParticles(count: 16),
                SafeArea(
                  child: FadeTransition(
                    opacity: _fadeIn,
                    child: SlideTransition(
                      position: _slideUp,
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Pulsating lock icon
                              AnimatedBuilder(
                                animation: _pulse,
                                builder: (_, child) => Transform.scale(
                                  scale: 0.95 + 0.05 * _pulse.value,
                                  child: Opacity(
                                    opacity: _pulse.value,
                                    child: child,
                                  ),
                                ),
                                child: Container(
                                  width: 130,
                                  height: 130,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(
                                      colors: [
                                        FonexColors.red.withValues(alpha: 0.3),
                                        FonexColors.red.withValues(alpha: 0.05),
                                        Colors.transparent,
                                      ],
                                    ),
                                  ),
                                  child: Center(
                                    child: Container(
                                      width: 88,
                                      height: 88,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: const LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            Color(0xFFDC2626),
                                            Color(0xFFEF4444),
                                          ],
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: FonexColors.red.withValues(
                                              alpha: 0.4,
                                            ),
                                            blurRadius: 30,
                                            spreadRadius: 4,
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.lock_rounded,
                                        size: 42,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 40),

                              // FONEX branding
                              const FonexLogo(size: 44),
                              const SizedBox(height: 14),
                              ShaderMask(
                                shaderCallback: (b) => const LinearGradient(
                                  colors: [
                                    FonexColors.accentLight,
                                    FonexColors.purple,
                                  ],
                                ).createShader(b),
                                child: Text(
                                  'FONEX',
                                  style: GoogleFonts.inter(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: 6,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _poweredByLine(widget.storeName),
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: FonexColors.textPrimary.withValues(
                                    alpha: 0.92,
                                  ),
                                  letterSpacing: 0.4,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),

                              const SizedBox(height: 40),

                              // Lock message card
                              GlassCard(
                                borderColor: FonexColors.red.withValues(
                                  alpha: 0.25,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 24,
                                ),
                                child: Column(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: FonexColors.orange.withValues(
                                          alpha: 0.15,
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.warning_amber_rounded,
                                        color: FonexColors.orange,
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Device Temporarily Locked',
                                      style: GoogleFonts.inter(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        color: FonexColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      'Your payment verification period has expired. '
                                      'Please visit your mobile shop to continue using this device.',
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        color: FonexColors.textSecondary,
                                        height: 1.6,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 20),

                              // Contact card
                              SizedBox(
                                width: double.infinity,
                                child: GlassCard(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 16,
                                  ),
                                  borderRadius: 14,
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: FonexColors.cyan.withValues(
                                            alpha: 0.12,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.store_rounded,
                                          color: FonexColors.cyan,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              widget.storeName,
                                              style: GoogleFonts.inter(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w700,
                                                color: FonexColors.textPrimary,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'Visit store to unlock',
                                              style: GoogleFonts.inter(
                                                fontSize: 12,
                                                color:
                                                    FonexColors.textSecondary,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              const SizedBox(height: 20),

                              // Device Hash Display
                              GlassCard(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                                borderRadius: 14,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Device ID',
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: FonexColors.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _deviceHash,
                                      textAlign: TextAlign.center,
                                      style: GoogleFonts.inter(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        color: FonexColors.textPrimary,
                                        letterSpacing: 4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 24),

                              // Emergency Call Buttons
                              GlassCard(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 16,
                                ),
                                borderColor: FonexColors.green.withValues(
                                  alpha: 0.3,
                                ),
                                borderRadius: 18,
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          Icons.phone_in_talk_rounded,
                                          color: FonexColors.green,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Text(
                                            'Need Help? Call ${widget.storeName}',
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: FonexColors.textSecondary,
                                            ),
                                            textAlign: TextAlign.center,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Tap any number to view full number',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: FonexColors.textMuted,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Column(
                                      children: [
                                        SizedBox(
                                          width: double.infinity,
                                          child: _CallButton(
                                            number: widget.supportPhone1,
                                            label: widget.supportPhone1
                                                .replaceAll('+91', '+91 '),
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        SizedBox(
                                          width: double.infinity,
                                          child: _CallButton(
                                            number: widget.supportPhone2,
                                            label: widget.supportPhone2
                                                .replaceAll('+91', '+91 '),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: FonexColors.orange.withValues(
                                          alpha: 0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: FonexColors.orange.withValues(
                                            alpha: 0.3,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            Icons.info_outline_rounded,
                                            color: FonexColors.orange,
                                            size: 16,
                                          ),
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: Text(
                                              'Visit ${widget.storeName} store to clear due payment and unlock device',
                                              textAlign: TextAlign.center,
                                              style: GoogleFonts.inter(
                                                fontSize: 11,
                                                color: FonexColors.orange,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: _showPaymentQr,
                                        icon: const Icon(
                                          Icons.qr_code_2_rounded,
                                          size: 18,
                                        ),
                                        label: Text(
                                          'Pay Due (Show QR)',
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: FonexColors.accent,
                                          foregroundColor: Colors.white,
                                          elevation: 0,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 20),

                              // Hidden unlock trigger — tap 5x
                              GestureDetector(
                                onTap: _handleSecretTap,
                                behavior: HitTestBehavior.opaque,
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Text(
                                    'FONEX v1.0.0',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: FonexColors.textMuted.withValues(
                                        alpha: 0.4,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// CALL BUTTON — Emergency support call widget for lock screen
// =============================================================================
class _CallButton extends StatelessWidget {
  final String number;
  final String label;
  const _CallButton({required this.number, required this.label});

  Future<void> _call() async {
    final uri = Uri.parse('tel:$number');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  String _formatPhoneNumber(String value) {
    final clean = value.replaceAll(' ', '');
    if (clean.startsWith('+91') && clean.length == 13) {
      final local = clean.substring(3);
      return '+91 ${local.substring(0, 5)} ${local.substring(5)}';
    }
    return value;
  }

  Future<void> _showFullNumberSheet(BuildContext context) async {
    final fullNumber = _formatPhoneNumber(number);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: FonexColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: FonexColors.cardBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    'Support Number',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: FonexColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: FonexColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: FonexColors.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: FonexColors.green.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.phone_rounded,
                      color: FonexColors.green,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SelectableText(
                        fullNumber,
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: FonexColors.green,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.of(sheetContext).pop();
                    await _call();
                  },
                  icon: const Icon(Icons.call_rounded, size: 18),
                  label: Text(
                    'Call Now',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: FonexColors.green,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showFullNumberSheet(context),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [
              FonexColors.green.withValues(alpha: 0.18),
              FonexColors.green.withValues(alpha: 0.08),
            ],
          ),
          border: Border.all(
            color: FonexColors.green.withValues(alpha: 0.35),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: FonexColors.green.withValues(alpha: 0.12),
              blurRadius: 12,
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            const Icon(Icons.phone_rounded, color: FonexColors.green, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: FonexColors.green,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tap to show full number',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: FonexColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: FonexColors.green.withValues(alpha: 0.18),
              ),
              child: const Icon(
                Icons.visibility_rounded,
                color: FonexColors.green,
                size: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// OWNER PIN SCREEN — Secure authentication with premium UI
// =============================================================================
class OwnerPinScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  final String deviceHash;
  const OwnerPinScreen({
    super.key,
    required this.onUnlocked,
    required this.deviceHash,
  });

  @override
  State<OwnerPinScreen> createState() => _OwnerPinScreenState();
}

class _OwnerPinScreenState extends State<OwnerPinScreen>
    with SingleTickerProviderStateMixin {
  static const _channel = MethodChannel(_channelName);
  static const int _pinDigits = 6;

  final _pinController = TextEditingController();
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  int _failedAttempts = 0;
  bool _isCooldown = false;
  int _cooldownRemaining = 0;
  Timer? _cooldownTimer;
  String? _errorMessage;
  bool _isValidating = false;
  bool _obscurePin = true;

  // PIN dots tracking
  String _currentPin = '';

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );
    _pinController.addListener(() {
      setState(() => _currentPin = _pinController.text);
    });
  }

  @override
  void dispose() {
    _pinController.dispose();
    _shakeController.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _triggerShake() {
    _shakeController.reset();
    _shakeController.forward();
  }

  void _startCooldown() {
    setState(() {
      _isCooldown = true;
      _cooldownRemaining = _cooldownSeconds;
      _errorMessage = 'Too many attempts. Wait $_cooldownRemaining seconds.';
    });
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _cooldownRemaining--;
          _errorMessage = 'Please wait $_cooldownRemaining seconds...';
        });
        if (_cooldownRemaining <= 0) {
          timer.cancel();
          setState(() {
            _isCooldown = false;
            _failedAttempts = 0;
            _errorMessage = null;
          });
        }
      }
    });
  }

  Future<void> _validatePin() async {
    if (_isCooldown || _isValidating) return;
    final pin = _pinController.text.trim();
    if (pin.isEmpty) {
      if (pin == '*#06#' || pin == '*#1234#' || pin == '00000000') {
        _pinController.clear();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DebugTerminalScreen()),
        );
        return;
      }
      setState(() => _errorMessage = 'Please enter your PIN');
      return;
    }
    setState(() {
      _isValidating = true;
      _errorMessage = null;
    });
    try {
      final expectedAlgorithmicPin = DeviceHashUtil.getExpectedPin(
        widget.deviceHash,
      );
      bool isValid = false;

      // 1. Check algorithmic PIN (offline)
      if (pin == expectedAlgorithmicPin) {
        isValid = true;
      } else {
        // 2. Check native stored PIN (offline fallback)
        isValid =
            await _channel.invokeMethod<bool>('validatePin', {'pin': pin}) ??
            false;
      }

      // 3. If local checks fail, try server-side unlock
      if (!isValid) {
        setState(() => _errorMessage = 'Verifying with server...');
        try {
          final response = await http
              .post(
                Uri.parse('$_serverBaseUrl/unlock'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'device_hash': widget.deviceHash,
                  'pin': pin,
                }),
              )
              .timeout(const Duration(seconds: 8));

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body) as Map<String, dynamic>;
            isValid = data['success'] == true;
          }
        } catch (_) {
          // Server unreachable — continue with local failure
        }
      }

      if (isValid) {
        if (mounted) Navigator.of(context).pop();
        widget.onUnlocked();
      } else {
        _failedAttempts++;
        _triggerShake();
        if (_failedAttempts >= _maxPinAttempts) {
          _startCooldown();
        } else {
          setState(() {
            _errorMessage =
                'Invalid PIN. ${_maxPinAttempts - _failedAttempts} attempt(s) remaining.';
          });
        }
        _pinController.clear();
      }
    } on PlatformException catch (e) {
      setState(() => _errorMessage = 'Error: ${e.message}');
    } finally {
      if (mounted) setState(() => _isValidating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Scaffold(
        body: AnimatedGradientBg(
          colors: const [
            Color(0xFF06080F),
            Color(0xFF0A1028),
            Color(0xFF0E0A1E),
            Color(0xFF06080F),
          ],
          child: Stack(
            children: [
              const FloatingParticles(count: 8),
              SafeArea(
                child: Column(
                  children: [
                    // App bar
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.arrow_back_ios_rounded,
                              color: FonexColors.textSecondary,
                              size: 20,
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          const Spacer(),
                          Text(
                            'STORE ACCESS',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: FonexColors.textMuted,
                              letterSpacing: 3,
                            ),
                          ),
                          const Spacer(),
                          const SizedBox(width: 48),
                        ],
                      ),
                    ),

                    Expanded(
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Icon
                              GlowIcon(
                                icon: Icons.admin_panel_settings_rounded,
                                color: FonexColors.accent,
                                size: 36,
                                containerSize: 80,
                              ),

                              const SizedBox(height: 28),

                              Text(
                                'Store Owner Access',
                                style: GoogleFonts.inter(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: FonexColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Enter your secure PIN to unlock this device',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: FonexColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Use 6-digit device PIN or owner PIN',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: FonexColors.textMuted,
                                ),
                              ),

                              const SizedBox(height: 36),

                              // PIN dots indicator
                              AnimatedBuilder(
                                animation: _shakeAnimation,
                                builder: (_, child) {
                                  final shake =
                                      sin(_shakeAnimation.value * pi * 4) * 10;
                                  return Transform.translate(
                                    offset: Offset(shake, 0),
                                    child: child,
                                  );
                                },
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: List.generate(_pinDigits, (i) {
                                    final isFilled = i < _currentPin.length;
                                    return AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      width: isFilled ? 16 : 14,
                                      height: isFilled ? 16 : 14,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isFilled
                                            ? FonexColors.accent
                                            : Colors.transparent,
                                        border: Border.all(
                                          color: isFilled
                                              ? FonexColors.accentLight
                                              : FonexColors.cardBorder,
                                          width: 2,
                                        ),
                                        boxShadow: isFilled
                                            ? [
                                                BoxShadow(
                                                  color: FonexColors.accent
                                                      .withValues(alpha: 0.4),
                                                  blurRadius: 8,
                                                ),
                                              ]
                                            : null,
                                      ),
                                    );
                                  }),
                                ),
                              ),

                              const SizedBox(height: 28),

                              // Hidden text field (drives the dots)
                              GlassCard(
                                borderColor: _errorMessage != null
                                    ? FonexColors.red.withValues(alpha: 0.4)
                                    : null,
                                padding: EdgeInsets.zero,
                                borderRadius: 16,
                                child: TextField(
                                  controller: _pinController,
                                  keyboardType: TextInputType.number,
                                  obscureText: _obscurePin,
                                  obscuringCharacter: '●',
                                  enabled: !_isCooldown,
                                  textAlign: TextAlign.center,
                                  maxLength: _pinDigits,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  style: GoogleFonts.inter(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w700,
                                    color: FonexColors.textPrimary,
                                    letterSpacing: 12,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: '• • • • • •',
                                    hintStyle: GoogleFonts.inter(
                                      fontSize: 24,
                                      color: FonexColors.textMuted,
                                      letterSpacing: 8,
                                    ),
                                    border: InputBorder.none,
                                    counterText: '',
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 18,
                                    ),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePin
                                            ? Icons.visibility_off_rounded
                                            : Icons.visibility_rounded,
                                        color: FonexColors.textMuted,
                                      ),
                                      onPressed: () => setState(
                                        () => _obscurePin = !_obscurePin,
                                      ),
                                    ),
                                  ),
                                  onSubmitted: (_) => _validatePin(),
                                ),
                              ),

                              // Error
                              AnimatedSize(
                                duration: const Duration(milliseconds: 300),
                                child: _errorMessage != null
                                    ? Padding(
                                        padding: const EdgeInsets.only(top: 14),
                                        child: GlassCard(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 10,
                                          ),
                                          borderColor: FonexColors.red
                                              .withValues(alpha: 0.3),
                                          borderRadius: 10,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.error_outline_rounded,
                                                color: FonexColors.red,
                                                size: 16,
                                              ),
                                              const SizedBox(width: 8),
                                              Flexible(
                                                child: Text(
                                                  _errorMessage!,
                                                  style: GoogleFonts.inter(
                                                    fontSize: 12,
                                                    color: FonexColors.red,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),

                              const SizedBox(height: 28),

                              // Unlock button
                              SizedBox(
                                width: double.infinity,
                                height: 56,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    gradient: _isCooldown
                                        ? null
                                        : const LinearGradient(
                                            colors: [
                                              FonexColors.accentDark,
                                              FonexColors.accent,
                                            ],
                                          ),
                                    color: _isCooldown
                                        ? FonexColors.card
                                        : null,
                                    boxShadow: _isCooldown
                                        ? null
                                        : [
                                            BoxShadow(
                                              color: FonexColors.accent
                                                  .withValues(alpha: 0.35),
                                              blurRadius: 16,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                  ),
                                  child: ElevatedButton(
                                    onPressed: (_isCooldown || _isValidating)
                                        ? null
                                        : _validatePin,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      shadowColor: Colors.transparent,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    child: _isValidating
                                        ? const SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.5,
                                              color: Colors.white,
                                            ),
                                          )
                                        : Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                _isCooldown
                                                    ? Icons.timer
                                                    : Icons.lock_open_rounded,
                                                size: 20,
                                              ),
                                              const SizedBox(width: 10),
                                              Text(
                                                _isCooldown
                                                    ? 'LOCKED ($_cooldownRemaining)'
                                                    : 'UNLOCK DEVICE',
                                                style: GoogleFonts.inter(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w700,
                                                  letterSpacing: 1.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 40),

                              Text(
                                'Default owner PIN: 1234',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: FonexColors.textMuted.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// DEVICE INFO SCREEN — Detailed device information
// =============================================================================
class DeviceInfoScreen extends StatefulWidget {
  const DeviceInfoScreen({super.key});

  @override
  State<DeviceInfoScreen> createState() => _DeviceInfoScreenState();
}

class _DeviceInfoScreenState extends State<DeviceInfoScreen> {
  static const _channel = MethodChannel(_channelName);
  Map<String, dynamic>? _deviceInfo;
  String _deviceHash = '------';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDeviceInfo();
  }

  Future<void> _loadDeviceInfo() async {
    try {
      final hash = await DeviceHashUtil.getDeviceHash();
      final info = await _channel.invokeMapMethod<String, dynamic>(
        'getDeviceInfo',
      );
      if (mounted) {
        setState(() {
          _deviceHash = hash;
          _deviceInfo = info;
          _isLoading = false;
        });
      }
    } catch (e) {
      AppLogger.log('Error loading device info: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Device Information',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        backgroundColor: FonexColors.surface,
        elevation: 0,
      ),
      body: AnimatedGradientBg(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GlassCard(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const FonexLogo(size: 64),
                          const SizedBox(height: 16),
                          Text(
                            'Device ID',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: FonexColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _deviceHash,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: FonexColors.textPrimary,
                              letterSpacing: 4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildInfoRow(
                      'IMEI',
                      _deviceInfo?['imei']?.toString() ?? 'Not Available',
                    ),
                    _buildInfoRow(
                      'Model',
                      _deviceInfo?['deviceModel']?.toString() ?? 'Unknown',
                    ),
                    _buildInfoRow(
                      'Manufacturer',
                      _deviceInfo?['manufacturer']?.toString() ?? 'Unknown',
                    ),
                    _buildInfoRow(
                      'Android Version',
                      'Android ${_deviceInfo?['androidVersion'] ?? 'Unknown'}',
                    ),
                    _buildInfoRow(
                      'Device Owner',
                      _deviceInfo?['isDeviceOwner'] == true
                          ? 'Active'
                          : 'Not Active',
                      _deviceInfo?['isDeviceOwner'] == true
                          ? FonexColors.green
                          : FonexColors.red,
                    ),
                    _buildInfoRow(
                      'Lock Status',
                      _deviceInfo?['isDeviceLocked'] == true
                          ? 'Locked'
                          : 'Unlocked',
                      _deviceInfo?['isDeviceLocked'] == true
                          ? FonexColors.red
                          : FonexColors.green,
                    ),
                    const SizedBox(height: 20),
                    GlassCard(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.info_outline_rounded,
                                color: FonexColors.accent,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'About This Device',
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: FonexColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'This device is protected by FONEX Device Control System. '
                            'Device Owner status is required for full functionality.',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: FonexColors.textSecondary,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: FonexColors.card.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: FonexColors.cardBorder.withValues(
                                  alpha: 0.7,
                                ),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.person_rounded,
                                      color: FonexColors.accent,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Software Developer: Anupam Pradhan',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: FonexColors.textSecondary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.location_on_rounded,
                                      color: FonexColors.textMuted,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Namkhana',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: FonexColors.textMuted,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, [Color? valueColor]) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 4,
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: FonexColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 5,
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: valueColor ?? FonexColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// SETTINGS SCREEN — App settings and preferences
// =============================================================================
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _channel = MethodChannel(_channelName);
  bool _isExporting = false;
  bool _isCheckingBackup = true;
  bool _isBackupEnabled = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshBackupStatus());
  }

  Future<void> _openAddAccountSettings() async {
    try {
      final opened =
          await _channel.invokeMethod<bool>('openAddAccountSettings') ?? false;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            opened
                ? 'Opening account settings...'
                : 'Unable to open account settings.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to open account settings.')),
      );
    }
  }

  Future<void> _openCreateGoogleEmail() async {
    try {
      final opened =
          await _channel.invokeMethod<bool>('openCreateGoogleAccount') ?? false;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            opened
                ? 'Opening Google account creation...'
                : 'Unable to open Google account creation.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to open Google account creation.'),
        ),
      );
    }
  }

  Future<void> _refreshBackupStatus() async {
    try {
      final enabled =
          await _channel.invokeMethod<bool>('isGoogleBackupEnabled') ?? false;
      if (!mounted) return;
      setState(() {
        _isBackupEnabled = enabled;
        _isCheckingBackup = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isBackupEnabled = false;
        _isCheckingBackup = false;
      });
    }
  }

  Future<void> _openBackupSettings() async {
    try {
      final opened =
          await _channel.invokeMethod<bool>('openBackupSettings') ?? false;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            opened
                ? 'Opening backup settings...'
                : 'Unable to open backup settings.',
          ),
        ),
      );
      if (opened) {
        // Give settings UI a moment before re-checking status.
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            unawaited(_refreshBackupStatus());
          }
        });
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to open backup settings.')),
      );
    }
  }

  Future<void> _exportAuditLogs() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      final diagnostics = RealtimeCommandService.diagnosticsNotifier.value;
      final syncStatus = await SyncService().getSyncStatus();
      final pendingAcks = RealtimeCommandService().pendingAckQueue;
      final buffer = StringBuffer()
        ..writeln('FONEX Audit Export')
        ..writeln('Generated: ${DateTime.now().toIso8601String()}')
        ..writeln('')
        ..writeln('Realtime Diagnostics:')
        ..writeln('  started=${diagnostics.started}')
        ..writeln('  subscribed=${diagnostics.subscribed}')
        ..writeln('  reconnecting=${diagnostics.reconnecting}')
        ..writeln('  reconnect_attempt=${diagnostics.reconnectAttempt}')
        ..writeln('  last_status=${diagnostics.lastStatus}')
        ..writeln(
          '  last_disconnect_reason=${diagnostics.lastDisconnectReason}',
        )
        ..writeln('  last_subscribed_at=${diagnostics.lastSubscribedAt}')
        ..writeln('  last_command_id=${diagnostics.lastCommandId}')
        ..writeln('  last_command=${diagnostics.lastCommand}')
        ..writeln('  last_command_stage=${diagnostics.lastCommandStage}')
        ..writeln('  last_ack_attempts=${diagnostics.lastAckAttempts}')
        ..writeln('  last_ack_status=${diagnostics.lastAckStatusCode}')
        ..writeln('  last_ack_result=${diagnostics.lastAckResult}')
        ..writeln('  pending_ack_count=${diagnostics.pendingAckCount}')
        ..writeln('')
        ..writeln('Pending ACK Queue:');
      for (final item in pendingAcks) {
        buffer.writeln(
          '  - id=${item.commandId} cmd=${item.command} device=${item.deviceId} '
          'queued=${item.queuedAt.toIso8601String()} retries=${item.retryCount} '
          'status=${item.lastStatusCode} result=${item.lastResult}',
        );
      }
      buffer
        ..writeln('')
        ..writeln('Sync Status: $syncStatus')
        ..writeln('')
        ..writeln('App Logs:')
        ..writeln(AppLogger.toMultilineText());

      final dir = await getTemporaryDirectory();
      final filename =
          'fonex_audit_${DateTime.now().millisecondsSinceEpoch}.log';
      final file = File('${dir.path}/$filename');
      await file.writeAsString(buffer.toString());

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/plain')],
        text: 'FONEX audit log export',
        subject: 'FONEX audit log',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Audit log exported: ${file.path}')),
      );
      AppLogger.log('Audit log exported: ${file.path}');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Audit export failed: $e')));
      AppLogger.log('Audit export failed: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Settings',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        backgroundColor: FonexColors.surface,
        elevation: 0,
      ),
      body: AnimatedGradientBg(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSettingsSection('Notifications', [
                _buildSettingTile(
                  icon: Icons.notifications_active_rounded,
                  title: 'Notification Preferences',
                  subtitle: 'Reminder frequency + language (BN/EN/Both)',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const NotificationPreferencesScreen(),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 24),
              _buildSettingsSection('Protection Health', [
                _buildSettingTile(
                  icon: Icons.health_and_safety_rounded,
                  title: 'Background Health Monitor',
                  subtitle: 'Realtime status, reconnect reason, ACK queue',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const BackgroundHealthDetailsScreen(),
                    ),
                  ),
                ),
                _buildSettingTile(
                  icon: Icons.security_update_warning_rounded,
                  title: 'Anti-kill Setup Assistant',
                  subtitle: 'Auto-start + battery unrestricted guidance',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AntiKillSetupAssistantScreen(),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 24),
              _buildSettingsSection('Diagnostics', [
                _buildSettingTile(
                  icon: Icons.build_circle_outlined,
                  title: 'Recovery Actions',
                  subtitle:
                      'Reconnect realtime, resync state, clear stale lock flag',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const RecoveryActionsScreen(),
                    ),
                  ),
                ),
                _buildSettingTile(
                  icon: Icons.ios_share_rounded,
                  title: 'Export Audit Log',
                  subtitle: _isExporting
                      ? 'Preparing export...'
                      : 'Share app logs + realtime diagnostics',
                  onTap: _isExporting ? null : _exportAuditLogs,
                ),
              ]),
              const SizedBox(height: 24),
              _buildSettingsSection('App Information', [
                _buildSettingTile(
                  icon: Icons.info_outline_rounded,
                  title: 'About FONEX',
                  subtitle: 'Version ${FonexConfig.appVersion}',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AboutScreen()),
                  ),
                ),
                _buildSettingTile(
                  icon: Icons.store_rounded,
                  title: 'Store Information',
                  subtitle: _storeName,
                ),
              ]),
              const SizedBox(height: 24),
              _buildSettingsSection('Google Services', [
                _buildSettingTile(
                  icon: Icons.backup_rounded,
                  title: 'Google Backup',
                  subtitle: _isCheckingBackup
                      ? 'Checking backup service...'
                      : _isBackupEnabled
                      ? 'Backup service is active'
                      : 'Backup service is not active',
                  onTap: _openBackupSettings,
                ),
                _buildSettingTile(
                  icon: Icons.refresh_rounded,
                  title: 'Refresh Backup Status',
                  subtitle: 'Re-check Google backup service state',
                  onTap: _refreshBackupStatus,
                ),
              ]),
              const SizedBox(height: 24),
              _buildSettingsSection('Support', [
                _buildSettingTile(
                  icon: Icons.phone_rounded,
                  title: 'Contact Store',
                  subtitle: _supportPhone1,
                  onTap: () => launchUrl(Uri.parse('tel:$_supportPhone1')),
                ),
                _buildSettingTile(
                  icon: Icons.alternate_email_rounded,
                  title: 'Create Google Email',
                  subtitle: 'Open Google sign-up page',
                  onTap: _openCreateGoogleEmail,
                ),
                _buildSettingTile(
                  icon: Icons.person_add_alt_1_rounded,
                  title: 'Add Account',
                  subtitle: 'Open Android account settings',
                  onTap: _openAddAccountSettings,
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: FonexColors.textMuted,
              letterSpacing: 1,
            ),
          ),
        ),
        ...children,
      ],
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: FonexColors.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: FonexColors.accent, size: 20),
          ),
          title: Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: FonexColors.textPrimary,
            ),
          ),
          subtitle: subtitle != null
              ? Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: FonexColors.textSecondary,
                  ),
                )
              : null,
          trailing: const Icon(
            Icons.chevron_right_rounded,
            color: FonexColors.textMuted,
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}

class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen> {
  bool _enabled = true;
  ReminderProfile _profile = ReminderProfile.balanced;
  ReminderLanguage _language = ReminderLanguage.both;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _enabled = prefs.getBool(_keyReminderEnabled) ?? true;
      _profile = ReminderSettings.profileFromRaw(
        prefs.getString(_keyReminderProfile),
      );
      _language = ReminderSettings.languageFromRaw(
        prefs.getString(_keyReminderLanguage),
      );
      _loading = false;
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyReminderEnabled, _enabled);
    await prefs.setString(
      _keyReminderProfile,
      ReminderSettings.profileToRaw(_profile),
    );
    await prefs.setString(
      _keyReminderLanguage,
      ReminderSettings.languageToRaw(_language),
    );
    AppLogger.log(
      'Reminder settings updated: enabled=$_enabled profile=$_profile lang=$_language',
    );
  }

  String _profileLabel(ReminderProfile profile) {
    switch (profile) {
      case ReminderProfile.frequent:
        return 'Frequent';
      case ReminderProfile.minimal:
        return 'Minimal';
      case ReminderProfile.balanced:
        return 'Balanced';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Notification Preferences',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        backgroundColor: FonexColors.surface,
      ),
      body: AnimatedGradientBg(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  GlassCard(
                    child: SwitchListTile(
                      value: _enabled,
                      title: Text(
                        'Enable local reminders',
                        style: GoogleFonts.inter(
                          color: FonexColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        'Applies without server push',
                        style: GoogleFonts.inter(
                          color: FonexColors.textSecondary,
                        ),
                      ),
                      onChanged: (value) async {
                        setState(() => _enabled = value);
                        await _save();
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  GlassCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Reminder Frequency',
                          style: GoogleFonts.inter(
                            color: FonexColors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        for (final profile in ReminderProfile.values)
                          RadioListTile<ReminderProfile>(
                            value: profile,
                            groupValue: _profile,
                            activeColor: FonexColors.accent,
                            title: Text(
                              _profileLabel(profile),
                              style: GoogleFonts.inter(
                                color: FonexColors.textPrimary,
                              ),
                            ),
                            onChanged: (value) async {
                              if (value == null) return;
                              setState(() => _profile = value);
                              await _save();
                            },
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  GlassCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Reminder Language',
                          style: GoogleFonts.inter(
                            color: FonexColors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        RadioListTile<ReminderLanguage>(
                          value: ReminderLanguage.both,
                          groupValue: _language,
                          activeColor: FonexColors.accent,
                          title: Text(
                            'Bengali + English',
                            style: GoogleFonts.inter(
                              color: FonexColors.textPrimary,
                            ),
                          ),
                          onChanged: (value) async {
                            if (value == null) return;
                            setState(() => _language = value);
                            await _save();
                          },
                        ),
                        RadioListTile<ReminderLanguage>(
                          value: ReminderLanguage.bn,
                          groupValue: _language,
                          activeColor: FonexColors.accent,
                          title: Text(
                            'Bengali only',
                            style: GoogleFonts.inter(
                              color: FonexColors.textPrimary,
                            ),
                          ),
                          onChanged: (value) async {
                            if (value == null) return;
                            setState(() => _language = value);
                            await _save();
                          },
                        ),
                        RadioListTile<ReminderLanguage>(
                          value: ReminderLanguage.en,
                          groupValue: _language,
                          activeColor: FonexColors.accent,
                          title: Text(
                            'English only',
                            style: GoogleFonts.inter(
                              color: FonexColors.textPrimary,
                            ),
                          ),
                          onChanged: (value) async {
                            if (value == null) return;
                            setState(() => _language = value);
                            await _save();
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class BackgroundHealthDetailsScreen extends StatelessWidget {
  const BackgroundHealthDetailsScreen({super.key});

  String _formatTime(DateTime? time) {
    if (time == null) return 'Never';
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: GoogleFonts.inter(
                color: FonexColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(
                color: FonexColors.textPrimary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Background Health',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        backgroundColor: FonexColors.surface,
      ),
      body: AnimatedGradientBg(
        child: ValueListenableBuilder<RealtimeDiagnostics>(
          valueListenable: RealtimeCommandService.diagnosticsNotifier,
          builder: (context, diagnostics, _) {
            final queue = RealtimeCommandService().pendingAckQueue;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                GlassCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Realtime Monitor',
                        style: GoogleFonts.inter(
                          color: FonexColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildRow('Status', diagnostics.lastStatus),
                      _buildRow(
                        'Subscribed',
                        diagnostics.subscribed ? 'Yes' : 'No',
                      ),
                      _buildRow(
                        'Last subscribe',
                        _formatTime(diagnostics.lastSubscribedAt),
                      ),
                      _buildRow(
                        'Last reconnect reason',
                        diagnostics.lastDisconnectReason ?? 'None',
                      ),
                      _buildRow(
                        'Last command',
                        diagnostics.lastCommandId == null
                            ? 'No command received'
                            : '${diagnostics.lastCommand} (${diagnostics.lastCommandId})',
                      ),
                      _buildRow(
                        'Command stage',
                        diagnostics.lastCommandStage ?? '-',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                GlassCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ACK Queue Visibility',
                        style: GoogleFonts.inter(
                          color: FonexColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildRow(
                        'Last ACK',
                        'attempts=${diagnostics.lastAckAttempts ?? 0}, status=${diagnostics.lastAckStatusCode ?? '-'}',
                      ),
                      _buildRow(
                        'Last ACK result',
                        diagnostics.lastAckResult ?? '-',
                      ),
                      _buildRow('Pending ACK count', '${queue.length}'),
                      const SizedBox(height: 8),
                      if (queue.isEmpty)
                        Text(
                          'No pending ACK items.',
                          style: GoogleFonts.inter(
                            color: FonexColors.textSecondary,
                            fontSize: 12,
                          ),
                        )
                      else
                        ...queue.take(5).map((item) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              '${item.command} • ${item.commandId} • retries=${item.retryCount}',
                              style: GoogleFonts.inter(
                                color: FonexColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                ValueListenableBuilder<int>(
                  valueListenable: CrashReporter.crashCountNotifier,
                  builder: (context, crashCount, _) {
                    return GlassCard(
                      padding: const EdgeInsets.all(16),
                      borderColor:
                          (crashCount > 0
                                  ? FonexColors.orange
                                  : FonexColors.cardBorder)
                              .withValues(alpha: 0.35),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Crash Alerts',
                            style: GoogleFonts.inter(
                              color: FonexColors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _buildRow('Captured crashes', '$crashCount'),
                          FutureBuilder<List<Map<String, dynamic>>>(
                            future: CrashReporter.getRecentEvents(limit: 3),
                            builder: (context, snapshot) {
                              final events = snapshot.data ?? const [];
                              if (events.isEmpty) {
                                return Text(
                                  'No crash events captured.',
                                  style: GoogleFonts.inter(
                                    color: FonexColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                );
                              }
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: events
                                    .map((event) {
                                      final source =
                                          event['source']?.toString() ??
                                          'unknown';
                                      final message =
                                          event['message']?.toString() ?? '-';
                                      final ts = event['ts']?.toString() ?? '-';
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        child: Text(
                                          '$ts • $source • ${message.length > 90 ? '${message.substring(0, 90)}...' : message}',
                                          style: GoogleFonts.inter(
                                            color: FonexColors.textSecondary,
                                            fontSize: 11,
                                          ),
                                        ),
                                      );
                                    })
                                    .toList(growable: false),
                              );
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class AntiKillSetupAssistantScreen extends StatefulWidget {
  const AntiKillSetupAssistantScreen({super.key});

  @override
  State<AntiKillSetupAssistantScreen> createState() =>
      _AntiKillSetupAssistantScreenState();
}

class _AntiKillSetupAssistantScreenState
    extends State<AntiKillSetupAssistantScreen> {
  static const _channel = MethodChannel(_channelName);
  bool _isIgnoringBatteryOptimizations = false;
  bool _autoStartDone = false;
  bool _batteryDone = false;
  String _manufacturer = 'android';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final info =
        await _channel.invokeMapMethod<String, dynamic>('getDeviceInfo') ??
        <String, dynamic>{};
    final ignoring =
        await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ??
        false;
    if (!mounted) return;
    setState(() {
      _manufacturer = (info['manufacturer']?.toString() ?? 'android')
          .toLowerCase();
      _isIgnoringBatteryOptimizations = ignoring;
      _autoStartDone = prefs.getBool(_keyAntiKillAutoStartDone) ?? false;
      _batteryDone = prefs.getBool(_keyAntiKillBatteryDone) ?? ignoring;
    });
  }

  Future<void> _setDone(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    await _load();
  }

  List<String> _stepsForBrand() {
    if (_manufacturer.contains('xiaomi') || _manufacturer.contains('redmi')) {
      return const <String>[
        'Open Auto-start settings and allow FONEX.',
        'Set Battery to No restrictions for FONEX.',
        'Lock FONEX in recent apps if available.',
      ];
    }
    if (_manufacturer.contains('oppo') || _manufacturer.contains('realme')) {
      return const <String>[
        'Allow startup manager access for FONEX.',
        'Disable battery optimization for FONEX.',
        'Allow background activity.',
      ];
    }
    if (_manufacturer.contains('vivo') || _manufacturer.contains('iqoo')) {
      return const <String>[
        'Enable autostart for FONEX.',
        'Set background power usage to unrestricted.',
        'Disable background app kill for FONEX.',
      ];
    }
    if (_manufacturer.contains('samsung')) {
      return const <String>[
        'Put FONEX in Never sleeping apps.',
        'Disable battery optimization for FONEX.',
        'Allow background activity in app info.',
      ];
    }
    return const <String>[
      'Allow auto-start/background run for FONEX.',
      'Disable battery optimization for FONEX.',
      'Ensure notifications are enabled for reminders.',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final allDone =
        _autoStartDone && (_batteryDone || _isIgnoringBatteryOptimizations);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Anti-kill Setup Assistant',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        backgroundColor: FonexColors.surface,
      ),
      body: AnimatedGradientBg(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            GlassCard(
              child: ListTile(
                leading: Icon(
                  allDone ? Icons.check_circle : Icons.warning_amber_rounded,
                  color: allDone ? FonexColors.green : FonexColors.orange,
                ),
                title: Text(
                  allDone ? 'Setup complete' : 'Setup incomplete',
                  style: GoogleFonts.inter(
                    color: FonexColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  'Brand detected: ${_manufacturer.toUpperCase()}',
                  style: GoogleFonts.inter(color: FonexColors.textSecondary),
                ),
              ),
            ),
            const SizedBox(height: 14),
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recommended Steps',
                    style: GoogleFonts.inter(
                      color: FonexColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (int i = 0; i < _stepsForBrand().length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '${i + 1}. ${_stepsForBrand()[i]}',
                        style: GoogleFonts.inter(
                          color: FonexColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            GlassCard(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.play_circle_outline_rounded),
                    title: Text(
                      'Open Auto-start settings',
                      style: GoogleFonts.inter(color: FonexColors.textPrimary),
                    ),
                    trailing: const Icon(Icons.open_in_new_rounded),
                    onTap: () => _channel.invokeMethod('openAutoStartSettings'),
                  ),
                  SwitchListTile(
                    value: _autoStartDone,
                    title: Text(
                      'Mark auto-start step complete',
                      style: GoogleFonts.inter(color: FonexColors.textPrimary),
                    ),
                    onChanged: (value) =>
                        _setDone(_keyAntiKillAutoStartDone, value),
                  ),
                  ListTile(
                    leading: const Icon(Icons.battery_saver_rounded),
                    title: Text(
                      'Open battery optimization settings',
                      style: GoogleFonts.inter(color: FonexColors.textPrimary),
                    ),
                    trailing: const Icon(Icons.open_in_new_rounded),
                    onTap: () => _channel.invokeMethod(
                      'requestIgnoreBatteryOptimizations',
                    ),
                  ),
                  SwitchListTile(
                    value: _batteryDone || _isIgnoringBatteryOptimizations,
                    title: Text(
                      _isIgnoringBatteryOptimizations
                          ? 'Battery already unrestricted'
                          : 'Mark battery step complete',
                      style: GoogleFonts.inter(color: FonexColors.textPrimary),
                    ),
                    onChanged: _isIgnoringBatteryOptimizations
                        ? null
                        : (value) => _setDone(_keyAntiKillBatteryDone, value),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RecoveryActionsScreen extends StatefulWidget {
  const RecoveryActionsScreen({super.key});

  @override
  State<RecoveryActionsScreen> createState() => _RecoveryActionsScreenState();
}

class _RecoveryActionsScreenState extends State<RecoveryActionsScreen> {
  static const _channel = MethodChannel(_channelName);
  bool _busy = false;
  int _supportUntilMs = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSupportWindow());
  }

  Future<void> _loadSupportWindow() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _supportUntilMs = prefs.getInt(_keySupportUnlockUntilMs) ?? 0;
    });
  }

  Future<void> _runAction(String label, Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$label completed')));
      AppLogger.log('Recovery action completed: $label');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$label failed: $e')));
      AppLogger.log('Recovery action failed: $label error=$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reconnectRealtime() async {
    await RealtimeCommandService().reconnectNow();
    await RealtimeCommandService().retryPendingAcks();
  }

  Future<void> _resyncNow() async {
    await DeviceStateManager().syncStateWithNative();
    await SyncService().manualSync();
    RealtimeCommandService().ensureConnected();
  }

  Future<void> _clearStaleLockFlag() async {
    final isNativeLocked =
        await _channel.invokeMethod<bool>('isDeviceLocked') ?? false;
    if (isNativeLocked) {
      throw Exception('Native device lock is active. Unlock first.');
    }
    await _channel.invokeMethod('setDeviceLocked', {'locked': false});
    AppLogger.log('Stale local lock flag cleared from recovery actions');
  }

  Future<void> _activateSupportWindow() async {
    final pinController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Enter local PIN'),
          content: TextField(
            controller: pinController,
            keyboardType: TextInputType.number,
            obscureText: true,
            decoration: const InputDecoration(hintText: 'Owner PIN'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Activate 30 min'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    final pin = pinController.text.trim();
    final valid =
        await _channel.invokeMethod<bool>('validatePin', {'pin': pin}) ?? false;
    if (!valid) {
      throw Exception('Invalid PIN');
    }

    final until = DateTime.now().add(const Duration(minutes: 30));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySupportUnlockUntilMs, until.millisecondsSinceEpoch);

    await _channel.invokeMethod('setDeviceLocked', {'locked': false});
    await _channel.invokeMethod('stopDeviceLock');
    AppLogger.log(
      'Support unlock window enabled until ${until.toIso8601String()}',
    );
    await _loadSupportWindow();
  }

  Future<void> _endSupportWindowNow() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keySupportUnlockUntilMs);
    AppLogger.log('Support unlock window disabled manually');
    await _loadSupportWindow();
  }

  @override
  Widget build(BuildContext context) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final active = _supportUntilMs > nowMs;
    final remaining = active
        ? Duration(milliseconds: _supportUntilMs - nowMs)
        : Duration.zero;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Recovery Actions',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        backgroundColor: FonexColors.surface,
      ),
      body: AnimatedGradientBg(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recovery Panel',
                    style: GoogleFonts.inter(
                      color: FonexColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.tonal(
                        onPressed: _busy
                            ? null
                            : () => _runAction(
                                'Reconnect realtime',
                                _reconnectRealtime,
                              ),
                        child: const Text('Reconnect Realtime Now'),
                      ),
                      FilledButton.tonal(
                        onPressed: _busy
                            ? null
                            : () => _runAction('Resync state', _resyncNow),
                        child: const Text('Resync State Now'),
                      ),
                      FilledButton.tonal(
                        onPressed: _busy
                            ? null
                            : () => _runAction(
                                'Clear stale lock flag',
                                _clearStaleLockFlag,
                              ),
                        child: const Text('Clear Stale Lock Flag'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            GlassCard(
              padding: const EdgeInsets.all(16),
              borderColor:
                  (active ? FonexColors.orange : FonexColors.cardBorder)
                      .withValues(alpha: 0.4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Safe Mode for Support',
                    style: GoogleFonts.inter(
                      color: FonexColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    active
                        ? 'Temporary unlock active for ${remaining.inMinutes} min.'
                        : 'Activate a 30-minute local support unlock window.',
                    style: GoogleFonts.inter(
                      color: FonexColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    children: [
                      FilledButton(
                        onPressed: _busy
                            ? null
                            : () => _runAction(
                                'Enable support unlock window',
                                _activateSupportWindow,
                              ),
                        child: const Text('Activate 30 min Window'),
                      ),
                      OutlinedButton(
                        onPressed: _busy || !active
                            ? null
                            : () => _runAction(
                                'Disable support window',
                                _endSupportWindowNow,
                              ),
                        child: const Text('End Support Window'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// ABOUT SCREEN — App information and help
// =============================================================================
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen>
    with TickerProviderStateMixin {
  static const String _facebookProfileUrl =
      'https://www.facebook.com/anupam.pradhan.35110/';
  static const String _facebookProfileAssetPath =
      'assets/images/facebook_profilephoto/FB_IMG_1743254515357.jpg';
  static const String _storeName = FonexConfig.storeName;
  static const String _storeAddress = FonexConfig.storeAddress;
  static const String _supportPhone1 = FonexConfig.supportPhone1;
  static const String _supportPhone2 = FonexConfig.supportPhone2;

  late AnimationController _staggerController;
  late AnimationController _pulseController;
  late AnimationController _shimmerController;
  late List<Animation<double>> _fadeAnims;
  late List<Animation<Offset>> _slideAnims;
  late Animation<double> _pulseAnim;
  late Animation<double> _shimmerAnim;

  @override
  void initState() {
    super.initState();

    _staggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
    _shimmerAnim = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.linear),
    );

    _fadeAnims = List.generate(5, (i) {
      final start = (i * 0.15).clamp(0.0, 1.0);
      final end = (start + 0.4).clamp(0.0, 1.0);
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _staggerController,
          curve: Interval(start, end, curve: Curves.easeOutCubic),
        ),
      );
    });
    _slideAnims = List.generate(5, (i) {
      final start = (i * 0.15).clamp(0.0, 1.0);
      final end = (start + 0.4).clamp(0.0, 1.0);
      return Tween<Offset>(
        begin: const Offset(0, 30),
        end: Offset.zero,
      ).animate(
        CurvedAnimation(
          parent: _staggerController,
          curve: Interval(start, end, curve: Curves.easeOutCubic),
        ),
      );
    });

    _staggerController.forward();
  }

  @override
  void dispose() {
    _staggerController.dispose();
    _pulseController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  Widget _buildStaggeredItem(int index, Widget child) {
    return AnimatedBuilder(
      animation: _staggerController,
      builder: (context, _) => Opacity(
        opacity: _fadeAnims[index].value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: _slideAnims[index].value,
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'About',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        backgroundColor: FonexColors.surface,
        elevation: 0,
      ),
      body: AnimatedGradientBg(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              _buildStaggeredItem(
                0,
                Column(
                  children: [
                    const FonexLogo(size: 80),
                    const SizedBox(height: 24),
                    Text(
                      'FONEX',
                      style: GoogleFonts.inter(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: FonexColors.textPrimary,
                        letterSpacing: 4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Device Control System',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: FonexColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onLongPress: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const DebugTerminalScreen(),
                          ),
                        );
                      },
                      child: Text(
                        'Version ${FonexConfig.appVersion}',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: FonexColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              _buildStaggeredItem(
                1,
                GlassCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Powered by',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: FonexColors.textMuted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _storeName,
                        style: GoogleFonts.inter(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: FonexColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildContactRow(
                        Icons.location_on_rounded,
                        _storeAddress,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      _buildContactRow(Icons.phone_rounded, _supportPhone1),
                      const SizedBox(height: 12),
                      _buildContactRow(Icons.phone_rounded, _supportPhone2),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _buildStaggeredItem(
                2,
                GlassCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Help & Support',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: FonexColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'If you need help with your device or have questions about your due payment, please contact $_storeName using the phone numbers above.',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: FonexColors.textSecondary,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _buildStaggeredItem(3, _buildDeveloperCard()),
              const SizedBox(height: 24),
              _buildStaggeredItem(
                4,
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.code_rounded,
                      color: FonexColors.textMuted,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This app and system was designed and developed by Anupam Pradhan',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: FonexColors.textMuted,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeveloperCard() {
    return GlassCard(
      padding: const EdgeInsets.all(24),
      borderColor: FonexColors.accent.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                color: FonexColors.accent,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Developed by',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: FonexColors.textMuted,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          InkWell(
            onTap: () => _openDeveloperProfile(context),
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF1A2238).withValues(alpha: 0.7),
                    FonexColors.accent.withValues(alpha: 0.15),
                    FonexColors.purple.withValues(alpha: 0.1),
                  ],
                ),
                border: Border.all(
                  color: FonexColors.accent.withValues(alpha: 0.4),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: FonexColors.accent.withValues(alpha: 0.12),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Row(
                children: [
                  AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (context, child) => Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: FonexColors.accent.withValues(
                              alpha: _pulseAnim.value,
                            ),
                            blurRadius: 16,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: FonexColors.accent.withValues(alpha: 0.7),
                            width: 2.5,
                          ),
                        ),
                        child: ClipOval(
                          child: Image.asset(
                            _facebookProfileAssetPath,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _buildProfilePlaceholder(),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AnimatedBuilder(
                          animation: _shimmerAnim,
                          builder: (context, _) => ShaderMask(
                            shaderCallback: (bounds) => LinearGradient(
                              colors: const [
                                Color(0xFFE2ECFF),
                                Color(0xFFFFFFFF),
                                Color(0xFF89F0DA),
                                Color(0xFFE2ECFF),
                              ],
                              stops: [
                                (_shimmerAnim.value - 0.3).clamp(0.0, 1.0),
                                _shimmerAnim.value.clamp(0.0, 1.0),
                                (_shimmerAnim.value + 0.3).clamp(0.0, 1.0),
                                (_shimmerAnim.value + 0.6).clamp(0.0, 1.0),
                              ],
                            ).createShader(bounds),
                            child: Text(
                              'Anupam Pradhan',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            gradient: LinearGradient(
                              colors: [
                                FonexColors.accent.withValues(alpha: 0.2),
                                FonexColors.purple.withValues(alpha: 0.15),
                              ],
                            ),
                          ),
                          child: Text(
                            'Software Developer',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: FonexColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on_rounded,
                              size: 14,
                              color: FonexColors.textMuted,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Namkhana',
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                color: FonexColors.textMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0.0, end: 1.0),
                          duration: const Duration(milliseconds: 1400),
                          curve: Curves.easeOutCubic,
                          builder: (context, widthFactor, _) {
                            return Align(
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: widthFactor,
                                child: Container(
                                  height: 2,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(999),
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFF5AA3FF),
                                        Color(0xFF89F0DA),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF1877F2,
                            ).withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(
                                0xFF1877F2,
                              ).withValues(alpha: 0.45),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.max,
                            children: [
                              const Icon(
                                Icons.facebook_rounded,
                                color: Color(0xFF5AA3FF),
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Open Facebook Profile',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF9BC5FF),
                                  ),
                                ),
                              ),
                              const Spacer(),
                              const Icon(
                                Icons.open_in_new_rounded,
                                color: Color(0xFF9BC5FF),
                                size: 14,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openDeveloperProfile(BuildContext context) async {
    final externalUri = Uri.parse(_facebookProfileUrl);
    final fallbackUri = Uri.parse(
      'https://m.facebook.com/anupam.pradhan.35110/',
    );

    try {
      final openedInApp = await launchUrl(
        externalUri,
        mode: LaunchMode.inAppBrowserView,
      );
      if (openedInApp) return;
    } catch (_) {}

    try {
      final openedExternal = await launchUrl(
        externalUri,
        mode: LaunchMode.externalApplication,
      );
      if (openedExternal) return;
    } catch (_) {}

    try {
      final openedFallback = await launchUrl(
        fallbackUri,
        mode: LaunchMode.inAppBrowserView,
      );
      if (openedFallback) return;
    } catch (_) {}

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open Facebook profile right now.'),
        ),
      );
    }
  }

  Widget _buildContactRow(IconData icon, String text, {int maxLines = 1}) {
    return Row(
      crossAxisAlignment: maxLines > 1
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Icon(icon, color: FonexColors.accent, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            maxLines: maxLines,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: FonexColors.textPrimary,
              height: maxLines > 1 ? 1.4 : 1.0,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfilePlaceholder() {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [FonexColors.accent, FonexColors.purple],
        ),
      ),
      child: Center(
        child: Text(
          'AP',
          style: GoogleFonts.inter(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// PAYMENT SCHEDULE SCREEN — Due payment schedule and history
// =============================================================================
class PaymentScheduleScreen extends StatelessWidget {
  final int daysRemaining;
  final int lockWindowDays;
  final bool isPaidInFull;
  final DateTime? lastServerSync;

  const PaymentScheduleScreen({
    super.key,
    required this.daysRemaining,
    required this.lockWindowDays,
    required this.isPaidInFull,
    this.lastServerSync,
  });

  @override
  Widget build(BuildContext context) {
    final nextPaymentDate = DateTime.now().add(Duration(days: daysRemaining));
    final urgentColor = daysRemaining <= 7
        ? FonexColors.red
        : daysRemaining <= 14
        ? FonexColors.orange
        : FonexColors.green;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Payment Schedule',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        backgroundColor: FonexColors.surface,
        elevation: 0,
      ),
      body: AnimatedGradientBg(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GlassCard(
                padding: const EdgeInsets.all(24),
                borderColor: urgentColor.withValues(alpha: 0.3),
                child: Column(
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      color: urgentColor,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Next Payment Due',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: FonexColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _formatDate(nextPaymentDate),
                      style: GoogleFonts.inter(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: urgentColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$daysRemaining days remaining',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: FonexColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Payment Information',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: FonexColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              GlassCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _buildInfoRow('Store', _storeName),
                    const Divider(color: FonexColors.cardBorder),
                    _buildInfoRow('Contact', _supportPhone1),
                    const Divider(color: FonexColors.cardBorder),
                    _buildInfoRow('Payment Period', '$lockWindowDays days'),
                    const Divider(color: FonexColors.cardBorder),
                    _buildInfoRow(
                      'Status',
                      isPaidInFull
                          ? 'Paid in Full'
                          : (daysRemaining > 0 ? 'Due Active' : 'Locked'),
                      isPaidInFull
                          ? FonexColors.green
                          : (daysRemaining > 0
                                ? FonexColors.green
                                : FonexColors.red),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Payment History',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: FonexColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              GlassCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _buildInfoRow(
                      'Latest Status',
                      isPaidInFull ? 'Paid in Full' : 'Amount Due',
                      isPaidInFull ? FonexColors.green : FonexColors.orange,
                    ),
                    const Divider(color: FonexColors.cardBorder),
                    _buildInfoRow(
                      'Last Server Sync',
                      lastServerSync != null
                          ? _formatDate(lastServerSync!)
                          : 'Not synced yet',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              GlassCard(
                padding: const EdgeInsets.all(20),
                borderColor: FonexColors.orange.withValues(alpha: 0.3),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: FonexColors.orange,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Please visit ${_storeName} to clear your due amount before the due date to avoid device lock.',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: FonexColors.textPrimary,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, [Color? valueColor]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: FonexColors.textSecondary,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: valueColor ?? FonexColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

// =============================================================================
// QR CODE SCREEN — Display device QR code for identification
// =============================================================================
class QRCodeScreen extends StatefulWidget {
  const QRCodeScreen({super.key});

  @override
  State<QRCodeScreen> createState() => _QRCodeScreenState();
}

class _QRCodeScreenState extends State<QRCodeScreen> {
  String _deviceHash = '------';
  String _deviceInfo = '';

  @override
  void initState() {
    super.initState();
    _loadDeviceData();
  }

  Future<void> _loadDeviceData() async {
    try {
      final hash = await DeviceHashUtil.getDeviceHash();
      final channel = const MethodChannel(_channelName);
      final info = await channel.invokeMapMethod<String, dynamic>(
        'getDeviceInfo',
      );
      final imei = info?['imei']?.toString() ?? 'N/A';

      if (mounted) {
        setState(() {
          _deviceHash = hash;
          _deviceInfo = 'IMEI: $imei\nHash: $hash';
        });
      }
    } catch (e) {
      AppLogger.log('Error loading device data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Device QR Code',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        backgroundColor: FonexColors.surface,
        elevation: 0,
      ),
      body: AnimatedGradientBg(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GlassCard(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      // Simple QR representation (text-based)
                      Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: FonexColors.cardBorder,
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.qr_code_2_rounded,
                                size: 120,
                                color: Colors.black,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _deviceHash,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black,
                                  letterSpacing: 2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Device ID',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: FonexColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _deviceHash,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: FonexColors.textPrimary,
                          letterSpacing: 4,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: FonexColors.card.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _deviceInfo,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: FonexColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                GlassCard(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        color: FonexColors.accent,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Show this QR code or Device ID to ${_storeName} for device identification and support.',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: FonexColors.textSecondary,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// DEBUG TERMINAL SCREEN - View App Logs
// =============================================================================
class DebugTerminalScreen extends StatefulWidget {
  const DebugTerminalScreen({super.key});

  @override
  State<DebugTerminalScreen> createState() => _DebugTerminalScreenState();
}

class _DebugTerminalScreenState extends State<DebugTerminalScreen> {
  static const _channel = MethodChannel(_channelName);
  Timer? _statsTimer;
  int? _batteryLevel;
  double _memoryMb = 0;
  int _pendingAckCount = 0;
  int _crashCount = 0;

  @override
  void initState() {
    super.initState();
    _crashCount = CrashReporter.crashCountNotifier.value;
    CrashReporter.crashCountNotifier.addListener(_onCrashCountChanged);
    _refreshStats();
    _statsTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _refreshStats();
    });
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    CrashReporter.crashCountNotifier.removeListener(_onCrashCountChanged);
    super.dispose();
  }

  void _onCrashCountChanged() {
    if (!mounted) return;
    setState(() {
      _crashCount = CrashReporter.crashCountNotifier.value;
    });
  }

  Future<void> _refreshStats() async {
    int? battery;
    try {
      battery = await _channel.invokeMethod<int>('getBatteryLevel');
    } catch (_) {
      battery = null;
    }
    final memoryMb = ProcessInfo.currentRss / (1024 * 1024);
    final pendingAcks = RealtimeCommandService().pendingAckQueue.length;
    if (!mounted) return;
    setState(() {
      _batteryLevel = battery;
      _memoryMb = memoryMb;
      _pendingAckCount = pendingAcks;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          'Debug Terminal: Logs',
          style: TextStyle(fontFamily: 'monospace', color: Colors.greenAccent),
        ),
        backgroundColor: Colors.grey[900],
        iconTheme: const IconThemeData(color: Colors.greenAccent),
        actions: [
          IconButton(
            icon: const Icon(Icons.build_circle_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const RecoveryActionsScreen(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              AppLogger.clear();
            },
          ),
          IconButton(
            icon: const Icon(Icons.warning_amber_rounded),
            tooltip: 'Clear captured crashes',
            onPressed: () async {
              await CrashReporter.clearEvents();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            color: Colors.grey.shade900,
            child: Text(
              'mem=${_memoryMb.toStringAsFixed(1)}MB  '
              'battery=${_batteryLevel?.toString() ?? '--'}%  '
              'pendingAck=$_pendingAckCount  crashes=$_crashCount',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: Colors.amberAccent,
              ),
            ),
          ),
          Expanded(
            child: ValueListenableBuilder<int>(
              valueListenable: AppLogger.logUpdateNotifier,
              builder: (context, _, __) {
                final logs = AppLogger.logs.reversed.toList();
                return ListView.builder(
                  itemCount: logs.length,
                  padding: const EdgeInsets.all(8),
                  itemBuilder: (context, index) {
                    return Text(
                      logs[index],
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: Colors.greenAccent,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
