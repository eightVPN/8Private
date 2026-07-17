import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
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

  void _showServerSelection(BuildContext context, VPNProvider provider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return _ServerSelectionModal(
          provider: provider,
          onNavigate: widget.onNavigate,
        );
      },
    );
  }

  Widget _buildServerChip(VPNProvider provider) {
    final server = provider.selectedServer;
    return GestureDetector(
      onTap: () => _showServerSelection(context, provider),
      child: GlassPanel(
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
      ),
    );
  }


  Widget _buildStatsSection(VPNProvider provider, bool isConnected) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          // Download card
          _buildSpeedCard(
            label: 'DOWNLOAD',
            value: isConnected ? provider.downloadSpeed.toStringAsFixed(1) : '0.0',
            icon: Icons.arrow_downward,
            color: AppColors.tertiary,
            gradientId: 'cyan',
            history: provider.downloadHistory,
            isConnected: isConnected,
          ),
          const SizedBox(height: 16),
          // Upload card
          _buildSpeedCard(
            label: 'UPLOAD',
            value: isConnected ? provider.uploadSpeed.toStringAsFixed(1) : '0.0',
            icon: Icons.arrow_upward,
            color: AppColors.primary,
            gradientId: 'violet',
            history: provider.uploadHistory,
            isConnected: isConnected,
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
    required List<FlSpot> history,
    required bool isConnected,
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
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                minX: history.isNotEmpty ? history.first.x : 0,
                maxX: history.isNotEmpty ? history.last.x : 60,
                minY: 0,
                maxY: (history.isNotEmpty && history.map((s) => s.y).reduce((a, b) => a > b ? a : b) > 10) 
                      ? history.map((s) => s.y).reduce((a, b) => a > b ? a : b) * 1.2 : 10,
                lineBarsData: [
                  LineChartBarData(
                    spots: history,
                    isCurved: true,
                    color: color,
                    barWidth: 2,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: color.withAlpha(50),
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
                    'XChaCha20-Poly1305',
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

class _ServerSelectionModal extends StatelessWidget {
  final VPNProvider provider;
  final Function(String) onNavigate;

  const _ServerSelectionModal({
    required this.provider,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 48,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Select Server',
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: AppColors.outline),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (provider.servers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  const Icon(Icons.dns, size: 48, color: AppColors.outline),
                  const SizedBox(height: 16),
                  Text(
                    'No servers added yet.',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          else
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.4,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: provider.servers.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final server = provider.servers[index];
                    final isSelected = provider.selectedServer?.id == server.id;
                    return GestureDetector(
                      onTap: () {
                        provider.selectServer(server);
                        Navigator.pop(context);
                      },
                      child: GlassPanel(
                        backgroundColor: isSelected
                            ? AppColors.primaryContainer.withOpacity(0.15)
                            : AppColors.surfaceContainerLow,
                        borderColor: isSelected
                            ? AppColors.primary
                            : AppColors.glassBorder,
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSelected
                                    ? AppColors.primaryContainer
                                    : AppColors.surfaceContainerHigh,
                              ),
                              child: Icon(
                                Icons.dns,
                                color: isSelected
                                    ? AppColors.onPrimaryContainer
                                    : AppColors.onSurfaceVariant,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    server.name,
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${server.ip}:${server.port}',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: AppColors.tertiary,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${server.latencyMs}ms',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.tertiary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                GestureDetector(
                                  onTap: () {
                                    provider.removeServer(server.id);
                                  },
                                  child: const Icon(
                                    Icons.delete_outline,
                                    color: AppColors.error,
                                    size: 18,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryContainer,
              foregroundColor: AppColors.onPrimaryContainer,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            onPressed: () {
              Navigator.pop(context);
              onNavigate('setup');
            },
            icon: const Icon(Icons.add),
            label: Text(
              'Add New Server',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: AppColors.error,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: AppColors.surfaceContainer,
                  title: const Text('Reset Application Data?'),
                  content: const Text(
                    'This will disconnect the VPN, delete all saved servers, and reset all credentials to default. Are you sure?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: AppColors.error),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Reset Everything'),
                    ),
                  ],
                ),
              );

              if (confirm == true) {
                Navigator.pop(context);
                await provider.clearAllData();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('All application data cleared.'),
                    backgroundColor: AppColors.surfaceContainerHigh,
                  ),
                );
              }
            },
            icon: const Icon(Icons.restore, size: 18),
            label: Text(
              'Reset App Data',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
