import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'theme.dart';
import 'services/ssh_deploy_service.dart';

class SSHSetupScreen extends StatefulWidget {
  final Function(String) onNavigate;

  const SSHSetupScreen({super.key, required this.onNavigate});

  @override
  State<SSHSetupScreen> createState() => _SSHSetupScreenState();
}

class _SSHSetupScreenState extends State<SSHSetupScreen> {
  final _ipController = TextEditingController();
  final _userController = TextEditingController(text: 'root');
  final _portController = TextEditingController(text: '22');
  final _passwordController = TextEditingController();

  String _authMode = 'password';
  bool _autoUpdate = false;
  bool _showPassword = false;
  bool _cursorVisible = true;
  Timer? _cursorTimer;

  bool _isDeploying = false;
  List<String> _deployLogs = ['> Awaiting deployment configuration...'];
  final ScrollController _terminalScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _cursorTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      setState(() => _cursorVisible = !_cursorVisible);
    });
  }

  @override
  void dispose() {
    _cursorTimer?.cancel();
    _ipController.dispose();
    _userController.dispose();
    _portController.dispose();
    _passwordController.dispose();
    _terminalScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Stack(
        children: [
          // Background atmosphere
          Positioned.fill(
            child: IgnorePointer(
              child: Stack(
                children: [
                  Positioned(
                    top: -50,
                    left: -80,
                    child: Container(
                      width: 256,
                      height: 256,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color.fromRGBO(122, 34, 255, 0.1),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -50,
                    right: -80,
                    child: Container(
                      width: 384,
                      height: 384,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color.fromRGBO(76, 215, 246, 0.1),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Main content
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTopAppBar(),
                _buildHeader(),
                _buildTerminalPreview(),
                _buildConfigForm(),
                _buildFeatureCards(),
                const SizedBox(height: 100),
              ],
            ),
          ),

          // Bottom nav
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
              const Icon(Icons.menu, color: AppColors.onSurface, size: 24),
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
          // Tag pill + gradient line
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Color.fromRGBO(0, 109, 128, 0.3),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: Color.fromRGBO(76, 215, 246, 0.2)),
                ),
                child: Text(
                  'NODE PROVISIONING',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.tertiary,
                    letterSpacing: 2.0,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color.fromRGBO(76, 215, 246, 0.2),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Server Setup',
            style: GoogleFonts.hankenGrotesk(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Establish a secure bridge to your infrastructure. VPN 8 uses high-level SSH automation to deploy a containerized Docker environment, ensuring your network is isolated and optimized within seconds.',
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

  Widget _buildTerminalPreview() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: GlassPanel(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.terminal, color: AppColors.tertiary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'INITIALIZATION SEQUENCE',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.tertiary,
                    letterSpacing: 2.0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              height: 200, // Fixed height for scrolling
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Color.fromRGBO(0, 0, 0, 0.4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Color.fromRGBO(255, 255, 255, 0.05)),
              ),
              child: SingleChildScrollView(
                controller: _terminalScrollController,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var logLine in _deployLogs)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          logLine,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 12,
                            color:
                                logLine.startsWith('ERR') ||
                                    logLine.startsWith('> ERROR')
                                ? AppColors.error
                                : logLine.startsWith('>')
                                ? AppColors.tertiary
                                : AppColors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        Text(
                          '>',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 12,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 4),
                        AnimatedOpacity(
                          opacity: _cursorVisible ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 100),
                          child: Container(
                            width: 8,
                            height: 16,
                            color: AppColors.tertiary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Color.fromRGBO(255, 255, 255, 0.1),
                    ),
                  ),
                  child: const Icon(
                    Icons.dock,
                    color: AppColors.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Docker Engine',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface,
                      ),
                    ),
                    Text(
                      'Automated deployment on Ubuntu 20.04+',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigForm() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: GlassPanel(
        borderRadius: 16,
        padding: const EdgeInsets.all(32),
        child: Stack(
          children: [
            // Subtle glow effect
            Positioned(
              top: -48,
              right: -48,
              child: Container(
                width: 192,
                height: 192,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color.fromRGBO(122, 34, 255, 0.2),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // IP Address
                _buildLabel('SERVER IPV4 ADDRESS'),
                const SizedBox(height: 8),
                _buildTextField(
                  controller: _ipController,
                  hint: '192.168.1.1',
                  icon: Icons.dns,
                  mono: true,
                ),
                const SizedBox(height: 24),

                // Username & Port
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildLabel('SSH USERNAME'),
                          const SizedBox(height: 8),
                          _buildTextField(
                            controller: _userController,
                            hint: 'root',
                            icon: Icons.person,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildLabel('SSH PORT'),
                          const SizedBox(height: 8),
                          _buildTextField(
                            controller: _portController,
                            hint: '22',
                            icon: Icons.numbers,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Auth toggle
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Color.fromRGBO(255, 255, 255, 0.05),
                    ),
                  ),
                  child: Row(
                    children: [
                      _buildAuthTab('Password', 'password'),
                      _buildAuthTab('SSH Key', 'key'),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Password field
                if (_authMode == 'password') ...[
                  _buildLabel('ROOT PASSWORD'),
                  const SizedBox(height: 8),
                  _buildTextField(
                    controller: _passwordController,
                    hint: '••••••••••••',
                    icon: Icons.key,
                    obscure: !_showPassword,
                    suffix: IconButton(
                      icon: Icon(
                        _showPassword ? Icons.visibility_off : Icons.visibility,
                        color: AppColors.onSurfaceVariant,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                    ),
                  ),
                ] else if (_authMode == 'key') ...[
                  _buildLabel('PRIVATE SSH KEY'),
                  const SizedBox(height: 8),
                  _buildTextField(
                    controller: _passwordController,
                    hint: '-----BEGIN PRIVATE KEY-----\\n...',
                    icon: Icons.vpn_key,
                    maxLines: 4,
                  ),
                ],
                const SizedBox(height: 24),

                // Watchtower checkbox
                Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: Checkbox(
                        value: _autoUpdate,
                        onChanged: (v) =>
                            setState(() => _autoUpdate = v ?? false),
                        activeColor: AppColors.primaryContainer,
                        side: BorderSide(
                          color: Color.fromRGBO(255, 255, 255, 0.2),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Enable automatic kernel security updates via Watchtower',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Deploy button
                Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        AppColors.primaryContainer,
                        AppColors.onPrimaryFixedVariant,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Color.fromRGBO(122, 34, 255, 0.5),
                        blurRadius: 20,
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _isDeploying ? null : _startDeployment,
                      borderRadius: BorderRadius.circular(12),
                      child: Center(
                        child: _isDeploying
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Deploy Server',
                                    style: GoogleFonts.hankenGrotesk(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(
                                    Icons.rocket_launch,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Warning footer
                Container(
                  height: 1,
                  color: Color.fromRGBO(255, 255, 255, 0.05),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: AppColors.outline,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Deploying a server will install Docker, Nginx, and WireGuard. Ensure your cloud provider\'s firewall permits traffic on port 51820.',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppColors.outline,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _startDeployment() {
    if (_ipController.text.isEmpty) return;

    setState(() {
      _isDeploying = true;
      _deployLogs = [
        '> Starting deployment sequence to ${_ipController.text}...',
      ];
    });

    final config = SSHDeployConfig(
      host: _ipController.text,
      port: int.tryParse(_portController.text) ?? 22,
      username: _userController.text,
      password: _authMode == 'password' ? _passwordController.text : null,
      privateKey: _authMode == 'key'
          ? _passwordController.text
          : null, // If key, user pastes key in password field
      enableAutoUpdate: _autoUpdate,
    );

    final service = SSHDeployService();
    service
        .deployServer(config)
        .listen(
          (logLine) {
            setState(() {
              _deployLogs.add(logLine);
            });
            _scrollToBottom();
          },
          onError: (e) {
            setState(() {
              _deployLogs.add('> ERROR: $e');
              _isDeploying = false;
            });
            _scrollToBottom();
          },
          onDone: () {
            setState(() {
              _isDeploying = false;
            });
            _scrollToBottom();
            // On success, we can navigate home or auto-connect
            if (!_deployLogs.any((l) => l.startsWith('> ERROR'))) {
              Future.delayed(
                const Duration(seconds: 2),
                () => widget.onNavigate('home'),
              );
            }
          },
        );
  }

  void _scrollToBottom() {
    if (_terminalScrollController.hasClients) {
      _terminalScrollController.animateTo(
        _terminalScrollController.position.maxScrollExtent + 40,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.outline,
          letterSpacing: 2.0,
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool mono = false,
    bool obscure = false,
    int maxLines = 1,
    Widget? suffix,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      maxLines: maxLines,
      style: mono
          ? GoogleFonts.jetBrainsMono(fontSize: 16, color: AppColors.primary)
          : GoogleFonts.inter(fontSize: 16, color: AppColors.onSurface),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(fontSize: 16, color: AppColors.outline),
        filled: true,
        fillColor: Color.fromRGBO(16, 12, 24, 0.8),
        prefixIcon: Icon(icon, color: AppColors.onSurfaceVariant, size: 20),
        suffixIcon: suffix,
        contentPadding: const EdgeInsets.symmetric(
          vertical: 16,
          horizontal: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Color.fromRGBO(255, 255, 255, 0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Color.fromRGBO(255, 255, 255, 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
    );
  }

  Widget _buildAuthTab(String label, String mode) {
    final isActive = _authMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _authMode = mode),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? AppColors.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: Color.fromRGBO(0, 0, 0, 0.3),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isActive
                    ? AppColors.onPrimaryContainer
                    : AppColors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureCards() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Row(
        children: [
          Expanded(
            child: GlassPanel(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Color.fromRGBO(0, 109, 128, 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Color.fromRGBO(76, 215, 246, 0.3),
                      ),
                    ),
                    child: const Icon(
                      Icons.vpn_key,
                      color: AppColors.tertiary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'End-to-End Encryption',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.onSurface,
                          ),
                        ),
                        Text(
                          '256-bit AES protection',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: GlassPanel(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Color.fromRGBO(122, 34, 255, 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Color.fromRGBO(210, 188, 255, 0.3),
                      ),
                    ),
                    child: const Icon(
                      Icons.bolt,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Instant Provisioning',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.onSurface,
                          ),
                        ),
                        Text(
                          'Under 45 seconds average',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: AppColors.onSurfaceVariant,
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
                'SSHSetupScreen' == 'MainConnectionScreen',
              ),
              _navIcon(
                Icons.language,
                'split',
                'SSHSetupScreen' == 'SplitTunnelingScreen',
              ),
              _navIcon(
                Icons.settings,
                'setup',
                'SSHSetupScreen' == 'SSHSetupScreen',
              ),
              _navIcon(
                Icons.admin_panel_settings,
                'admin',
                'SSHSetupScreen' == 'ServerAdministrationScreen',
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
