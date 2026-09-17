import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/device_gate.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/local_auth_service.dart';
import 'widgets/aims_skin.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
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
        colorScheme: ColorScheme.fromSeed(seedColor: aimsCyan, brightness: Brightness.dark),
        scaffoldBackgroundColor: aimsNavy,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF03152C),
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: Color(0xFF0B2E57),
          contentTextStyle: TextStyle(color: Colors.white),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 52),
            backgroundColor: aimsBlue,
            foregroundColor: Colors.white,
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ),
      home: AnimatedBuilder(
        animation: LocalAuthService.instance,
        builder: (context, _) {
          if (!LocalAuthService.instance.authenticated) return const LoginScreen();
          return const DeviceGate(child: HomeScreen());
        },
      ),
    );
  }
}
