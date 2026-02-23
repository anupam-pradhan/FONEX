import 'dart:async';
import 'dart:math';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'config.dart';
import 'services/device_storage_service.dart';
import 'services/realtime_command_service.dart';
import 'services/sync_service.dart';
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
const String _keyBatteryOptimizationPrompted = 'battery_optimization_prompted';
const String _keyAutoStartPrompted = 'auto_start_prompted';
const String _serverBaseUrl = FonexConfig.serverBaseUrl;
const String _supportPhone1 = FonexConfig.supportPhone1;
const String _supportPhone2 = FonexConfig.supportPhone2;
const String _storeName = FonexConfig.storeName;
const String _storeAddress = FonexConfig.storeAddress;

// =============================================================================
// DEVICE HASH UTILITY — Offline Algorithmic PIN Generation
// =============================================================================
class DeviceHashUtil {
  static const String _keySalt = 'device_hash_salt';

  static Future<String> getDeviceHash() async {
    final prefs = await SharedPreferences.getInstance();
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
    return (hash.abs() % 1000000).toString().padLeft(6, '0');
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
  if (FonexConfig.supabaseUrl.isNotEmpty &&
      FonexConfig.supabaseAnonKey.isNotEmpty) {
    try {
      await Supabase.initialize(
        url: FonexConfig.supabaseUrl,
        anonKey: FonexConfig.supabaseAnonKey,
      );
    } catch (e) {
      debugPrint('Supabase initialization failed: $e');
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
  runApp(const FonexApp());
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
// WALLPAPER WITH STORE NAME AND EMI INFO
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
                    Column(
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
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'EMI Payment System',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: FonexColors.textSecondary,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
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

  bool _isDeviceOwner = false;
  bool _isDeviceLocked = false;
  bool _isLoading = true;
  bool _isPaidInFull = false;
  int _daysRemaining = 30;
  bool _isServerConnected = false;
  String _serverStatusMessage = 'Connecting...';
  DateTime? _lastServerSync;
  bool _isConnecting = false;
  String? _deviceHash;
  String? _realtimeDeviceId;

  Timer? _simCheckTimer;
  Timer? _serverCheckInTimer;

  @override
  void initState() {
    super.initState();
    // Initialize sync service for enterprise-level sync
    WidgetsBinding.instance.addObserver(this);
    SyncService().initialize();
    unawaited(_initialize());
    // Poll SIM state every 60 seconds while app is active (optimized: only when needed)
    _simCheckTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted && !_isPaidInFull) _checkSimState();
    });
    // Lightweight heartbeat every 5 minutes
    _serverCheckInTimer = Timer.periodic(
      Duration(minutes: FonexConfig.serverCheckInIntervalMinutes),
      (_) {
        RealtimeCommandService().ensureConnected();
        if (mounted && !_isConnecting) unawaited(_serverCheckIn());
      },
    );
  }

  @override
  void dispose() {
    _simCheckTimer?.cancel();
    _serverCheckInTimer?.cancel();
    SyncService().dispose();
    unawaited(RealtimeCommandService().dispose());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// SIM-absent logic: lock only after 7 continuous days without a SIM.
  Future<void> _checkSimState() async {
    if (!_isDeviceOwner || _isDeviceLocked || _isPaidInFull) return;
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
          debugPrint('SIM absent detected — grace period started (7 days).');
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
            await _engageDeviceLock();
            if (mounted)
              setState(() {
                _isDeviceLocked = true;
                _daysRemaining = 0;
              });
          }
        }
      } else {
        // SIM present — clear the absent timer
        if (prefs.containsKey(_keySimAbsentSince)) {
          await prefs.remove(_keySimAbsentSince);
          debugPrint('SIM detected — grace period cleared.');
        }
      }
    } on PlatformException catch (e) {
      debugPrint('Error checking SIM state: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Optimize: Only check when app resumes, not on every state change
    if (state == AppLifecycleState.resumed && mounted) {
      // Debounce rapid state changes
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _checkTimerAndLock();
          _checkSimState();
          unawaited(_ensureBackgroundKillProtection(allowUserPrompt: false));
          RealtimeCommandService().onAppResumed();
          RealtimeCommandService().ensureConnected();
          // Immediate server check-in when app resumes for accurate status
          if (!_isConnecting) unawaited(_serverCheckIn());
        }
      });
    } else if (state == AppLifecycleState.paused) {
      // Clean up resources when app goes to background to prevent hanging
      // Timers continue but heavy operations are paused
    }
  }

  Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('is_paid_in_full') == true) {
      if (mounted) setState(() => _isPaidInFull = true);
    }

    await _checkDeviceOwner();
    unawaited(_ensureBackgroundKillProtection(allowUserPrompt: true));
    _deviceHash = await DeviceHashUtil.getDeviceHash();
    _realtimeDeviceId = _deviceHash;
    await _startRealtimeListener();
    if (!_isPaidInFull) {
      await _checkTimerAndLock();
    }
    // Attempt server check-in (non-blocking, offline-safe)
    unawaited(_serverCheckIn());
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _checkDeviceOwner() async {
    try {
      final isOwner = await _channel.invokeMethod<bool>('isDeviceOwner');
      if (mounted) setState(() => _isDeviceOwner = isOwner ?? false);
    } on PlatformException catch (e) {
      debugPrint('Error checking device owner: $e');
      if (mounted) setState(() => _isDeviceOwner = false);
    }
  }

  Future<void> _checkTimerAndLock() async {
    final prefs = await SharedPreferences.getInstance();
    final lastVerifiedMs = prefs.getInt(_keyLastVerified);

    if (lastVerifiedMs == null) {
      // First run — set initial verification timestamp
      await prefs.setInt(
        _keyLastVerified,
        DateTime.now().millisecondsSinceEpoch,
      );
      await prefs.setBool(_keyDeviceLocked, false);
      if (mounted) {
        setState(() {
          _isDeviceLocked = false;
          _daysRemaining = _lockAfterDays;
        });
      }
      return;
    }

    final wasLocked = prefs.getBool(_keyDeviceLocked) ?? false;

    // If explicitly marked locked in prefs, re-engage lock
    if (wasLocked) {
      await _engageDeviceLock();
      if (mounted)
        setState(() {
          _isDeviceLocked = true;
          _daysRemaining = 0;
        });
      return;
    }

    // Not locked — check timer expiry
    final lastVerified = DateTime.fromMillisecondsSinceEpoch(lastVerifiedMs);
    final daysSince = DateTime.now().difference(lastVerified).inDays;
    final remaining = _lockAfterDays - daysSince;

    if (daysSince >= _lockAfterDays) {
      await _engageDeviceLock();
      if (mounted)
        setState(() {
          _isDeviceLocked = true;
          _daysRemaining = 0;
        });
    } else {
      if (mounted) {
        setState(() {
          _isDeviceLocked = false;
          _daysRemaining = remaining.clamp(0, _lockAfterDays);
        });
      }
    }
  }

  Future<void> _engageDeviceLock() async {
    if (!_isDeviceOwner) return;
    try {
      await _channel.invokeMethod('startDeviceLock');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyDeviceLocked, true);
    } on PlatformException catch (e) {
      debugPrint('Error engaging device lock: $e');
    }
  }

  /// FIX: Properly clear locked flag AND reset timer so device doesn't re-lock immediately.
  Future<void> _disengageDeviceLock() async {
    try {
      await _channel.invokeMethod('stopDeviceLock');
      final prefs = await SharedPreferences.getInstance();
      // Clear locked flag
      await prefs.setBool(_keyDeviceLocked, false);
      // Reset the verification timer to NOW — user gets a fresh 30-day window
      await prefs.setInt(
        _keyLastVerified,
        DateTime.now().millisecondsSinceEpoch,
      );
      // Clear SIM absent timer too
      await prefs.remove(_keySimAbsentSince);
      if (mounted) {
        setState(() {
          _isDeviceLocked = false;
          _daysRemaining = _lockAfterDays;
        });
      }
    } on PlatformException catch (e) {
      debugPrint('Error disengaging device lock: $e');
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

  Future<void> lockDeviceLocally() => _engageDeviceLock();

  Future<void> unlockDeviceLocally() => _disengageDeviceLock();

  Future<void> _handleRealtimeCommand(DeviceRealtimeCommand command) async {
    switch (command.command) {
      case 'LOCK':
        if (!_isDeviceLocked) {
          await lockDeviceLocally();
          if (mounted) {
            setState(() {
              _isDeviceLocked = true;
              _daysRemaining = 0;
            });
          }
        }
        break;
      case 'UNLOCK':
        if (_isDeviceLocked) {
          await unlockDeviceLocally();
        }
        break;
      default:
        return;
    }

    sendCommandAck(
      command.commandId,
      command: command.command,
      deviceId: _realtimeDeviceId ?? command.deviceId,
    );

    // Push an immediate health/status sync so dashboard state updates quickly.
    unawaited(_serverCheckIn());
  }

  void sendCommandAck(
    String commandId, {
    required String command,
    String? deviceId,
  }) {
    RealtimeCommandService().sendCommandAck(
      commandId: commandId,
      command: command,
      deviceId: deviceId,
    );
  }

  Future<bool> _hasNetworkConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    return result.any((item) => item != ConnectivityResult.none);
  }

  Future<void> _ensureBackgroundKillProtection({
    required bool allowUserPrompt,
  }) async {
    try {
      await _channel.invokeMethod('startKeepAliveService');
      await _channel.invokeMethod('scheduleKeepAliveWatchdog');

      final isIgnoringBatteryOptimizations =
          await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ??
          true;
      if (isIgnoringBatteryOptimizations || !allowUserPrompt) return;

      final prefs = await SharedPreferences.getInstance();
      final hasPromptedBattery =
          prefs.getBool(_keyBatteryOptimizationPrompted) ?? false;
      if (!hasPromptedBattery) {
        await prefs.setBool(_keyBatteryOptimizationPrompted, true);
        unawaited(_channel.invokeMethod('requestIgnoreBatteryOptimizations'));
      }

      final hasPromptedAutoStart =
          prefs.getBool(_keyAutoStartPrompted) ?? false;
      if (!hasPromptedAutoStart) {
        await prefs.setBool(_keyAutoStartPrompted, true);
        unawaited(_channel.invokeMethod('openAutoStartSettings'));
      }
    } catch (e) {
      debugPrint('Background protection setup skipped: $e');
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
        final serverDeviceId = (response['device_id'] ?? response['id'])
            ?.toString()
            .trim();
        if (serverDeviceId != null &&
            serverDeviceId.isNotEmpty &&
            serverDeviceId != _realtimeDeviceId) {
          _realtimeDeviceId = serverDeviceId;
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

        final rawAction = response['action'] as String? ?? 'none';
        final action = rawAction.toLowerCase();

        debugPrint('Server check-in response: action=$action');

        // Heartbeat must not control lock/unlock. Those are realtime-only.
        switch (action) {
          case 'lock':
          case 'unlock':
            debugPrint(
              'Ignoring $action from heartbeat (realtime handles it).',
            );
            break;
          case 'extend':
          case 'extend_days':
            final days = response['days'] as int? ?? _lockAfterDays;
            final prefs = await SharedPreferences.getInstance();
            await prefs.setInt(
              _keyLastVerified,
              DateTime.now()
                  .subtract(Duration(days: _lockAfterDays - days))
                  .millisecondsSinceEpoch,
            );
            if (mounted) setState(() => _daysRemaining = days);
            debugPrint('Device extended by server: $days days');
            break;
          case 'paid_in_full':
          case 'mark_paid_in_full':
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('is_paid_in_full', true);
            if (mounted) setState(() => _isPaidInFull = true);
            await _disengageDeviceLock();
            try {
              await _channel.invokeMethod('clearDeviceOwner');
              debugPrint(
                'Device marked as paid in full - restrictions removed',
              );
            } on PlatformException catch (e) {
              debugPrint('Error clearing device owner: $e');
            }
            break;
          case 'none':
            debugPrint('No action required from server');
            break;
          default:
            debugPrint('Unknown server action: $action');
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
        debugPrint('Check-in queued for retry (offline or server error)');
      }
    } catch (e, stacktrace) {
      if (mounted) {
        setState(() {
          _isServerConnected = false;
          _serverStatusMessage = 'Connection failed';
        });
      }
      debugPrint('Error during _serverCheckIn: $e\n$stacktrace');
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

  // DEV: simulate 30-day expiry for testing
  Future<void> _devSimulateExpiry() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _keyLastVerified,
      DateTime.now().subtract(const Duration(days: 31)).millisecondsSinceEpoch,
    );
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
              daysRemaining: _daysRemaining,
              onSimulateExpiry: _devSimulateExpiry,
              isServerConnected: _isServerConnected,
              serverStatusMessage: _serverStatusMessage,
              lastServerSync: _lastServerSync,
              onManualConnect: _manualServerConnect,
              isConnecting: _isConnecting,
            ),
    );
  }

  Widget _buildHeroStatus() {
    final isHealthy = _isDeviceOwner && _daysRemaining > 0;
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
                      : 'Device protection needs configuration',
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

  Widget _buildProgressCard() {
    final urgentColor = _daysRemaining <= 7
        ? FonexColors.red
        : _daysRemaining <= 14
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
                  '$_daysRemaining days',
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
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (_daysRemaining / _lockAfterDays).clamp(0.0, 1.0),
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
                'Locks in $_daysRemaining days',
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

  void _showDevTools(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: FonexColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: FonexColors.cardBorder,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Developer Tools',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: FonexColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'For testing and development only',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: FonexColors.textMuted,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _devSimulateExpiry();
                },
                icon: const Icon(Icons.fast_forward_rounded, size: 20),
                label: Text(
                  'Simulate 30-Day Expiry',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: FonexColors.accent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final prefs = await SharedPreferences.getInstance();
                  final now = DateTime.now();
                  await prefs.setInt(
                    _keySimAbsentSince,
                    now
                        .subtract(const Duration(days: 7))
                        .millisecondsSinceEpoch,
                  );
                  await _checkSimState(); // trigger immediate recalculation
                },
                icon: const Icon(Icons.sim_card_alert_rounded, size: 20),
                label: Text(
                  'Simulate SIM Absent Lock',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: FonexColors.surface,
                  foregroundColor: FonexColors.red,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: FonexColors.red.withValues(alpha: 0.3),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// NORMAL MODE SCREEN — Main dashboard when device is unlocked
// =============================================================================
class NormalModeScreen extends StatefulWidget {
  final bool isDeviceOwner;
  final int daysRemaining;
  final VoidCallback onSimulateExpiry;
  final bool isServerConnected;
  final String serverStatusMessage;
  final DateTime? lastServerSync;
  final VoidCallback onManualConnect;
  final bool isConnecting;

  const NormalModeScreen({
    super.key,
    required this.isDeviceOwner,
    required this.daysRemaining,
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
                      : 'Device protection needs configuration',
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
              value: (widget.daysRemaining / _lockAfterDays).clamp(0.0, 1.0),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedGradientBg(
        child: Stack(
          children: [
            const FloatingParticles(count: 20),
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
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
                              builder: (_) => DeviceInfoScreen(),
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
                            MaterialPageRoute(builder: (_) => SettingsScreen()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildHeroStatus(),
                    const SizedBox(height: 16),
                    _buildServerConnectionCard(),
                    const SizedBox(height: 16),
                    _buildProgressCard(),
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
                                builder: (_) => DeviceInfoScreen(),
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
                                ? 'EMI\nActive'
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
                        MaterialPageRoute(builder: (_) => QRCodeScreen()),
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
                                crossAxisAlignment: CrossAxisAlignment.start,
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
    );
  }
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
            const FloatingParticles(count: 15),
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
                        'Powered by Roy Communication',
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
  final VoidCallback onUnlocked;
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
  late AnimationController _pulseController;
  late AnimationController _entryController;
  late Animation<double> _pulse;
  late Animation<double> _fadeIn;
  late Animation<Offset> _slideUp;

  int _unlockTapCount = 0;
  Timer? _tapResetTimer;
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
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _entryController.dispose();
    _tapResetTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDeviceHash() async {
    final hash = await DeviceHashUtil.getDeviceHash();
    if (mounted) setState(() => _deviceHash = hash);
  }

  void _handleSecretTap() {
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
                  'Scan to Pay EMI',
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: AnimatedGradientBg(
          colors: const [
            Color(0xFF06080F),
            Color(0xFF1A0A0A),
            Color(0xFF0A0A1A),
            Color(0xFF06080F),
          ],
          child: Stack(
            children: [
              const FloatingParticles(count: 25),
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
                              'Powered by ${widget.storeName}',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: FonexColors.textSecondary,
                                letterSpacing: 2,
                              ),
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
                            GlassCard(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 16,
                              ),
                              borderRadius: 14,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
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
                                  Column(
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
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Visit store to unlock',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: FonexColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
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
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Device ID  ',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: FonexColors.textSecondary,
                                    ),
                                  ),
                                  Text(
                                    _deviceHash,
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
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.phone_in_talk_rounded,
                                        color: FonexColors.green,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Need Help? Call ${widget.storeName}',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: FonexColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _CallButton(
                                          number: widget.supportPhone1,
                                          label: widget.supportPhone1
                                              .replaceAll('+91', '+91 '),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
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
                                            'Visit ${widget.storeName} store to complete EMI payment and unlock device',
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
                                        'Pay EMI (Show QR)',
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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _call,
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.phone_rounded, color: FonexColors.green, size: 16),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: FonexColors.green,
                ),
                overflow: TextOverflow.ellipsis,
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
              const FloatingParticles(count: 12),
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
                                  children: List.generate(6, (i) {
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
                                  enabled: !_isCooldown,
                                  textAlign: TextAlign.center,
                                  maxLength: 6,
                                  style: GoogleFonts.inter(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w700,
                                    color: FonexColors.textPrimary,
                                    letterSpacing: 12,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: '• • • •',
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
                                'Default PIN: 1234',
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
      debugPrint('Error loading device info: $e');
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
                        children: [
                          const FonexLogo(size: 64),
                          const SizedBox(height: 16),
                          Text(
                            'Device ID',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: FonexColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _deviceHash,
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
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
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
      ),
    );
  }
}

// =============================================================================
// SETTINGS SCREEN — App settings and preferences
// =============================================================================
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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
              _buildSettingsSection('Support', [
                _buildSettingTile(
                  icon: Icons.phone_rounded,
                  title: 'Contact Store',
                  subtitle: _supportPhone1,
                  onTap: () => launchUrl(Uri.parse('tel:$_supportPhone1')),
                ),
                _buildSettingTile(
                  icon: Icons.help_outline_rounded,
                  title: 'Help & Support',
                  subtitle: 'Get help with your device',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AboutScreen()),
                  ),
                ),
              ]),
              const SizedBox(height: 24),
              _buildSettingsSection('System', [
                _buildSettingTile(
                  icon: Icons.refresh_rounded,
                  title: 'Sync with Server',
                  subtitle: 'Manually sync device status',
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Syncing with server...')),
                    );
                  },
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
          trailing: onTap != null
              ? const Icon(
                  Icons.chevron_right_rounded,
                  color: FonexColors.textMuted,
                )
              : null,
          onTap: onTap,
        ),
      ),
    );
  }
}

// =============================================================================
// ABOUT SCREEN — App information and help
// =============================================================================
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  // Facebook profile photo URL
  // Option 1: Get direct image URL - Visit https://www.facebook.com/share/1JNRaFRMqc/
  //          Right-click profile photo > Copy image address, then paste below
  // Option 2: Use Facebook Graph API (requires username):
  //          https://graph.facebook.com/{username}/picture?type=large
  // Option 3: Leave empty to show initials placeholder
  static const String _facebookProfilePhotoUrl = '';

  // Alternative: Try to construct from share link (update if needed)
  // For share link: https://www.facebook.com/share/1JNRaFRMqc/
  // You can also use: https://graph.facebook.com/v18.0/{user-id}/picture?type=large

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
              Text(
                'Version ${FonexConfig.appVersion}',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: FonexColors.textMuted,
                ),
              ),
              const SizedBox(height: 40),
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
                    _buildContactRow(Icons.phone_rounded, _supportPhone1),
                    const SizedBox(height: 12),
                    _buildContactRow(Icons.phone_rounded, _supportPhone2),
                  ],
                ),
              ),
              const SizedBox(height: 24),
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
                      'If you need help with your device or have questions about your EMI payment, please contact ${_storeName} using the phone numbers above.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: FonexColors.textSecondary,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Developer Attribution
              GlassCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Developed by',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: FonexColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final uri = Uri.parse(
                          'https://www.facebook.com/share/1JNRaFRMqc/',
                        );
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: FonexColors.cardBorder,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            // Profile Photo Preview - Facebook style
                            // Loading profile photo from Facebook
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: FonexColors.accent.withValues(
                                    alpha: 0.3,
                                  ),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: FonexColors.accent.withValues(
                                      alpha: 0.2,
                                    ),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child: _facebookProfilePhotoUrl.isNotEmpty
                                    ? Image.network(
                                        _facebookProfilePhotoUrl,
                                        width: 64,
                                        height: 64,
                                        fit: BoxFit.cover,
                                        headers: const {
                                          'User-Agent':
                                              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
                                        },
                                        loadingBuilder: (context, child, loadingProgress) {
                                          if (loadingProgress == null)
                                            return child;
                                          return Container(
                                            width: 64,
                                            height: 64,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: FonexColors.card,
                                            ),
                                            child: Center(
                                              child: SizedBox(
                                                width: 24,
                                                height: 24,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2.5,
                                                  value:
                                                      loadingProgress
                                                              .expectedTotalBytes !=
                                                          null
                                                      ? loadingProgress
                                                                .cumulativeBytesLoaded /
                                                            loadingProgress
                                                                .expectedTotalBytes!
                                                      : null,
                                                  color: FonexColors.accent,
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                        errorBuilder: (_, __, ___) =>
                                            _buildProfilePlaceholder(),
                                      )
                                    : _buildProfilePlaceholder(),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Anupam Pradhan',
                                    style: GoogleFonts.inter(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: FonexColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: FonexColors.accent.withValues(
                                            alpha: 0.15,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.facebook_rounded,
                                              color: FonexColors.accent,
                                              size: 16,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              'View Profile',
                                              style: GoogleFonts.inter(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: FonexColors.accent,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              color: FonexColors.textMuted,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(height: 1, color: FonexColors.cardBorder),
                    const SizedBox(height: 16),
                    Row(
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
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContactRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: FonexColors.accent, size: 20),
        const SizedBox(width: 12),
        Text(
          text,
          style: GoogleFonts.inter(
            fontSize: 14,
            color: FonexColors.textPrimary,
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
// PAYMENT SCHEDULE SCREEN — EMI payment schedule and history
// =============================================================================
class PaymentScheduleScreen extends StatelessWidget {
  final int daysRemaining;

  const PaymentScheduleScreen({super.key, required this.daysRemaining});

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
                    _buildInfoRow('Payment Period', '${_lockAfterDays} days'),
                    const Divider(color: FonexColors.cardBorder),
                    _buildInfoRow(
                      'Status',
                      daysRemaining > 0 ? 'Active' : 'Locked',
                      daysRemaining > 0 ? FonexColors.green : FonexColors.red,
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
                        'Please visit ${_storeName} to make your EMI payment before the due date to avoid device lock.',
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
      debugPrint('Error loading device data: $e');
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
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: FonexColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _deviceHash,
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
