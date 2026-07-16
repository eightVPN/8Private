import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vpn8_client/main.dart';
import 'package:vpn8_client/vpn_provider.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => VPNProvider()),
        ],
        child: const VPN8App(),
      ),
    );

    // Verify that the app launches and displays the primary app header title
    expect(find.text('VPN 8'), findsWidgets);
  });
}
