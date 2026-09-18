import 'package:flutter/material.dart';

import 'screens/flow_login_screen.dart';
import 'services/driver_push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DriverPushService.instance.initialize();
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
    );
  }
}
