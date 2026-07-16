import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'theme.dart';
import 'vpn_provider.dart';
import 'main_connection_screen.dart';
import 'ssh_setup_screen.dart';
import 'server_administration_screen.dart';
import 'split_tunneling_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  bool isDesktop = false;
  try {
    isDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  } catch (_) {}

  if (isDesktop) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      size: Size(430, 850),
      minimumSize: Size(380, 700),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(const VPN8App());
}

class VPN8App extends StatelessWidget {
  const VPN8App({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => VPNProvider())],
      child: MaterialApp(
        title: 'VPN 8',
        debugShowCheckedModeBanner: false,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
        home: const MainNavigationShell(),
      ),
    );
  }
}

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _currentIndex = 0;

  void _navigateTo(String screen) {
    int index = 0;
    switch (screen) {
      case 'home':
        index = 0;
      case 'admin':
        index = 1;
      case 'split':
        index = 2;
      case 'setup':
        index = 3;
    }
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: _currentIndex,
      children: [
        MainConnectionScreen(onNavigate: _navigateTo),
        ServerAdministrationScreen(onNavigate: _navigateTo),
        SplitTunnelingScreen(onNavigate: _navigateTo),
        SSHSetupScreen(onNavigate: _navigateTo),
      ],
    );
  }
}
