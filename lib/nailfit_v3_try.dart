import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'nailfit_v3_model.dart';
import 'nailfit_v3_widgets.dart';

class NailFitV3Try extends StatelessWidget {
  const NailFitV3Try({super.key, required this.c, required this.photo, required this.pick});
  final NailFitV3Controller c;
  final XFile? photo;
  final Future<void> Function(ImageSource) pick;

  @override
  Widget build(BuildContext context) => nfBackground(SingleChildScrollView(
    physics: const BouncingScrollPhysics(), padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      nfHeader(), const SizedBox(height: 20),
      Row(children: [
        Container(width: 43, height: 43, decoration: const BoxDecoration(color: Color(0xFFFBE4E7), shape: BoxShape.circle), child: IconButton(onPressed: () => c.go(1), icon: const Icon(Icons.arrow_back_rounded, color: nfInk))),
        const SizedBox(width: 12),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('V I R T U Á L I S   P R Ó B A', style: TextStyle(color: nfRoseDark, fontSize: 8.5, letterSpacing: 1.4, fontWeight: FontWeight.w800)), Text('Próbáld fel', style: TextStyle(fontFamily: 'serif', color: nfInk, fontSize: 39, height: 1)), SizedBox(height: 4), Text('Nézd meg, hogyan áll rajtad.', style: TextStyle(color: nfMuted, fontSize: 11))])),
        InkWell(onTap: () => pick(ImageSource.camera), child: const CircleAvatar(radius: 22, backgroundColor: Color(0xFFFBE3E7), child: Icon(Icons.camera_alt_rounded, color: nfRoseDark)))
      ]),
      const SizedBox(height: 16), _preview(), const SizedBox(height: 20),
      nfSectionTitle('További stílusok kipróbálása', 'Összes stílus'), const SizedBox(height: 10),
      nfLookStrip(premiumLooks, c), const SizedBox(height: 14),
      Row(children: [
        Expanded(child: _action(c.favorites.contains(c.look.name) ? Icons.favorite_rounded : Icons.favorite_border_rounded, 'Kedvencekhez', () => c.toggleFavorite())), const SizedBox(width: 8),
        Expanded(child: _action(Icons.bookmark_border_rounded, 'Look mentése', c.saveCurrent)), const SizedBox(width: 8),
        Expanded(child: _action(Icons.ios_share_rounded, 'Megosztás', () {})),
      ]),
      const SizedBox(height: 18), _booking()
    ]),
  ));

  Widget _preview() => Container(height: 445, clipBehavior: Clip.antiAlias, decoration: BoxDecoration(borderRadius: BorderRadius.circular(29), border: Border.all(color: Colors.white), boxShadow: const [BoxShadow(color: Color(0x20966973), blurRadius: 27, offset: Offset(0, 12))]), child: Stack(fit: StackFit.expand, children: [
    photo != null ? Image.file(File(photo!.path), fit: BoxFit.cover) : nfPhoto(c.look.image, tint: c.look.color),
    Positioned(left: 14, top: 14, child: Container(padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8), decoration: BoxDecoration(color: const Color(0x853A2D2C), borderRadius: BorderRadius.circular(99)), child: Text(photo == null ? 'STUDIO DEMO' : 'SAJÁT KÉZ', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)))),
    Positioned(right: 14, top: 14, child: InkWell(onTap: () => c.toggleFavorite(), child: Container(width: 42, height: 42, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: Icon(c.favorites.contains(c.look.name) ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: nfRoseDark)))),
    Positioned(left: 14, bottom: 14, child: Container(width: 190, padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .92), borderRadius: BorderRadius.circular(19)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [Text(c.look.name, style: const TextStyle(fontFamily: 'serif', fontSize: 19, color: nfInk, fontWeight: FontWeight.w600)), Text(c.look.subtitle, style: const TextStyle(color: nfMuted, fontSize: 9))]))),
    Positioned(right: 14, bottom: 14, child: Container(width: 145, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xF7FBE7EA), borderRadius: BorderRadius.circular(19), border: Border.all(color: Colors.white)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [const Row(children: [Icon(Icons.auto_awesome_rounded, color: nfRose, size: 13), SizedBox(width: 4), Text('AI AJÁNLÁS', style: TextStyle(color: nfRoseDark, fontSize: 7, fontWeight: FontWeight.w800))]), const SizedBox(height: 7), Text('${c.look.match}% egyezés', style: const TextStyle(fontFamily: 'serif', fontSize: 21, color: nfInk)), const SizedBox(height: 5), const Text('Illik a kézformádhoz és a bőrtónusodhoz.', style: TextStyle(color: nfMuted, fontSize: 8.2))]))),
  ]));

  Widget _action(IconData icon, String label, VoidCallback tap) => InkWell(onTap: tap, borderRadius: BorderRadius.circular(19), child: Container(height: 62, decoration: nfCard(), padding: const EdgeInsets.symmetric(horizontal: 8), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [CircleAvatar(radius: 17, backgroundColor: const Color(0xFFF9DBE1), child: Icon(icon, color: nfInk, size: 17)), const SizedBox(width: 7), Flexible(child: Text(label, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800)))])));

  Widget _booking() => Container(height: 92, clipBehavior: Clip.antiAlias, decoration: nfCard(), child: Row(children: [Expanded(child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [const CircleAvatar(radius: 22, backgroundColor: Color(0xFFF8DCE2), child: Icon(Icons.calendar_month_outlined, color: nfRoseDark)), const SizedBox(width: 11), const Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Időpontfoglalás a szalonban', style: TextStyle(fontFamily: 'serif', fontSize: 17, color: nfInk, fontWeight: FontWeight.w600)), SizedBox(height: 3), Text('Vidd magaddal a kedvenc stílusod, és keltsd életre!', style: TextStyle(color: nfMuted, fontSize: 8.8))])), const Icon(Icons.chevron_right_rounded, color: nfMuted)]))), SizedBox(width: 105, child: nfPhoto(nfHeroUrl))]));
}
