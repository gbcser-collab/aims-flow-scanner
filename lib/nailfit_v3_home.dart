import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'nailfit_v3_model.dart';
import 'nailfit_v3_widgets.dart';

class NailFitV3Home extends StatelessWidget {
  const NailFitV3Home({super.key, required this.c, required this.pick});
  final NailFitV3Controller c;
  final Future<void> Function(ImageSource) pick;

  @override
  Widget build(BuildContext context) => nfBackground(SingleChildScrollView(
    physics: const BouncingScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      nfHeader(),
      const SizedBox(height: 18),
      _hero(),
      const SizedBox(height: 26),
      nfSectionTitle('Neked ajánljuk', 'Összes megtekintése'),
      const SizedBox(height: 10),
      nfLookStrip(premiumLooks, c),
      const SizedBox(height: 18),
      Row(children: [
        Expanded(child: nfQuick(Icons.favorite_border_rounded, 'Kedvencek', 'Mentett stílusaid', () => c.go(3))),
        const SizedBox(width: 8),
        Expanded(child: nfQuick(Icons.bookmark_border_rounded, 'Look mentése', 'Kedvenc szetted', () => c.go(2))),
        const SizedBox(width: 8),
        Expanded(child: nfQuick(Icons.person_outline_rounded, 'Stílusprofil', 'Ajánlásaid', () => c.go(4))),
      ]),
      const SizedBox(height: 18),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 3, child: _match()),
        const SizedBox(width: 10),
        Expanded(flex: 2, child: _season()),
      ]),
      const SizedBox(height: 24),
      nfSectionTitle('Stílusok böngészése', 'Összes kategória'),
      const SizedBox(height: 10),
      _chips(),
      const SizedBox(height: 18),
      _ai(),
      const SizedBox(height: 12),
      _outfit(),
    ]),
  ));

  Widget _hero() => Container(
    height: 300,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(29), border: Border.all(color: Colors.white, width: 1.3), boxShadow: const [BoxShadow(color: Color(0x1E9C6872), blurRadius: 28, offset: Offset(0, 13))]),
    child: Stack(fit: StackFit.expand, children: [
      nfPhoto(nfHeroUrl),
      const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [Color(0xFFFDF0EC), Color(0xF8FDEDEA), Color(0x18FFFFFF)]))),
      Padding(padding: const EdgeInsets.fromLTRB(20, 24, 18, 18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('T A L Á L D   M E G', style: TextStyle(color: nfRoseDark, fontSize: 9, letterSpacing: 1.8, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        const Text('a hozzád illő\nkörmöket.', style: TextStyle(fontFamily: 'serif', color: nfInk, fontSize: 35, height: .95)),
        const SizedBox(height: 11),
        const SizedBox(width: 205, child: Text('Nézd meg, melyik forma, árnyalat és stílus áll neked a legjobban — még a szalon előtt.', style: TextStyle(color: nfMuted, fontSize: 11, height: 1.35))),
        const Spacer(),
        SizedBox(width: 185, child: FilledButton.icon(key: const ValueKey('hero-camera'), onPressed: () => pick(ImageSource.camera), icon: const Icon(Icons.camera_alt_rounded, size: 18), label: const Text('Készíts fotót'), style: FilledButton.styleFrom(backgroundColor: nfRose, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)), textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)))),
      ])),
      const Positioned(right: 16, top: 43, child: Text('Your\nNails\nYour Story ♡', textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontFamily: 'serif', fontStyle: FontStyle.italic, fontSize: 14, height: 1.02))),
    ]),
  );

  Widget _match() => Container(height: 205, padding: const EdgeInsets.all(16), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFFE7EB), Color(0xFFF4D3D9)]), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Row(children: [Icon(Icons.auto_awesome_rounded, size: 15, color: nfRose), SizedBox(width: 5), Text('AI AJÁNLÁS NEKED', style: TextStyle(color: nfRoseDark, fontSize: 8, letterSpacing: 1, fontWeight: FontWeight.w800))]),
    const SizedBox(height: 11),
    Text('${c.look.match}% egyezés', style: const TextStyle(fontFamily: 'serif', color: nfInk, fontSize: 30, height: 1)),
    const SizedBox(height: 7),
    const Text('Ez a stílus harmonikusan illik hozzád a kézformád és az ízlésed alapján.', style: TextStyle(color: nfMuted, fontSize: 10, height: 1.35)),
    const Spacer(),
    FilledButton(onPressed: () => c.go(2), style: FilledButton.styleFrom(backgroundColor: nfRose, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(21))), child: const Text('Próbáld ki most  →', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800))),
  ]));

  Widget _season() => Container(height: 205, padding: const EdgeInsets.all(15), decoration: nfCard(const Color(0xFFFFF4EF)), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.eco_outlined, color: nfRoseDark, size: 25), Spacer(), Text('Új őszi\nkollekció', style: TextStyle(fontFamily: 'serif', fontSize: 23, color: nfInk, height: .98)), SizedBox(height: 8), Text('Természetes árnyalatok, időtlen elegancia.', style: TextStyle(color: nfMuted, fontSize: 9, height: 1.3)), SizedBox(height: 10), Text('Felfedezem  →', style: TextStyle(color: nfRoseDark, fontSize: 10, fontWeight: FontWeight.w800))]));

  Widget _chips() { const labels = ['Minimal','Francia','Nude','Menyasszony','Őszi','Merész']; const icons = [Icons.diamond_outlined,Icons.waves_rounded,Icons.circle,Icons.favorite_border_rounded,Icons.eco_outlined,Icons.auto_awesome_rounded]; return SizedBox(height: 40, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: labels.length, separatorBuilder: (_, __) => const SizedBox(width: 7), itemBuilder: (_, i) => Chip(label: Text(labels[i]), avatar: Icon(icons[i], size: 14, color: nfRoseDark), side: const BorderSide(color: Colors.white), backgroundColor: Colors.white.withValues(alpha: .75), labelStyle: const TextStyle(fontSize: 9.5)))); }

  Widget _ai() => Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFCE4E8), Color(0xFFFFF7F3)]), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white)), child: const Row(children: [CircleAvatar(radius: 23, backgroundColor: Colors.white, child: Icon(Icons.auto_awesome_rounded, color: nfRose)), SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Beauty AI Stylist', style: TextStyle(fontFamily: 'serif', fontSize: 20, fontWeight: FontWeight.w600, color: nfInk)), SizedBox(height: 3), Text('Írd le az alkalmat, a ruhád vagy a hangulatod — személyre szabott lookokat kapsz.', style: TextStyle(color: nfMuted, fontSize: 9.8, height: 1.3))])), Icon(Icons.arrow_forward_rounded, color: nfRoseDark)]));

  Widget _outfit() => Container(padding: const EdgeInsets.all(15), decoration: nfCard(), child: const Row(children: [CircleAvatar(radius: 22, backgroundColor: Color(0xFFF7DCE1), child: Icon(Icons.checkroom_outlined, color: nfRoseDark)), SizedBox(width: 11), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Párosítsd a ruhádhoz', style: TextStyle(fontFamily: 'serif', fontSize: 19, color: nfInk, fontWeight: FontWeight.w600)), SizedBox(height: 3), Text('Tölts fel egy outfit-fotót, és válassz hozzá harmonizáló körmöt.', style: TextStyle(color: nfMuted, fontSize: 9.5))])), Icon(Icons.chevron_right_rounded, color: nfMuted)]));
}
