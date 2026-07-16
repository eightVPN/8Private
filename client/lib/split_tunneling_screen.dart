import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'theme.dart';

class SplitTunnelingScreen extends StatefulWidget {
  final Function(String) onNavigate;

  const SplitTunnelingScreen({super.key, required this.onNavigate});

  @override
  State<SplitTunnelingScreen> createState() => _SplitTunnelingScreenState();
}

class _SplitTunnelingScreenState extends State<SplitTunnelingScreen> {
  String _selectedMode = 'vpn';
  final _searchController = TextEditingController();
  final List<bool> _appToggles = [true, true, false, true, false];

  final List<_AppEntry> _apps = [
    _AppEntry('Telegram', 'Messaging & VOIP', Icons.send, Color(0xFF0088CC)),
    _AppEntry('Google Chrome', 'Web Browser', Icons.public, Color(0xFF4285F4)),
    _AppEntry(
      'Gosuslugi',
      'Government Services',
      Icons.account_balance,
      Color(0xFF1A237E),
      badge: 'RECOMMENDED DIRECT',
    ),
    _AppEntry(
      'YouTube',
      'Video Streaming',
      Icons.play_circle_fill,
      Color(0xFFFF0000),
    ),
    _AppEntry('Gmail', 'Communication', Icons.mail_outline, Color(0xFFEA4335)),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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
                _buildHeaderSection(),
                _buildModeSelection(),
                _buildAdvisoryBanner(),
                _buildSearchBar(),
                _buildAppList(),
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
              Row(
                children: [
                  const Icon(
                    Icons.search,
                    color: AppColors.onSurface,
                    size: 24,
                  ),
                  const SizedBox(width: 16),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.surfaceContainer,
                      border: Border.all(
                        color: Color.fromRGBO(255, 255, 255, 0.2),
                      ),
                    ),
                    child: const Icon(
                      Icons.person,
                      color: AppColors.onSurfaceVariant,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Split Tunneling',
            style: GoogleFonts.hankenGrotesk(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Decide which apps should bypass the VPN connection. Useful for local services and high-speed regional access.',
            style: GoogleFonts.inter(
              fontSize: 16,
              color: AppColors.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Column(
        children: [
          _buildModeCard(
            icon: Icons.tune,
            title: 'Route through VPN',
            subtitle: 'Encrypt traffic for all selected apps.',
            mode: 'vpn',
            iconColor: AppColors.primary,
          ),
          const SizedBox(height: 12),
          _buildModeCard(
            icon: Icons.wifi_off,
            title: 'Bypass VPN',
            subtitle: 'Direct connection for all selected apps.',
            mode: 'bypass',
            iconColor: AppColors.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  Widget _buildModeCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String mode,
    required Color iconColor,
  }) {
    final isSelected = _selectedMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _selectedMode = mode),
      child: GlassPanel(
        padding: const EdgeInsets.all(24),
        borderColor: isSelected ? Color.fromRGBO(76, 215, 246, 0.3) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, size: 32, color: iconColor),
                // Radio indicator
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? AppColors.tertiary
                          : AppColors.outline,
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? Center(
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.tertiary,
                            ),
                          ),
                        )
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: GoogleFonts.hankenGrotesk(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdvisoryBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Color.fromRGBO(122, 34, 255, 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Color.fromRGBO(210, 188, 255, 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, color: AppColors.primary, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Government Services Advisory',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryContainer,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Apps like Gosuslugi often require a local IP address and direct connection to function. We recommend adding them to your "Bypass VPN" list.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.onSurfaceVariant,
                      height: 1.4,
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

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: GlassPanel(
        borderRadius: 100,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        child: Row(
          children: [
            const Icon(Icons.search, color: AppColors.outline, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _searchController,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  color: AppColors.onSurface,
                ),
                decoration: InputDecoration(
                  hintText: 'Search applications...',
                  hintStyle: GoogleFonts.inter(
                    fontSize: 16,
                    color: AppColors.outline,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppList() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        children: [
          ...List.generate(_apps.length, (i) {
            final app = _apps[i];
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Color.fromRGBO(255, 255, 255, 0.05),
                  ),
                ),
              ),
              child: Row(
                children: [
                  // App icon
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Color.fromRGBO(
                        (app.color.r * 255).round(),
                        (app.color.g * 255).round(),
                        (app.color.b * 255).round(),
                        0.2,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(app.icon, color: app.color, size: 22),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          app.name,
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              app.category,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                            if (app.badge != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Color.fromRGBO(147, 0, 10, 0.8),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  app.badge!,
                                  style: GoogleFonts.inter(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.error,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: _appToggles[i],
                    onChanged: (v) => setState(() => _appToggles[i] = v),
                    activeThumbColor: AppColors.primaryContainer,
                    activeTrackColor: Color.fromRGBO(122, 34, 255, 0.3),
                    inactiveThumbColor: AppColors.surfaceContainerHigh,
                    inactiveTrackColor: Color.fromRGBO(55, 51, 64, 0.5),
                  ),
                ],
              ),
            );
          }),
          // Add custom application
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: TextButton(
                onPressed: () {},
                child: Text(
                  '+ Add custom application',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
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
                'SplitTunnelingScreen' == 'MainConnectionScreen',
              ),
              _navIcon(
                Icons.language,
                'split',
                'SplitTunnelingScreen' == 'SplitTunnelingScreen',
              ),
              _navIcon(
                Icons.settings,
                'setup',
                'SplitTunnelingScreen' == 'SSHSetupScreen',
              ),
              _navIcon(
                Icons.admin_panel_settings,
                'admin',
                'SplitTunnelingScreen' == 'ServerAdministrationScreen',
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

class _AppEntry {
  final String name;
  final String category;
  final IconData icon;
  final Color color;
  final String? badge;

  const _AppEntry(
    this.name,
    this.category,
    this.icon,
    this.color, {
    this.badge,
  });
}
