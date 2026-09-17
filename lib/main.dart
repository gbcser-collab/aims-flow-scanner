import 'package:flutter/material.dart';

import 'screens/login_screen.dart';
import 'widgets/aims_flow_skin.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AimsFlowApp());
}

class AimsFlowApp extends StatelessWidget {
  const AimsFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AIMS Flow',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AimsFlowSkin.cyan,
          brightness: Brightness.dark,
          surface: AimsFlowSkin.panelSolid,
        ),
        scaffoldBackgroundColor: AimsFlowSkin.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: AimsFlowSkin.background,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
        filledButtonTheme: FilledButtonThemeData(style: AimsFlowSkin.primaryButton()),
        cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
        dialogTheme: const DialogThemeData(backgroundColor: AimsFlowSkin.panelSolid),
      ),
      home: const LoginScreen(),
    );
  }
}
