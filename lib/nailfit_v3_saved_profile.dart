import 'package:flutter/material.dart';
import 'nailfit_v3_model.dart';
import 'nailfit_v3_widgets.dart';

class NailFitV3SavedProfile extends StatelessWidget {
  const NailFitV3SavedProfile({super.key, required this.c});
  final NailFitV3Controller c;

  Widget saved() {
    final favs = premiumLooks.where((e) => c.favorites.contains(e.name)).toList();
    final data = favs.isEmpty ? premiumLooks.take(3).toList() : favs;
    return nfBackground(SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 30), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      nfHeader(), const SizedBox(height: 24),
      const Text('Mentett', style: TextStyle(fontFamily: 'serif', fontSize: 39, color: nfInk)),
      Text('${data.length} kedvenc stílus · ${c.saved.length} mentett look', style: const TextStyle(color: nfMuted, fontSize: 12)),
      const SizedBox(height: 24), nfSectionTitle('Mentett kollekciók', 'Összes kollekció'), const SizedBox(height: 10), _collections(),
      const SizedBox(height: 24), nfSectionTitle('Kedvenc szettjeid', 'Összes megtekintése'), const SizedBox(height: 10), nfLookStrip(data, c),
      const SizedBox(height: 20), _banner(),
    ])));
  }

  Widget profile() => nfBackground(SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 30), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    nfHeader(), const SizedBox(height: 20), _profileCard(),
    const SizedBox(height: 24), nfSectionTitle('Mentett kollekciók', 'Összes kollekció'), const SizedBox(height: 10), _collections(),
    const SizedBox(height: 24), nfSectionTitle('Kedvenc szettjeid', 'Összes megtekintése'), const SizedBox(height: 10), nfLookStrip(premiumLooks.take(3).toList(), c),
    const SizedBox(height: 18), GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), childAspectRatio: 2.55, crossAxisSpacing: 8, mainAxisSpacing: 8, children: [
      _utility(Icons.person_outline_rounded, 'Stílusprofil szerkesztése'), _utility(Icons.notifications_none_rounded, 'Értesítések'), _utility(Icons.share_outlined, 'Megosztott lookok'), _utility(Icons.image_outlined, 'PNG export'), _utility(Icons.settings_outlined, 'Beállítások'), _utility(Icons.help_outline_rounded, 'Súgó és GYIK')]),
    const SizedBox(height: 18), _banner(),
  ])));

  Widget _collections() => SizedBox(height: 154, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: 4, separatorBuilder: (_, __) => const SizedBox(width: 9), itemBuilder: (_, i) => Container(width: 160, clipBehavior: Clip.antiAlias, decoration: nfCard(), child: Column(children: [Expanded(child: nfPhoto(premiumLooks[i].image, tint: premiumLooks[i].color)), Padding(padding: const EdgeInsets.all(9), child: Text(['Nude kedvencek','Őszi elegancia','Csillogó hangulat','Francia klasszikus'][i], style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)))]))));

  Widget _profileCard() => Container(padding: const EdgeInsets.all(16), decoration: nfCard(const Color(0xFFFFF2F0)), child: Column(children: [
    Row(children: [const CircleAvatar(radius: 52, backgroundImage: NetworkImage(nfHeroUrl), backgroundColor: Color(0xFFF4D6D8)), const SizedBox(width: 15), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Anna', style: TextStyle(fontFamily: 'serif', fontSize: 35, color: nfInk)), const Text('Stílusprofil  ›', style: TextStyle(color: nfMuted, fontSize: 13)), const SizedBox(height: 12), Wrap(spacing: 6, runSpacing: 6, children: const [_Tag('Mandula'), _Tag('Nude'), _Tag('Minimal'), _Tag('Őszi')])]))]),
    const SizedBox(height: 16), const Divider(color: nfLine), const SizedBox(height: 8),
    Row(children: [Expanded(child: _stat(Icons.bookmark_border_rounded, '24', 'Mentett lookok')), Expanded(child: _stat(Icons.favorite_border_rounded, '17', 'Kedvencek')), Expanded(child: _stat(Icons.auto_awesome_rounded, '36', 'Próbák'))])
  ]));

  Widget _stat(IconData icon, String n, String label) => Column(children: [CircleAvatar(radius: 22, backgroundColor: const Color(0xFFF8DCE2), child: Icon(icon, color: nfInk, size: 20)), const SizedBox(height: 5), Text(n, style: const TextStyle(fontFamily: 'serif', fontSize: 20, color: nfInk)), Text(label, textAlign: TextAlign.center, style: const TextStyle(color: nfMuted, fontSize: 8.5))]);
  Widget _utility(IconData icon, String label) => Container(padding: const EdgeInsets.symmetric(horizontal: 12), decoration: nfCard(), child: Row(children: [CircleAvatar(radius: 18, backgroundColor: const Color(0xFFF8DCE1), child: Icon(icon, size: 18, color: nfInk)), const SizedBox(width: 9), Expanded(child: Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700))), const Icon(Icons.chevron_right_rounded, color: nfMuted, size: 17)]));
  Widget _banner() => Container(height: 140, clipBehavior: Clip.antiAlias, decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white)), child: Stack(fit: StackFit.expand, children: [nfPhoto(nfHeroUrl), const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFFFE7EB), Color(0xF2FFF3EF), Color(0x30FFFFFF)]))), const Padding(padding: EdgeInsets.all(17), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('✦  BEAUTY AI', style: TextStyle(color: nfRoseDark, fontSize: 8, fontWeight: FontWeight.w800)), SizedBox(height: 8), Text('Személyre szabott ajánlás', style: TextStyle(fontFamily: 'serif', fontSize: 22, color: nfInk)), SizedBox(height: 4), Text('Fedezz fel új stílusokat a Te ízlésed alapján.', style: TextStyle(color: nfMuted, fontSize: 9.5))]) ]));
}

class _Tag extends StatelessWidget { const _Tag(this.text); final String text; @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .72), borderRadius: BorderRadius.circular(99), border: Border.all(color: Colors.white)), child: Text(text, style: const TextStyle(fontSize: 9.5, color: nfInk))); }
