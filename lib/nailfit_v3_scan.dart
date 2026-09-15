import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'nailfit_v3_model.dart';
import 'nailfit_v3_widgets.dart';

class NailFitV3Scan extends StatelessWidget {
  const NailFitV3Scan({super.key, required this.c, required this.photo, required this.pick});
  final NailFitV3Controller c;
  final XFile? photo;
  final Future<void> Function(ImageSource) pick;

  @override
  Widget build(BuildContext context) => nfBackground(SingleChildScrollView(
    physics: const BouncingScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      nfHeader(), const SizedBox(height: 22),
      const Text('Kéz szkennelése', style: TextStyle(fontFamily: 'serif', fontSize: 37, color: nfInk, height: 1)),
      const SizedBox(height: 8),
      const Text('Igazítsd a kezed a kerethez, és készíts egy éles fotót.', style: TextStyle(color: nfMuted, fontSize: 12)),
      const SizedBox(height: 16), _preview(), const SizedBox(height: 14),
      _feature('Bőrtónus', 'Világos, meleg', Icons.circle),
      _feature('Kézforma', 'Karcsú, hosszúkás', Icons.back_hand_outlined),
      _feature('Körömágy', 'Közepes, ovális', Icons.water_drop_outlined),
      _feature('Ajánlott forma', 'Mandula', Icons.auto_awesome_rounded),
      const SizedBox(height: 12), _analysis(), const SizedBox(height: 20),
      nfSectionTitle('Ajánlott stílusok neked', 'Összes'), const SizedBox(height: 10),
      nfLookStrip(premiumLooks.take(3).toList(), c), const SizedBox(height: 15),
      Row(children: [Expanded(child: nfPrimary(Icons.auto_awesome_rounded, 'Elemzés indítása', () => c.go(2))), const SizedBox(width: 9), Expanded(child: nfSecondary(Icons.camera_alt_outlined, 'Fotó újra', () => pick(ImageSource.camera)))])
    ]),
  ));

  Widget _preview() => Container(height: 430, clipBehavior: Clip.antiAlias, decoration: BoxDecoration(borderRadius: BorderRadius.circular(28), border: Border.all(color: Colors.white), boxShadow: const [BoxShadow(color: Color(0x1B90636B), blurRadius: 24, offset: Offset(0, 10))]), child: Stack(fit: StackFit.expand, children: [
    photo != null ? Image.file(File(photo!.path), fit: BoxFit.cover) : nfPhoto(nfAlmondUrl),
    Positioned(left: 15, right: 15, top: 15, child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0x81392E2C), borderRadius: BorderRadius.circular(99)), child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.camera_alt_rounded, color: Colors.white, size: 16), SizedBox(width: 7), Text('Igazítsd a kezed a kerethez', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800))]))),
  ]));

  Widget _feature(String title, String sub, IconData icon) => Container(margin: const EdgeInsets.only(bottom: 7), padding: const EdgeInsets.all(11), decoration: nfCard(), child: Row(children: [CircleAvatar(radius: 18, backgroundColor: const Color(0xFFF6D8DE), child: Icon(icon, size: 17, color: nfRoseDark)), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 10.5)), Text(sub, style: const TextStyle(color: nfMuted, fontSize: 9.3))])), const Icon(Icons.chevron_right_rounded, color: nfMuted, size: 18)]));

  Widget _analysis() => Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFFE7EA), Color(0xFFF6D6DB)]), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white)), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Icon(Icons.auto_awesome_rounded, color: nfRose, size: 15), SizedBox(width: 5), Text('AI ELEMZÉS', style: TextStyle(color: nfRoseDark, fontSize: 8, letterSpacing: 1, fontWeight: FontWeight.w800))]), SizedBox(height: 9), Text('Mandula forma ajánlott.', style: TextStyle(fontFamily: 'serif', fontSize: 25, color: nfInk)), SizedBox(height: 6), Text('A kezed arányaihoz harmonikusan illik. Meleg nude árnyalatok különösen jól állnak.', style: TextStyle(color: nfMuted, fontSize: 10, height: 1.35))]));
}
