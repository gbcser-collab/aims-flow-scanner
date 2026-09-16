import 'package:flutter/material.dart';

import 'screens/flow_shell_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AimsFlowApp());
}

class AimsFlowApp extends StatelessWidget {
  const AimsFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    const aimsBlue = Color(0xFF1CB8FF);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AIMS Flow',
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
        navigationBarTheme: NavigationBarThemeData(
          height: 70,
          backgroundColor: const Color(0xFF030D16),
          indicatorColor: aimsBlue.withValues(alpha: .18),
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              color: states.contains(WidgetState.selected) ? Colors.white : Colors.white54,
              fontSize: 11,
              fontWeight: states.contains(WidgetState.selected) ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ),
        cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 54),
            backgroundColor: aimsBlue,
            foregroundColor: Colors.white,
            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 52),
            foregroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFF24557D)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF0A1A2C).withValues(alpha: .92),
          labelStyle: const TextStyle(color: Colors.white60),
          hintStyle: const TextStyle(color: Colors.white30),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: Color(0xFF24557D)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: aimsBlue, width: 1.4),
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFF0A1A2C),
          contentTextStyle: TextStyle(color: Colors.white),
        ),
      ),
      home: const FlowShellScreen(),
    );
  }
}
