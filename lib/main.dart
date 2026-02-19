import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

// =============================================================================
// FONEX Powered by Roy Communication — Device Control System
// =============================================================================
// Production-ready device lock for mobile retail financing.
// Uses Device Owner + DevicePolicyManager + Lock Task (no root, no Accessibility).
// =============================================================================

const String _channelName = 'device.lock/channel';
const int _lockAfterDays = 30;
const int _maxPinAttempts = 3;
const int _cooldownSeconds = 30;
const String _keyLastVerified = 'last_verified';
const String _keyDeviceLocked = 'device_locked';
const String _keyPinSetup = 'pin_setup_done';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const FonexApp());
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
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A237E),
          brightness: Brightness.dark,
        ),
        textTheme: GoogleFonts.interTextTheme(
          ThemeData.dark().textTheme,
        ),
      ),
      home: const DeviceControlHome(),
    );
  }
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
  int _daysRemaining = 30;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkTimerAndLock();
    }
  }

  Future<void> _initialize() async {
    await _checkDeviceOwner();
    await _checkTimerAndLock();
    setState(() => _isLoading = false);
  }

  Future<void> _checkDeviceOwner() async {
    try {
      final isOwner = await _channel.invokeMethod<bool>('isDeviceOwner');
      setState(() => _isDeviceOwner = isOwner ?? false);
    } on PlatformException catch (e) {
      debugPrint('Error checking device owner: $e');
      setState(() => _isDeviceOwner = false);
    }
  }

  Future<void> _checkTimerAndLock() async {
    final prefs = await SharedPreferences.getInstance();
    final lastVerifiedMs = prefs.getInt(_keyLastVerified);

    if (lastVerifiedMs == null) {
      // First run — set initial timestamp
      await prefs.setInt(
        _keyLastVerified,
        DateTime.now().millisecondsSinceEpoch,
      );
      await prefs.setBool(_keyDeviceLocked, false);
      setState(() {
        _isDeviceLocked = false;
        _daysRemaining = _lockAfterDays;
      });
      return;
    }

    final lastVerified =
        DateTime.fromMillisecondsSinceEpoch(lastVerifiedMs);
    final daysSince = DateTime.now().difference(lastVerified).inDays;
    final remaining = _lockAfterDays - daysSince;

    if (daysSince >= _lockAfterDays) {
      // Lock the device
      await _engageDeviceLock();
      setState(() {
        _isDeviceLocked = true;
        _daysRemaining = 0;
      });
    } else {
      // Check if was previously locked but shouldn't be
      final wasLocked = prefs.getBool(_keyDeviceLocked) ?? false;
      if (wasLocked) {
        await _engageDeviceLock();
        setState(() {
          _isDeviceLocked = true;
          _daysRemaining = 0;
        });
      } else {
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

  Future<void> _disengageDeviceLock() async {
    try {
      await _channel.invokeMethod('stopDeviceLock');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyDeviceLocked, false);
      await prefs.setInt(
        _keyLastVerified,
        DateTime.now().millisecondsSinceEpoch,
      );
      setState(() {
        _isDeviceLocked = false;
        _daysRemaining = _lockAfterDays;
      });
    } on PlatformException catch (e) {
      debugPrint('Error disengaging device lock: $e');
    }
  }

  // ---- DEV ESCAPE: simulate 30-day expiry for testing ----
  Future<void> _devSimulateExpiry() async {
    final prefs = await SharedPreferences.getInstance();
    final expired = DateTime.now()
        .subtract(const Duration(days: 31))
        .millisecondsSinceEpoch;
    await prefs.setInt(_keyLastVerified, expired);
    await _checkTimerAndLock();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const _SplashScreen();
    }

    if (_isDeviceLocked) {
      return LockScreen(
        onUnlocked: _disengageDeviceLock,
      );
    }

    return NormalModeScreen(
      isDeviceOwner: _isDeviceOwner,
      daysRemaining: _daysRemaining,
      onSimulateExpiry: _devSimulateExpiry,
    );
  }
}

// =============================================================================
// SPLASH SCREEN
// =============================================================================
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _fonexLogo(size: 80),
            const SizedBox(height: 24),
            Text(
              'FONEX',
              style: GoogleFonts.inter(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Powered by Roy Communication',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Colors.white54,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 40),
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Color(0xFF4FC3F7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// LOCK SCREEN — Shown when device is locked
// =============================================================================
class LockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;

  const LockScreen({super.key, required this.onUnlocked});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  int _unlockTapCount = 0;
  Timer? _tapResetTimer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    // Ensure immersive mode
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _tapResetTimer?.cancel();
    super.dispose();
  }

  void _handleSecretTap() {
    _unlockTapCount++;
    _tapResetTimer?.cancel();
    _tapResetTimer = Timer(const Duration(seconds: 3), () {
      _unlockTapCount = 0;
    });

    if (_unlockTapCount >= 5) {
      _unlockTapCount = 0;
      _showPinDialog();
    }
  }

  void _showPinDialog() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OwnerPinScreen(onUnlocked: widget.onUnlocked),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0D1117),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Animated lock icon
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _pulseAnimation.value,
                        child: child,
                      );
                    },
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            const Color(0xFFE53935).withValues(alpha: 0.8),
                            const Color(0xFFFF7043).withValues(alpha: 0.6),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFFE53935).withValues(alpha: 0.3),
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.lock_rounded,
                        size: 56,
                        color: Colors.white,
                      ),
                    ),
                  ),

                  const SizedBox(height: 48),

                  // FONEX Header
                  _fonexLogo(size: 48),
                  const SizedBox(height: 16),
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Color(0xFF4FC3F7), Color(0xFF7C4DFF)],
                    ).createShader(bounds),
                    child: Text(
                      'FONEX',
                      style: GoogleFonts.inter(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Powered by Roy Communication',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Colors.white60,
                      letterSpacing: 1.5,
                    ),
                  ),

                  const SizedBox(height: 48),

                  // Lock message
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: const Color(0xFF1A1F2E),
                      border: Border.all(
                        color: const Color(0xFFE53935).withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: Color(0xFFFFB74D),
                          size: 28,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Device Temporarily Locked',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Your payment verification period has expired.\nPlease contact your mobile shop to continue using this device.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: Colors.white60,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Contact info
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: const Color(0xFF1E293B),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.store_rounded,
                            color: Color(0xFF4FC3F7), size: 20),
                        const SizedBox(width: 12),
                        Text(
                          'Visit Roy Communication',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF4FC3F7),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 48),

                  // Hidden unlock trigger — tap 5x on this area
                  GestureDetector(
                    onTap: _handleSecretTap,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'FONEX v1.0.0',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: Colors.white24,
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
    );
  }
}

// =============================================================================
// OWNER PIN SCREEN — Secure authentication for store owner
// =============================================================================
class OwnerPinScreen extends StatefulWidget {
  final VoidCallback onUnlocked;

  const OwnerPinScreen({super.key, required this.onUnlocked});

  @override
  State<OwnerPinScreen> createState() => _OwnerPinScreenState();
}

class _OwnerPinScreenState extends State<OwnerPinScreen> {
  static const _channel = MethodChannel(_channelName);

  final _pinController = TextEditingController();
  int _failedAttempts = 0;
  bool _isCooldown = false;
  int _cooldownRemaining = 0;
  Timer? _cooldownTimer;
  String? _errorMessage;
  bool _isValidating = false;
  bool _obscurePin = true;

  @override
  void dispose() {
    _pinController.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    setState(() {
      _isCooldown = true;
      _cooldownRemaining = _cooldownSeconds;
      _errorMessage =
          'Too many failed attempts. Please wait $_cooldownRemaining seconds.';
    });

    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
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
      final isValid = await _channel.invokeMethod<bool>(
        'validatePin',
        {'pin': pin},
      );

      if (isValid == true) {
        // Unlock successful
        if (mounted) {
          Navigator.of(context).pop();
        }
        widget.onUnlocked();
      } else {
        _failedAttempts++;
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
      if (mounted) {
        setState(() => _isValidating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: const Color(0xFF0D1117),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded,
                color: Colors.white54),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1565C0), Color(0xFF7C4DFF)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color:
                              const Color(0xFF1565C0).withValues(alpha: 0.4),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.admin_panel_settings_rounded,
                      size: 40,
                      color: Colors.white,
                    ),
                  ),

                  const SizedBox(height: 24),

                  Text(
                    'Store Owner Access',
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter your secure PIN to unlock this device',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: Colors.white54,
                    ),
                  ),

                  const SizedBox(height: 40),

                  // PIN Input
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: const Color(0xFF1A1F2E),
                      border: Border.all(
                        color: _errorMessage != null
                            ? const Color(0xFFE53935).withValues(alpha: 0.6)
                            : const Color(0xFF2A3142),
                      ),
                    ),
                    child: TextField(
                      controller: _pinController,
                      keyboardType: TextInputType.number,
                      obscureText: _obscurePin,
                      enabled: !_isCooldown,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 8,
                      ),
                      decoration: InputDecoration(
                        hintText: '• • • •',
                        hintStyle: GoogleFonts.inter(
                          fontSize: 24,
                          color: Colors.white24,
                          letterSpacing: 8,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePin
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            color: Colors.white38,
                          ),
                          onPressed: () {
                            setState(() => _obscurePin = !_obscurePin);
                          },
                        ),
                      ),
                      onSubmitted: (_) => _validatePin(),
                    ),
                  ),

                  // Error message
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: const Color(0xFFE53935).withValues(alpha: 0.15),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              color: Color(0xFFEF5350), size: 16),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _errorMessage!,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: const Color(0xFFEF5350),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Unlock button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed:
                          (_isCooldown || _isValidating) ? null : _validatePin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isCooldown
                            ? const Color(0xFF2A3142)
                            : const Color(0xFF1565C0),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: _isValidating
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _isCooldown ? 'LOCKED' : 'UNLOCK DEVICE',
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.5,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Security notice
                  Text(
                    'Default PIN: 1234',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: Colors.white24,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// NORMAL MODE SCREEN — Shown when device is NOT locked
// =============================================================================
class NormalModeScreen extends StatelessWidget {
  final bool isDeviceOwner;
  final int daysRemaining;
  final VoidCallback onSimulateExpiry;

  const NormalModeScreen({
    super.key,
    required this.isDeviceOwner,
    required this.daysRemaining,
    required this.onSimulateExpiry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),

              // Header
              Row(
                children: [
                  _fonexLogo(size: 36),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'FONEX',
                        style: GoogleFonts.inter(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 3,
                        ),
                      ),
                      Text(
                        'Powered by Roy Communication',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // Status card
              _buildStatusCard(),

              const SizedBox(height: 16),

              // Device Owner status
              _buildInfoCard(
                icon: isDeviceOwner
                    ? Icons.verified_rounded
                    : Icons.warning_rounded,
                iconColor: isDeviceOwner
                    ? const Color(0xFF66BB6A)
                    : const Color(0xFFFFB74D),
                title: isDeviceOwner
                    ? 'Device Owner Active'
                    : 'Device Owner Not Set',
                subtitle: isDeviceOwner
                    ? 'This device is protected by FONEX'
                    : 'Set via ADB to enable device protection',
              ),

              const SizedBox(height: 16),

              // Days remaining
              _buildInfoCard(
                icon: Icons.schedule_rounded,
                iconColor: daysRemaining <= 7
                    ? const Color(0xFFEF5350)
                    : const Color(0xFF4FC3F7),
                title: '$daysRemaining days remaining',
                subtitle: 'Until next verification required',
              ),

              const Spacer(),

              // Dev tools (for development/testing only)
              Center(
                child: GestureDetector(
                  onLongPress: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: const Color(0xFF1A1F2E),
                        title: Text(
                          'Developer Tools',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        content: Text(
                          'Simulate 30-day expiry? This will lock the device.',
                          style: GoogleFonts.inter(color: Colors.white70),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text('Cancel',
                                style:
                                    GoogleFonts.inter(color: Colors.white54)),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              onSimulateExpiry();
                            },
                            child: Text('Simulate',
                                style: GoogleFonts.inter(
                                    color: const Color(0xFFEF5350))),
                          ),
                        ],
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'FONEX v1.0.0 • Device Control System',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: Colors.white24,
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

  Widget _buildStatusCard() {
    final isHealthy = isDeviceOwner && daysRemaining > 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isHealthy
              ? [
                  const Color(0xFF1B5E20).withValues(alpha: 0.5),
                  const Color(0xFF0D1117),
                ]
              : [
                  const Color(0xFFB71C1C).withValues(alpha: 0.4),
                  const Color(0xFF0D1117),
                ],
        ),
        border: Border.all(
          color: isHealthy
              ? const Color(0xFF66BB6A).withValues(alpha: 0.3)
              : const Color(0xFFE53935).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isHealthy
                  ? const Color(0xFF66BB6A).withValues(alpha: 0.2)
                  : const Color(0xFFE53935).withValues(alpha: 0.2),
            ),
            child: Icon(
              isHealthy
                  ? Icons.shield_rounded
                  : Icons.gpp_bad_rounded,
              color: isHealthy
                  ? const Color(0xFF66BB6A)
                  : const Color(0xFFE53935),
              size: 28,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isHealthy ? 'Device Protected' : 'Action Required',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isHealthy
                      ? 'All systems operational'
                      : 'Device protection not fully configured',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.white60,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: const Color(0xFF1A1F2E),
        border: Border.all(color: const Color(0xFF2A3142)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: iconColor.withValues(alpha: 0.15),
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.white54,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// FONEX LOGO WIDGET
// =============================================================================
Widget _fonexLogo({double size = 48}) {
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF1565C0),
          Color(0xFF7C4DFF),
        ],
      ),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF1565C0).withValues(alpha: 0.4),
          blurRadius: 12,
          spreadRadius: 1,
        ),
      ],
    ),
    child: Center(
      child: Text(
        'F',
        style: GoogleFonts.inter(
          fontSize: size * 0.5,
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
      ),
    ),
  );
}
