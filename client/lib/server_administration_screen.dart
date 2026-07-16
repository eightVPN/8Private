import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'theme.dart';

class ServerAdministrationScreen extends StatefulWidget {
  final Function(String) onNavigate;

  const ServerAdministrationScreen({super.key, required this.onNavigate});

  @override
  State<ServerAdministrationScreen> createState() =>
      _ServerAdministrationScreenState();
}

class _ServerAdministrationScreenState extends State<ServerAdministrationScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  // Hardcoded users for UI demo
  final List<Map<String, String>> _users = [
    {'name': 'alpha_protocol_01', 'status': 'Active Connection • 45ms'},
    {'name': 'spectre_node_usr', 'status': 'Disconnected • 2h ago'},
    {'name': 'cyber_junkie_77', 'status': 'Active Connection • 12ms'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTopAppBar(),
                _buildHeader(),
                _buildUserManagement(),
                _buildAdminManagement(),
                _buildServerControls(),
                _buildBackupCard(),
                _buildDecorativeOrb(),
                const SizedBox(height: 100),
              ],
            ),
          ),
          Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomNav()),
        ],
      ),
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
                  const Icon(
                    Icons.security,
                    color: AppColors.primary,
                    size: 28,
                  ),
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
                  border: Border.all(color: Color.fromRGBO(210, 188, 255, 0.3)),
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

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Admin Console',
                style: GoogleFonts.hankenGrotesk(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(width: 12),
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _pulseAnimation.value,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.tertiary,
                        boxShadow: [
                          BoxShadow(
                            color: Color.fromRGBO(76, 215, 246, 0.6),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style: GoogleFonts.inter(
                fontSize: 16,
                color: AppColors.onSurfaceVariant,
              ),
              children: [
                const TextSpan(text: 'Server ID: '),
                TextSpan(
                  text: 'US-WEST-NODE-081',
                  style: GoogleFonts.jetBrainsMono(
                    color: AppColors.primary,
                    fontSize: 14,
                  ),
                ),
                const TextSpan(text: ' | Active since Jan 24, 2024'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserManagement() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: GlassPanel(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.group, color: AppColors.primary, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'User Management',
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer,
                    borderRadius: BorderRadius.circular(100),
                    boxShadow: [
                      BoxShadow(
                        color: Color.fromRGBO(122, 34, 255, 0.5),
                        blurRadius: 15,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.person_add,
                        size: 16,
                        color: AppColors.onPrimaryContainer,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Provision\nNew User',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppColors.onPrimaryContainer,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ..._users.map(
              (user) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Color.fromRGBO(55, 51, 64, 0.3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Color.fromRGBO(255, 255, 255, 0.05),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color.fromRGBO(210, 188, 255, 0.1),
                          border: Border.all(
                            color: Color.fromRGBO(210, 188, 255, 0.2),
                          ),
                        ),
                        child: const Icon(
                          Icons.person,
                          color: AppColors.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user['name']!,
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.onSurface,
                              ),
                            ),
                            Text(
                              user['status']!,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _iconBtn(Icons.qr_code_2, AppColors.onSurfaceVariant),
                      _iconBtn(Icons.content_copy, AppColors.onSurfaceVariant),
                      _iconBtn(
                        Icons.delete_forever,
                        Color.fromRGBO(105, 0, 5, 1.0),
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

  Widget _iconBtn(IconData icon, Color color) {
    return InkWell(
      onTap: () {},
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: 20, color: color),
      ),
    );
  }

  Widget _buildAdminManagement() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: GlassPanel(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.admin_panel_settings,
                  color: AppColors.tertiary,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  'Admin Management',
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Color.fromRGBO(76, 215, 246, 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Generate Master Admin Key',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Security Protocol: This key is restricted to one device only. Regenerating will revoke previous admin access.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () {},
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.tertiary),
                      foregroundColor: AppColors.tertiary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 12,
                      ),
                    ),
                    child: Text(
                      'Create Admin Key',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: GlassPanel(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.settings_suggest,
                  color: AppColors.onSurfaceVariant,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  'Server Controls',
                  style: GoogleFonts.hankenGrotesk(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildControlButton(
              Icons.restart_alt,
              'Remote Reboot',
              'Full system cycle',
              Color(0xFFFFC107),
              false,
            ),
            const SizedBox(height: 8),
            _buildControlButton(
              Icons.delete_sweep,
              'Remote Data Wipe',
              'Irreversible operation',
              AppColors.error,
              true,
            ),
            const SizedBox(height: 8),
            _buildControlButton(
              Icons.link_off,
              'Remove from Client',
              'Revoke all local access',
              AppColors.onSurfaceVariant,
              false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton(
    IconData icon,
    String title,
    String subtitle,
    Color iconColor,
    bool isDestructive,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDestructive
              ? Color.fromRGBO(147, 0, 10, 0.2)
              : Color.fromRGBO(255, 255, 255, 0.1),
        ),
        color: isDestructive
            ? Color.fromRGBO(147, 0, 10, 0.1)
            : Colors.transparent,
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color.fromRGBO(
                (iconColor.r * 255).round(),
                (iconColor.g * 255).round(),
                (iconColor.b * 255).round(),
                0.1,
              ),
              border: Border.all(
                color: Color.fromRGBO(
                  (iconColor.r * 255).round(),
                  (iconColor.g * 255).round(),
                  (iconColor.b * 255).round(),
                  0.3,
                ),
              ),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDestructive ? AppColors.error : AppColors.onSurface,
                ),
              ),
              Text(
                subtitle,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDestructive
                      ? AppColors.onErrorContainer
                      : AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBackupCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: GlassPanel(
        padding: const EdgeInsets.all(24),
        child: Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.backup, color: AppColors.primary, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    'Backup',
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Last backup: 14 mins ago (Encrypted)',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Color.fromRGBO(122, 34, 255, 0.5),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    'Create Connection Backup',
                    style: GoogleFonts.hankenGrotesk(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
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

  Widget _buildDecorativeOrb() {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Center(
        child: AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _pulseAnimation.value,
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Color.fromRGBO(210, 188, 255, 0.2),
                    width: 4,
                  ),
                ),
                child: Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                        colors: [AppColors.primary, AppColors.tertiary],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Color.fromRGBO(122, 34, 255, 0.6),
                          blurRadius: 30,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
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
                'ServerAdministrationScreen' == 'MainConnectionScreen',
              ),
              _navIcon(
                Icons.language,
                'split',
                'ServerAdministrationScreen' == 'SplitTunnelingScreen',
              ),
              _navIcon(
                Icons.settings,
                'setup',
                'ServerAdministrationScreen' == 'SSHSetupScreen',
              ),
              _navIcon(
                Icons.admin_panel_settings,
                'admin',
                'ServerAdministrationScreen' == 'ServerAdministrationScreen',
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

Widget _navIcon(IconData icon, {VoidCallback? onTap}) {
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(24),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Icon(icon, color: AppColors.outline, size: 24),
    ),
  );
}
