import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/flow_login_screen.dart';
import 'services/aims_display_mode.dart';
import 'services/aims_locale.dart';
import 'services/driver_push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // A local preference or a temporary platform problem must never prevent
  // the driver application from opening.
  try {
    await AimsLocaleController.instance.initialize();
  } catch (_) {}
  try {
    await AimsDisplayModeController.instance.initialize();
  } catch (_) {}

  runApp(const AimsFlowApp());

  // Push is important, but Firebase/network problems must not block startup.
  unawaited(
    DriverPushService.instance.initialize().catchError((_) {
      // DriverShell retries registration after identity recovery.
    }),
  );
}

class AimsFlowApp extends StatelessWidget {
  const AimsFlowApp({super.key});

  static const _aimsBlue = Color(0xFF1478FF);

  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final background = dark
        ? const Color(0xFF111315)
        : const Color(0xFFF4F6F8);
    final surface = dark
        ? const Color(0xFF191C1F)
        : Colors.white;
    final surfaceAlt = dark
        ? const Color(0xFF22262A)
        : const Color(0xFFEDF2F5);
    final text = dark ? Colors.white : const Color(0xFF17212A);
    final muted = dark ? const Color(0xFFCFD5DA) : const Color(0xFF536471);
    final line = dark ? const Color(0xFF383D42) : const Color(0xFFD5DEE5);

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _aimsBlue,
        brightness: brightness,
        surface: surface,
      ).copyWith(
        primary: _aimsBlue,
        onPrimary: Colors.white,
        surface: surface,
        onSurface: text,
        onSurfaceVariant: muted,
        outline: line,
        error: const Color(0xFFD94A4A),
        onError: Colors.white,
      ),
    );

    final textTheme = base.textTheme.apply(
      bodyColor: text,
      displayColor: text,
    );

    return base.copyWith(
      textTheme: textTheme.copyWith(
        headlineSmall: textTheme.headlineSmall?.copyWith(
          fontSize: 28,
          fontWeight: FontWeight.w900,
          height: 1.08,
          letterSpacing: -.35,
        ),
        titleLarge: textTheme.titleLarge?.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w900,
          height: 1.15,
        ),
        titleMedium: textTheme.titleMedium?.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w900,
          height: 1.2,
        ),
        bodyLarge: textTheme.bodyLarge?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
        bodyMedium: textTheme.bodyMedium?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          height: 1.4,
        ),
        bodySmall: textTheme.bodySmall?.copyWith(
          color: muted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
        labelLarge: textTheme.labelLarge?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w900,
          letterSpacing: .15,
        ),
      ),
      primaryTextTheme: textTheme,
      appBarTheme: AppBarTheme(
        elevation: 0,
        backgroundColor: surface,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: text,
          fontSize: 20,
          fontWeight: FontWeight.w900,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceAlt,
        labelStyle: TextStyle(color: muted),
        floatingLabelStyle: const TextStyle(color: _aimsBlue),
        hintStyle: TextStyle(
          color: muted,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        helperStyle: TextStyle(color: muted),
        errorStyle: TextStyle(color: dark ? Colors.white : const Color(0xFFB12626)),
        prefixIconColor: muted,
        suffixIconColor: muted,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _aimsBlue, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFD94A4A)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: _aimsBlue.withValues(alpha: dark ? .22 : .12),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: states.contains(WidgetState.selected) ? _aimsBlue : muted,
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        textColor: text,
        iconColor: muted,
        titleTextStyle: TextStyle(color: text, fontWeight: FontWeight.w800),
        subtitleTextStyle: TextStyle(color: muted),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        textColor: text,
        collapsedTextColor: text,
        iconColor: _aimsBlue,
        collapsedIconColor: muted,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: surfaceAlt,
        side: BorderSide(color: line),
        labelStyle: TextStyle(color: text, fontWeight: FontWeight.w800),
        secondaryLabelStyle: TextStyle(color: text),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: line),
        ),
      ),
      dividerColor: line,
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: text,
          fontSize: 20,
          fontWeight: FontWeight.w900,
        ),
        contentTextStyle: TextStyle(color: text),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: dark ? const Color(0xFF2B3035) : const Color(0xFF26333D),
        contentTextStyle: const TextStyle(color: Colors.white),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 54),
          backgroundColor: _aimsBlue,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(
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
          foregroundColor: text,
          side: BorderSide(color: line),
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _aimsBlue,
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? _aimsBlue
              : Colors.transparent,
        ),
        checkColor: WidgetStateProperty.all(Colors.white),
        side: BorderSide(color: line),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? _aimsBlue : muted,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : (dark ? const Color(0xFFB9C0C5) : Colors.white),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? _aimsBlue
              : line,
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
        // AUTO follows the locally calculated sunrise/sunset state. Manual
        // LIGHT and DARK remain explicit user choices.
        themeMode: display.isDark ? ThemeMode.dark : ThemeMode.light,
        home: const FlowLoginScreen(),
      ),
    );
  }
}
