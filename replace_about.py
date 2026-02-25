import re

with open('lib/main.dart', 'r') as f:
    content = f.read()

new_about_screen = """class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> with TickerProviderStateMixin {
  static const String _facebookProfileUrl = 'https://www.facebook.com/anupam.pradhan.35110/';
  static const String _facebookProfileAssetPath = 'assets/images/facebook_profilephoto/FB_IMG_1743254515357.jpg';
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
                    Text(
                      'Version ${FonexConfig.appVersion}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: FonexColors.textMuted,
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
                      _buildContactRow(Icons.location_on_rounded, _storeAddress, maxLines: 2),
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
              Icon(Icons.auto_awesome_rounded, color: FonexColors.accent, size: 18),
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
                            color: FonexColors.accent.withValues(alpha: _pulseAnim.value),
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
                            errorBuilder: (_, __, ___) => _buildProfilePlaceholder(),
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
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                                      colors: [Color(0xFF5AA3FF), Color(0xFF89F0DA)],
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
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1877F2).withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(0xFF1877F2).withValues(alpha: 0.45),
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
    final fallbackUri = Uri.parse('https://m.facebook.com/anupam.pradhan.35110/');

    try {
      final openedInApp = await launchUrl(externalUri, mode: LaunchMode.inAppBrowserView);
      if (openedInApp) return;
    } catch (_) {}

    try {
      final openedExternal = await launchUrl(externalUri, mode: LaunchMode.externalApplication);
      if (openedExternal) return;
    } catch (_) {}

    try {
      final openedFallback = await launchUrl(fallbackUri, mode: LaunchMode.inAppBrowserView);
      if (openedFallback) return;
    } catch (_) {}

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open Facebook profile right now.')),
      );
    }
  }

  Widget _buildContactRow(IconData icon, String text, {int maxLines = 1}) {
    return Row(
      crossAxisAlignment: maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
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
          style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white),
        ),
      ),
    );
  }
}"""

pattern = re.compile(r'class AboutScreen extends StatelessWidget \{.*?(?=\n// =============================================================================\n// PAYMENT SCHEDULE SCREEN)', re.DOTALL)
new_content = pattern.sub(new_about_screen, content)

with open('lib/main.dart', 'w') as f:
    f.write(new_content)

print(content != new_content)
