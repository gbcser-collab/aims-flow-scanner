import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/flow_login_screen.dart';
import 'services/aims_locale.dart';
import 'services/driver_push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Only the minimum required local state is allowed to block first paint.
  // Push / Firebase / notification failures must never replace the login UI
  // with Flutter's red error screen.
  try {
    await AimsLocaleController.instance.initialize();
  } catch (_) {
    // The app remains usable with the controller's default locale.
  }

  runApp(const AimsFlowApp());
  unawaited(_initializeOptionalRuntime());
}

Future<void> _initializeOptionalRuntime() async {
  try {
    await DriverPushService.instance.initialize();
  } catch (_) {
    // DriverShell retries push registration later. Startup must stay alive.
  }
}

class AimsFlowApp extends StatelessWidget {
  const AimsFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    const aimsBlue = Color(0xFF1CB8FF);
    final locale = AimsLocaleController.instance;
    return AnimatedBuilder(
      animation: locale,
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
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: aimsBlue,
          brightness: Brightness.dark,
          surface: const Color(0xFF07111F),
        ),
        scaffoldBackgroundColor: const Color(0xFF030A13),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF030A13),
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 54),
            backgroundColor: aimsBlue,
            foregroundColor: const Color(0xFF00131F),
            textStyle:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
      home: const FlowLoginScreen(),
    ),
    );
  }
}
