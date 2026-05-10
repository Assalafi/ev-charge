import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner_web_plugin.dart'
    if (dart.library.io) 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mobile_scanner/src/web/jsqr.dart'
    if (dart.library.io) 'package:mobile_scanner/mobile_scanner.dart';
import 'config/theme.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/splash_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    MobileScannerWebPlugin.barCodeReader =
        JsQrCodeReader(videoContainer: MobileScannerWebPlugin.vidDiv);
  }
  runApp(const EVChargeApp());
}

class EVChargeApp extends StatelessWidget {
  const EVChargeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'EV Charge',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: themeProvider.themeMode,
            home: const SplashScreen(),
          );
        },
      ),
    );
  }
}
