import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'nailfit_v3_home.dart';
import 'nailfit_v3_model.dart';
import 'nailfit_v3_saved_profile.dart';
import 'nailfit_v3_scan.dart';
import 'nailfit_v3_try.dart';

class NailFitApp extends StatefulWidget {
  const NailFitApp({super.key});

  @override
  State<NailFitApp> createState() => _NailFitAppState();
}

class _NailFitAppState extends State<NailFitApp> {
  final c = NailFitV3Controller();
  final picker = ImagePicker();
  XFile? photo;

  @override
  void initState() {
    super.initState();
    c.addListener(_refresh);
    c.restore();
  }

  @override
  void dispose() {
    c.removeListener(_refresh);
    c.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _pick(ImageSource source) async {
    final file = await picker.pickImage(
      source: source,
      imageQuality: 92,
      maxWidth: 2400,
    );
    if (!mounted || file == null) return;
    c.resetScan();
    setState(() => photo = file);
    c.go(1);
    await c.analyzePhoto(file);
  }

  Widget _activeScreen(NailFitV3SavedProfile savedProfile) {
    switch (c.tab) {
      case 1:
        return NailFitV3Scan(c: c, photo: photo, pick: _pick);
      case 2:
        return NailFitV3Try(c: c, photo: photo, pick: _pick);
      case 3:
        return savedProfile.saved();
      case 4:
        return savedProfile.profile();
      case 0:
      default:
        return NailFitV3Home(c: c, pick: _pick);
    }
  }

  @override
  Widget build(BuildContext context) {
    final savedProfile = NailFitV3SavedProfile(c: c);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NAILFIT',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: nfCream,
        colorScheme: ColorScheme.fromSeed(
          seedColor: nfRose,
          brightness: Brightness.light,
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: Scaffold(
        body: SafeArea(
          bottom: false,
          child: _activeScreen(savedProfile),
        ),
        bottomNavigationBar: _nav(),
      ),
    );
  }

  Widget _nav() {
    const items = [
      (Icons.home_outlined, Icons.home_rounded, 'Főoldal'),
      (Icons.camera_alt_outlined, Icons.camera_alt_rounded, 'Scan'),
      (Icons.auto_awesome_outlined, Icons.auto_awesome_rounded, 'Try-On'),
      (Icons.favorite_border_rounded, Icons.favorite_rounded, 'Mentett'),
      (Icons.person_outline_rounded, Icons.person_rounded, 'Profil'),
    ];

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 5, 14, 9),
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFCFA),
          borderRadius: BorderRadius.circular(29),
          border: Border.all(color: Colors.white),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1FB17A85),
              blurRadius: 25,
              offset: Offset(0, 9),
            ),
          ],
        ),
        child: Row(
          children: List.generate(items.length, (i) {
            final active = c.tab == i;
            return Expanded(
              child: InkWell(
                key: ValueKey('nav-$i'),
                onTap: () => c.go(i),
                borderRadius: BorderRadius.circular(22),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: active ? const Color(0xFFFBE3E7) : Colors.transparent,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        active ? items[i].$2 : items[i].$1,
                        color: active ? nfRoseDark : const Color(0xFF475257),
                        size: 23,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        items[i].$3,
                        style: TextStyle(
                          fontSize: 10,
                          color: active ? nfRoseDark : const Color(0xFF475257),
                          fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                        ),
                      ),
                      SizedBox(
                        height: 4,
                        child: active
                            ? const Center(
                                child: CircleAvatar(
                                  radius: 2.5,
                                  backgroundColor: nfRoseDark,
                                ),
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
