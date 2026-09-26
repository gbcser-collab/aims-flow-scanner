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
      textTheme: TextTheme(
        headlineSmall: TextStyle(
          color: dark ? Colors.white : const Color(0xFF06131F),
          fontSize: 28,
          fontWeight: FontWeight.w900,
          height: 1.08,
          letterSpacing: -.35,
        ),
        titleLarge: TextStyle(
          color: dark ? Colors.white : const Color(0xFF06131F),
          fontSize: 20,
          fontWeight: FontWeight.w900,
          height: 1.15,
        ),
        titleMedium: TextStyle(
          color: dark ? Colors.white : const Color(0xFF06131F),
          fontSize: 15,
          fontWeight: FontWeight.w900,
          height: 1.2,
        ),
        bodyLarge: TextStyle(
          color: dark ? Colors.white : const Color(0xFF183247),
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
        bodyMedium: TextStyle(
          color: dark ? Colors.white70 : const Color(0xFF486273),
          fontSize: 13,
          fontWeight: FontWeight.w500,
          height: 1.4,
        ),
        bodySmall: TextStyle(
          color: dark ? Colors.white54 : const Color(0xFF657B89),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
        labelLarge: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w900,
          letterSpacing: .15,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF071725) : Colors.white,
        hintStyle: TextStyle(
          color: dark ? Colors.white38 : const Color(0xFF8194A0),
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: dark ? const Color(0xFF24557D) : const Color(0xFFC9D8E1),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: aimsBlue, width: 1.6),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: dark ? const Color(0xFF04101A) : Colors.white,
        indicatorColor: aimsBlue.withValues(alpha: dark ? .18 : .12),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: states.contains(WidgetState.selected)
                ? aimsBlue
                : (dark ? Colors.white60 : const Color(0xFF536B7A)),
          ),
        ),
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
