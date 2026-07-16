import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:internet_speed_test/internet_speed_test.dart';
import 'package:internet_speed_test/callbacks_enum.dart';
import 'theme.dart';
import 'vpn_provider.dart';

class MainConnectionScreen extends StatefulWidget {
  final Function(String) onNavigate;

  const MainConnectionScreen({super.key, required this.onNavigate});

  @override
  State<MainConnectionScreen> createState() => _MainConnectionScreenState();
}

class _MainConnectionScreenState extends State<MainConnectionScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _pingController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _pingScaleAnimation;
  late Animation<double> _pingOpacityAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.02).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _pingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    _pingScaleAnimation = Tween<double>(
      begin: 0.95,
      end: 1.15,
    ).animate(CurvedAnimation(parent: _pingController, curve: Curves.easeOut));
    _pingOpacityAnimation = Tween<double>(
      begin: 0.4,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _pingController, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _pingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<VPNProvider>();
    if (provider.servers.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.surface,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.dns, size: 64, color: AppColors.outline),
              SizedBox(height: 24),
              Text(
                'No Server Configured',
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                ),
              ),
              SizedBox(height: 12),
              Text(
                'Please add a node to continue.',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () => widget.onNavigate('setup'),
                icon: Icon(Icons.add),
                label: Text('Deploy / Add Server'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryContainer,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _buildBottomNav(),
      );
    }

    return Consumer<VPNProvider>(
      builder: (context, provider, _) {
        final isConnected = provider.state == VPNState.connected;
        final isConnecting = provider.state == VPNState.connecting;

        return Scaffold(
          backgroundColor: AppColors.surface,
          body: Stack(
            children: [
              // Atmospheric background blurs
              Positioned.fill(
                child: IgnorePointer(
                  child: Stack(
                    children: [
                      Center(
                        child: Container(
                          width: 800,
                          height: 800,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color.fromRGBO(
                              122,
                              34,
                              255,
                              isConnected ? 0.1 : 0.03,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 100,
                        right: -50,
                        child: Container(
                          width: 400,
                          height: 400,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color.fromRGBO(
                              76,
                              215,
                              246,
                              isConnected ? 0.05 : 0.02,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Main scrollable content
              SingleChildScrollView(
                child: Column(
                  children: [
                    _buildTopAppBar(),
                    _buildStatusSection(provider, isConnected, isConnecting),
                    _buildOrb(provider, isConnected, isConnecting),
                    const SizedBox(height: 24),
                    _buildServerChip(provider),
                    const SizedBox(height: 40),
                    _buildStatsSection(provider, isConnected),
                    const SizedBox(height: 100),
                  ],
                ),
              ),

              // Bottom Navigation Bar
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildBottomNav(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopAppBar() {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 12,
            left: 24,
            right: 24,
            bottom: 12,
          ),
          decoration: BoxDecoration(
            color: Color.fromRGBO(21, 18, 29, 0.7),
            border: Border(
              bottom: BorderSide(color: Color.fromRGBO(255, 255, 255, 0.1)),
            ),
            boxShadow: [
              BoxShadow(
                color: Color.fromRGBO(122, 34, 255, 0.2),
                blurRadius: 20,
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.security, color: AppColors.primary, size: 28),
                  const SizedBox(width: 8),
                  Text(
                    'VPN 8',
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                      letterSpacing: -1.5,
                    ),
                  ),
                ],
              ),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surfaceContainer,
                  border: Border.all(color: Color.fromRGBO(255, 255, 255, 0.2)),
                ),
                child: const Icon(
                  Icons.person,
                  color: AppColors.onSurfaceVariant,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusSection(
    VPNProvider provider,
    bool isConnected,
    bool isConnecting,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Column(
        children: [
          // Status indicator
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isConnected ? Icons.verified_user : Icons.shield_outlined,
                size: 18,
                color: isConnected ? AppColors.tertiary : AppColors.outline,
              ),
              const SizedBox(width: 4),
              Text(
                isConnected ? 'SECURE PROTOCOL ACTIVE' : 'VPN DISCONNECTED',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isConnected ? AppColors.tertiary : AppColors.outline,
                  letterSpacing: 2.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Connection status title
          Text(
            isConnecting
                ? 'Connecting...'
                : (isConnected ? 'Connected' : 'Not Protected'),
            style: GoogleFonts.hankenGrotesk(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: isConnected ? AppColors.onSurface : AppColors.outline,
            ),
          ),
          const SizedBox(height: 4),
          // Session duration label
          Text(
            'Session duration',
            style: GoogleFonts.inter(
              fontSize: 16,
              color: Color.fromRGBO(204, 194, 217, 0.6),
            ),
          ),
          const SizedBox(height: 4),
          // Timer
          Text(
            isConnected ? provider.sessionDurationString : '00:00:00',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: isConnected
                  ? AppColors.primary
                  : Color.fromRGBO(150, 141, 162, 0.4),
              letterSpacing: 4.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrb(VPNProvider provider, bool isConnected, bool isConnecting) {
    return GestureDetector(
      onTap: () => provider.toggleConnection(),
      child: Padding(
        padding: const EdgeInsets.only(top: 24),
        child: SizedBox(
          width: 260,
          height: 260,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Ping ring (only when connected)
              if (isConnected)
                AnimatedBuilder(
                  animation: _pingController,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _pingOpacityAnimation.value,
                      child: Transform.scale(
                        scale: _pingScaleAnimation.value,
                        child: Container(
                          width: 260,
                          height: 260,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Color.fromRGBO(210, 188, 255, 0.2),
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),

              // Second ring
              Container(
                width: 244,
                height: 244,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Color.fromRGBO(
                      210,
                      188,
                      255,
                      isConnected ? 0.3 : 0.1,
                    ),
                    width: 1,
                  ),
                ),
              ),

              // Inner gradient orb
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: isConnected ? _pulseAnimation.value : 1.0,
                    child: Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: isConnected
                            ? const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  AppColors.primaryContainer,
                                  AppColors.onPrimaryFixedVariant,
                                ],
                              )
                            : null,
                        border: isConnected
                            ? null
                            : Border.all(
                                color: Color.fromRGBO(150, 141, 162, 0.3),
                                width: 2,
                              ),
                        boxShadow: isConnected
                            ? [
                                BoxShadow(
                                  color: Color.fromRGBO(122, 34, 255, 0.6),
                                  blurRadius: 25,
                                ),
                              ]
                            : null,
                      ),
                      padding: const EdgeInsets.all(2),
                      child: ClipOval(
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color.fromRGBO(16, 12, 24, 0.85),
                            ),
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isConnecting)
                                    SizedBox(
                                      width: 64,
                                      height: 64,
                                      child: CircularProgressIndicator(
                                        color: AppColors.primary,
                                        strokeWidth: 3,
                                      ),
                                    )
                                  else
                                    Icon(
                                      Icons.power_settings_new,
                                      size: 64,
                                      color: isConnected
                                          ? AppColors.primary
                                          : AppColors.outline,
                                    ),
                                  const SizedBox(height: 12),
                                  Text(
                                    isConnecting
                                        ? 'CONNECTING'
                                        : (isConnected
                                              ? 'DISCONNECT'
                                              : 'CONNECT'),
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: isConnected
                                          ? AppColors.primary
                                          : AppColors.outline,
                                      letterSpacing: 3.0,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildServerChip(VPNProvider provider) {
    final server = provider.selectedServer;
    return GlassPanel(
      borderRadius: 100,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Flag placeholder
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.surfaceContainerHigh,
              border: Border.all(color: Color.fromRGBO(255, 255, 255, 0.1)),
            ),
            child: const Icon(
              Icons.flag,
              size: 16,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                server?.name ?? 'Select Server',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.tertiary,
                      boxShadow: [
                        BoxShadow(
                          color: Color.fromRGBO(76, 215, 246, 0.4),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'LATENCY: ${provider.latency}ms',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.tertiary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(width: 16),
          const Icon(Icons.expand_more, color: AppColors.outline, size: 20),
        ],
      ),
    );
  }

  bool _isSpeedTesting = false;
  double _testDownloadSpeed = 0.0;
  double _testUploadSpeed = 0.0;
  final _internetSpeedTest = InternetSpeedTest();

  void _startSpeedTest() {
    setState(() {
      _isSpeedTesting = true;
      _testDownloadSpeed = 0.0;
      _testUploadSpeed = 0.0;
    });

    _internetSpeedTest.startDownloadTesting(
      onDone: (double transferRate, SpeedUnit unit) {
        setState(() {
          _testDownloadSpeed = transferRate;
        });
        // Start upload testing after download finishes
        _internetSpeedTest.startUploadTesting(
          onDone: (double transferRate, SpeedUnit unit) {
            setState(() {
              _testUploadSpeed = transferRate;
              _isSpeedTesting = false;
            });
          },
          onProgress: (double percent, double transferRate, SpeedUnit unit) {
            setState(() {
              _testUploadSpeed = transferRate;
            });
          },
          onError: (String errorMessage, String speedTestError) {
            setState(() => _isSpeedTesting = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Upload test failed: $errorMessage')),
            );
          },
        );
      },
      onProgress: (double percent, double transferRate, SpeedUnit unit) {
        setState(() {
          _testDownloadSpeed = transferRate;
        });
      },
      onError: (String errorMessage, String speedTestError) {
        setState(() => _isSpeedTesting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download test failed: $errorMessage')),
        );
      },
    );
  }

  Widget _buildStatsSection(VPNProvider provider, bool isConnected) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          // Speed Test Button
          if (isConnected && !_isSpeedTesting)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: ElevatedButton.icon(
                onPressed: _startSpeedTest,
                icon: const Icon(Icons.speed),
                label: const Text('Run Speed Test'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryContainer,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          if (_isSpeedTesting)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            ),
          // Download card
          _buildSpeedCard(
            label: 'DOWNLOAD',
            value: isConnected
                ? (_isSpeedTesting || _testDownloadSpeed > 0 ? _testDownloadSpeed.toStringAsFixed(1) : provider.downloadSpeed.toStringAsFixed(1))
                : '0.0',
            icon: Icons.arrow_downward,
            color: AppColors.tertiary,
            gradientId: 'cyan',
          ),
          const SizedBox(height: 16),
          // Upload card
          _buildSpeedCard(
            label: 'UPLOAD',
            value: isConnected
                ? (_isSpeedTesting || _testUploadSpeed > 0 ? _testUploadSpeed.toStringAsFixed(1) : provider.uploadSpeed.toStringAsFixed(1))
                : '0.0',
            icon: Icons.arrow_upward,
            color: AppColors.primary,
            gradientId: 'violet',
          ),
          const SizedBox(height: 16),
          // Encryption card
          _buildEncryptionCard(),
        ],
      ),
    );
  }

  Widget _buildSpeedCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required String gradientId,
  }) {
    return GlassPanel(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurfaceVariant,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        value,
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Mbps',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          color: Color.fromRGBO(
                            (color.r * 255).round(),
                            (color.g * 255).round(),
                            (color.b * 255).round(),
                            0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Icon(icon, color: color, size: 24),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 64,
            child: CustomPaint(
              size: Size.infinite,
              painter: _WaveGraphPainter(color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEncryptionCard() {
    return GlassPanel(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Color.fromRGBO(0, 109, 128, 0.3),
                ),
                child: const Icon(
                  Icons.verified_user,
                  color: AppColors.tertiary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ENCRYPTION',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurfaceVariant,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'AES-256-GCM',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: Color.fromRGBO(255, 255, 255, 0.05)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'KILL SWITCH',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.outline,
                  letterSpacing: 0.6,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Color.fromRGBO(76, 215, 246, 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'ACTIVE',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.tertiary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: 80,
          decoration: BoxDecoration(
            color: Color.fromRGBO(33, 30, 42, 0.7),
            border: Border(
              top: BorderSide(color: Color.fromRGBO(255, 255, 255, 0.2)),
            ),
            boxShadow: [
              BoxShadow(
                color: Color.fromRGBO(0, 0, 0, 0.5),
                offset: Offset(0, -4),
                blurRadius: 20,
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navIcon(
                Icons.bolt,
                'home',
                'MainConnectionScreen' == 'MainConnectionScreen',
              ),
              _navIcon(
                Icons.language,
                'split',
                'MainConnectionScreen' == 'SplitTunnelingScreen',
              ),
              _navIcon(
                Icons.settings,
                'setup',
                'MainConnectionScreen' == 'SSHSetupScreen',
              ),
              _navIcon(
                Icons.admin_panel_settings,
                'admin',
                'MainConnectionScreen' == 'ServerAdministrationScreen',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navIcon(IconData icon, String screenName, bool isActive) {
    return GestureDetector(
      onTap: () => widget.onNavigate(screenName),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: isActive
            ? Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primaryContainer,
                  boxShadow: [
                    BoxShadow(
                      color: Color.fromRGBO(122, 34, 255, 0.5),
                      blurRadius: 15,
                    ),
                  ],
                ),
                child: Icon(
                  icon,
                  color: AppColors.onPrimaryContainer,
                  size: 24,
                ),
              )
            : Icon(icon, color: AppColors.outline, size: 24),
      ),
    );
  }
}

class _WaveGraphPainter extends CustomPainter {
  final Color color;

  _WaveGraphPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final path = Path();
    final w = size.width;
    final h = size.height;

    path.moveTo(0, h * 0.7);
    path.cubicTo(w * 0.1, h * 0.2, w * 0.2, h * 0.8, w * 0.3, h * 0.4);
    path.cubicTo(w * 0.4, h * 0.1, w * 0.5, h * 0.6, w * 0.6, h * 0.3);
    path.cubicTo(w * 0.7, h * 0.0, w * 0.8, h * 0.5, w * 0.9, h * 0.2);
    path.cubicTo(w * 0.95, h * 0.1, w, h * 0.5, w, h * 0.4);

    canvas.drawPath(path, paint);

    // Fill gradient below the wave
    final fillPath = Path.from(path);
    fillPath.lineTo(w, h);
    fillPath.lineTo(0, h);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color.fromRGBO(
            (color.r * 255).round(),
            (color.g * 255).round(),
            (color.b * 255).round(),
            0.15,
          ),
          Color.fromRGBO(
            (color.r * 255).round(),
            (color.g * 255).round(),
            (color.b * 255).round(),
            0.0,
          ),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    canvas.drawPath(fillPath, fillPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
