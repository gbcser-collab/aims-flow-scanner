import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/flow_login_screen.dart';
import 'services/aims_display_mode.dart';
import 'services/aims_locale.dart';
import 'services/driver_push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AimsLocaleController.instance.initialize();
  await AimsDisplayModeController.instance.initialize();
  await DriverPushService.instance.initialize();
  runApp(const AimsFlowApp());
}

class AimsFlowApp extends StatelessWidget {
  const AimsFlowApp({super.key});

  ThemeData _theme(Brightness brightness) {
    const aimsBlue = Color(0xFF1CB8FF);
    final dark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: aimsBlue,
        brightness: brightness,
        surface: dark ? const Color(0xFF07111F) : const Color(0xFFF4F9FC),
      ),
      scaffoldBackgroundColor:
          dark ? const Color(0xFF030A13) : const Color(0xFFF4F9FC),
      appBarTheme: AppBarTheme(
        backgroundColor:
            dark ? const Color(0xFF030A13) : const Color(0xFFF4F9FC),
        foregroundColor: dark ? Colors.white : const Color(0xFF06131F),
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 54),
          backgroundColor: aimsBlue,
          foregroundColor: const Color(0xFF00131F),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = AimsLocaleController.instance;
    final display = AimsDisplayModeController.instance;
    return AnimatedBuilder(
      animation: Listenable.merge([locale, display]),
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'AIMS Flow',
        locale: locale.locale,
        supportedLocales: const [
          Locale('hu'),
          Locale('en'),
          Locale('de'),
        ],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: display.isDark ? ThemeMode.dark : ThemeMode.light,
        home: const FlowLoginScreen(),
      ),
    );
  }
}
