import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AimsFlowApp());
}

class AimsFlowApp extends StatelessWidget {
  const AimsFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFE6B85C);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AIMS Flow Scanner',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: gold, brightness: Brightness.light),
        scaffoldBackgroundColor: const Color(0xFFF5F5F2),
        cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
        filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(0, 52), textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
      ),
      home: const HomeScreen(),
    );
  }
}
