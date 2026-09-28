import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/flow_login_screen.dart';
import 'services/aims_display_mode.dart';
import 'services/aims_locale.dart';
import 'services/driver_push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Local UI preferences should never prevent the driver app from opening.
  try {
    await AimsLocaleController.instance.initialize();
  } catch (_) {}
  try {
    await AimsDisplayModeController.instance.initialize();
  } catch (_) {}

  runApp(const AimsFlowApp());

  // Push is important, but a Firebase/network problem must not block startup.
  unawaited(
    DriverPushService.instance.initialize().catchError((_) {
      // DriverShell will retry registration after identity recovery.
    }),
  );
}

class AimsFlowApp extends StatelessWidget {
  const AimsFlowApp({super.key});

  ThemeData _theme() {
    const aimsBlue = Color(0xFF1CB8FF);
    const surface = Color(0xFF07111F);
    const background = Color(0xFF030A13);

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: aimsBlue,
        brightness: Brightness.dark,
        surface: surface,
      ).copyWith(
        primary: aimsBlue,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: Colors.white,
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: background,
    );

    final whiteText = base.textTheme.apply(
      bodyColor: Colors.white,
      displayColor: Colors.white,
    );

    return base.copyWith(
      textTheme: whiteText.copyWith(
        headlineSmall: whiteText.headlineSmall?.copyWith(
          color: Colors.white,
          fontSize: 28,
          fontWeight: FontWeight.w900,
          height: 1.08,
          letterSpacing: -.35,
        ),
        titleLarge: whiteText.titleLarge?.copyWith(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w900,
          height: 1.15,
        ),
        titleMedium: whiteText.titleMedium?.copyWith(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w900,
          height: 1.2,
        ),
        bodyLarge: whiteText.bodyLarge?.copyWith(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
        bodyMedium: whiteText.bodyMedium?.copyWith(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w500,
          height: 1.4,
        ),
        bodySmall: whiteText.bodySmall?.copyWith(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
        labelLarge: whiteText.labelLarge?.copyWith(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w900,
          letterSpacing: .15,
        ),
        labelMedium: whiteText.labelMedium?.copyWith(color: Colors.white),
        labelSmall: whiteText.labelSmall?.copyWith(color: Colors.white),
      ),
      primaryTextTheme: whiteText,
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w900,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF071725),
        labelStyle: const TextStyle(color: Colors.white),
        floatingLabelStyle: const TextStyle(color: Colors.white),
        hintStyle: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        helperStyle: const TextStyle(color: Colors.white),
        errorStyle: const TextStyle(color: Colors.white),
        prefixIconColor: Colors.white,
        suffixIconColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF24557D)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: aimsBlue, width: 1.6),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF04101A),
        indicatorColor: aimsBlue.withValues(alpha: .18),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
      cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
      dialogTheme: const DialogThemeData(
        backgroundColor: Color(0xFF071725),
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w900,
        ),
        contentTextStyle: TextStyle(color: Colors.white),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFF06131F),
        modalBackgroundColor: Color(0xFF06131F),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Color(0xFF102436),
        contentTextStyle: TextStyle(color: Colors.white),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 54),
          backgroundColor: aimsBlue,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          textStyle: const TextStyle(color: Colors.white),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          textStyle: const TextStyle(color: Colors.white),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        checkColor: WidgetStateProperty.all(Colors.white),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? aimsBlue
              : Colors.white,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(Colors.white),
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
        theme: _theme(),
        darkTheme: _theme(),
        // Flow uses a permanently dark operational surface so every text
        // remains white and readable. Display mode still controls the
        // night-time brightness cap independently.
        themeMode: ThemeMode.dark,
        home: const FlowLoginScreen(),
      ),
    );
  }
}
