import 'dart:io';

import 'package:flutter/material.dart';
import 'nailfit_v3_model.dart';
import 'nailfit_v3_widgets.dart';

class NailFitV3SavedProfile {
  const NailFitV3SavedProfile({required this.c});
  final NailFitV3Controller c;

  Widget saved() {
    final favs = premiumLooks.where(c.isFavorite).toList();
    final data = <PremiumLook>{...c.saved, ...favs}.toList();
    final display = data.isEmpty ? premiumLooks.take(3).toList() : data;
    return nfBackground(
      SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Builder(builder: (context) => nfHeader(onAi: () => nfShowStylist(context, c, initial: 'elegáns '), onNotifications: () => nfShowNotifications(context, c), notificationActive: c.notificationsEnabled && c.appointment != null)),
            const SizedBox(height: 24),
            const Text('Mentett', style: TextStyle(fontFamily: 'serif', fontSize: 39, color: nfInk)),
            Text('${c.favorites.length} kedvenc stílus · ${c.saved.length} mentett look · ${c.savedPngPaths.length} PNG', style: const TextStyle(color: nfMuted, fontSize: 12)),
            const SizedBox(height: 24),
            nfSectionTitle('Mentett kollekciók', 'Összes kollekció'),
            const SizedBox(height: 10),
            _collections(),
            const SizedBox(height: 24),
            nfSectionTitle('Kedvenc szettjeid', 'Try-On'),
            const SizedBox(height: 10),
            nfLookStrip(display, c),
            if (c.savedPngPaths.isNotEmpty) ...[
              const SizedBox(height: 24),
              nfSectionTitle('Saját PNG mentéseid', '${c.savedPngPaths.length} kép'),
              const SizedBox(height: 10),
              _pngStrip(),
            ],
            const SizedBox(height: 20),
            _banner(),
          ],
        ),
      ),
    );
  }

  Widget profile() {
    return nfBackground(
      SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Builder(builder: (context) => nfHeader(onAi: () => nfShowStylist(context, c, initial: 'minimal elegáns '), onNotifications: () => nfShowNotifications(context, c), notificationActive: c.notificationsEnabled && c.appointment != null)),
            const SizedBox(height: 20),
            _profileCard(),
            const SizedBox(height: 24),
            nfSectionTitle('Mentett kollekciók', 'Összes kollekció'),
            const SizedBox(height: 10),
            _collections(),
            const SizedBox(height: 24),
            nfSectionTitle('Kedvenc szettjeid', 'Mentett'),
            const SizedBox(height: 10),
            nfLookStrip(premiumLooks.take(3).toList(), c),
            const SizedBox(height: 18),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 2.35,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              children: [
                _utility(Icons.person_outline_rounded, 'Stílusprofil szerkesztése', _editProfile),
                _utility(Icons.notifications_none_rounded, c.notificationsEnabled ? 'Értesítések: be' : 'Értesítések: ki', _toggleNotifications),
                _utility(Icons.favorite_border_rounded, 'Kedvencek és mentések', _openSaved),
                _utility(Icons.image_outlined, 'PNG exportok', _showExports),
                _utility(Icons.privacy_tip_outlined, 'Adatvédelem és törlés', _privacy),
                _utility(Icons.help_outline_rounded, 'Súgó és GYIK', _showHelp),
              ],
            ),
            const SizedBox(height: 18),
            _banner(),
          ],
        ),
      ),
    );
  }

  Widget _collections() => SizedBox(
        height: 154,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: 4,
          separatorBuilder: (_, __) => const SizedBox(width: 9),
          itemBuilder: (_, i) {
            final lookIndex = const [0, 3, 2, 1][i];
            final look = premiumLooks[lookIndex];
            return InkWell(
              onTap: () => c.select(look),
              borderRadius: BorderRadius.circular(22),
              child: Container(
                width: 160,
                clipBehavior: Clip.antiAlias,
                decoration: nfCard(),
                child: Column(
                  children: [
                    Expanded(child: nfPhoto(look.image, tint: look.color)),
                    Padding(
                      padding: const EdgeInsets.all(9),
                      child: Text(const ['Nude kedvencek','Őszi elegancia','Csillogó hangulat','Francia klasszikus'][i], style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );

  Widget _pngStrip() {
    final paths = c.savedPngPaths.where((path) => File(path).existsSync()).take(8).toList();
    if (paths.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: nfCard(),
        child: const Text('A korábbi PNG-fájlok már nem érhetők el ezen az eszközön.', style: TextStyle(color: nfMuted, fontSize: 10)),
      );
    }
    return SizedBox(
      height: 170,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: paths.length,
        separatorBuilder: (_, __) => const SizedBox(width: 9),
        itemBuilder: (_, i) => Builder(
          builder: (context) => InkWell(
            onTap: () => _previewPng(context, paths[i]),
            borderRadius: BorderRadius.circular(22),
            child: Container(
              width: 142,
              clipBehavior: Clip.antiAlias,
              decoration: nfCard(),
              child: Image.file(File(paths[i]), fit: BoxFit.cover),
            ),
          ),
        ),
      ),
    );
  }

  Widget _profileCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: nfCard(const Color(0xFFFFF2F0)),
        child: Column(
          children: [
            Row(
              children: [
                const CircleAvatar(radius: 52, backgroundColor: Color(0xFFF4D6D8), child: Icon(Icons.person_rounded, size: 48, color: Colors.white)),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Saját profil', style: TextStyle(fontFamily: 'serif', fontSize: 31, color: nfInk)),
                      const Text('NAILFIT stílusprofil', style: TextStyle(color: nfMuted, fontSize: 12)),
                      const SizedBox(height: 12),
                      Wrap(spacing: 6, runSpacing: 6, children: [_Tag(c.preferredShape), _Tag(c.preferredStyle), if (c.scan != null) _Tag(c.scan!.undertone), if (c.scan != null) _Tag(c.scan!.tone)]),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: nfLine),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _stat(Icons.bookmark_border_rounded, '${c.saved.length}', 'Mentett lookok')),
                Expanded(child: _stat(Icons.favorite_border_rounded, '${c.favorites.length}', 'Kedvencek')),
                Expanded(child: _stat(Icons.auto_awesome_rounded, '${c.tryCount}', 'Próbák')),
              ],
            ),
          ],
        ),
      );

  Widget _stat(IconData icon, String n, String label) => Column(children: [
        CircleAvatar(radius: 22, backgroundColor: const Color(0xFFF8DCE2), child: Icon(icon, color: nfInk, size: 20)),
        const SizedBox(height: 5),
        Text(n, style: const TextStyle(fontFamily: 'serif', fontSize: 20, color: nfInk)),
        Text(label, textAlign: TextAlign.center, style: const TextStyle(color: nfMuted, fontSize: 8.5)),
      ]);

  Widget _utility(IconData icon, String label, void Function(BuildContext) action) => Builder(
        builder: (context) => InkWell(
          onTap: () => action(context),
          borderRadius: BorderRadius.circular(22),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: nfCard(),
            child: Row(
              children: [
                CircleAvatar(radius: 18, backgroundColor: const Color(0xFFF8DCE1), child: Icon(icon, size: 18, color: nfInk)),
                const SizedBox(width: 9),
                Expanded(child: Text(label, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700))),
                const Icon(Icons.chevron_right_rounded, color: nfMuted, size: 17),
              ],
            ),
          ),
        ),
      );

  Widget _banner() => InkWell(
        onTap: () => c.recommendFromPrompt('${c.preferredStyle} elegáns'),
        borderRadius: BorderRadius.circular(24),
        child: Container(
          height: 160,
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFFE7EB), Color(0xFFFFF3EF)]), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white)),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('✦  BEAUTY STYLIST', style: TextStyle(color: nfRoseDark, fontSize: 8, fontWeight: FontWeight.w800)),
              SizedBox(height: 7),
              Text('Személyre szabott ajánlás', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'serif', fontSize: 21, height: 1.05, color: nfInk)),
              SizedBox(height: 5),
              Text('Érintsd meg, és a stílusprofilod alapján nyitunk egy ajánlott lookot.', maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: nfMuted, fontSize: 9.3, height: 1.25)),
            ],
          ),
        ),
      );

  void _openSaved(BuildContext context) {
    c.go(3);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A mentett lookok megnyitva.')));
  }

  void _toggleNotifications(BuildContext context) {
    c.toggleNotifications();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(c.notificationsEnabled ? 'Értesítések bekapcsolva.' : 'Értesítések kikapcsolva.')));
  }

  void _showExports(BuildContext context) {
    if (c.savedPngPaths.isEmpty) {
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('PNG exportok'),
          content: const Text('Még nincs mentett PNG. A Try-On oldalon a „Look mentése” gombbal készíthetsz.'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Rendben'))],
        ),
      );
      return;
    }
    c.go(3);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A PNG-galéria megnyitva a Mentett oldalon. Érints meg egy képet a nagyításhoz.')));
  }

  void _previewPng(BuildContext context, String path) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Mentett NAILFIT look'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 520),
          child: Image.file(File(path), fit: BoxFit.contain),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Bezárás')),
          TextButton(
            onPressed: () async {
              await c.removePng(path);
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('PNG törlése'),
          ),
        ],
      ),
    );
  }

  void _privacy(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: nfCream,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Adatvédelem és törlés', style: TextStyle(fontFamily: 'serif', fontSize: 28, color: nfInk)),
              const SizedBox(height: 8),
              const Text('A kézfotó, a scan-adatok és a mentett PNG-k ezen az eszközön, az app saját tárhelyén vannak.', style: TextStyle(color: nfMuted, fontSize: 10.5, height: 1.35)),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () async {
                  await c.clearHandData();
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A tárolt kézfotó és scan-adatok törölve.')));
                },
                icon: const Icon(Icons.back_hand_outlined),
                label: const Text('Kézfotó + scan törlése'),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () {
                  c.clearSaved();
                  Navigator.pop(sheetContext);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('A kedvencek, mentett lookok és PNG-fájlok törlése elindult.')));
                },
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Mentések + PNG-k törlése'),
              ),
              const SizedBox(height: 6),
              TextButton(onPressed: () => Navigator.pop(sheetContext), child: const Text('Mégse')),
            ],
          ),
        ),
      ),
    );
  }

  void _showHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('NAILFIT súgó'),
        content: const Text('1. Készíts kézfotót.\n2. A Scan képen jelöld meg az 5 köröm közepét, vagy használd az Auto pontokat.\n3. Indítsd az elemzést.\n4. A Try-On oldalon finomítsd a formát, színt, finisht és hosszt.\n5. Mentsd PNG-be vagy oszd meg a lookot.\n\nA jelenlegi scanner vizuális becslés; milliméterpontos press-on méretezéshez később referencia/AR kalibráció szükséges.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Bezárás'))],
      ),
    );
  }

  Future<void> _editProfile(BuildContext context) async {
    String shape = c.preferredShape;
    String style = c.preferredStyle;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: nfCream,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setLocal) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Stílusprofil', style: TextStyle(fontFamily: 'serif', fontSize: 28, color: nfInk)),
              const SizedBox(height: 14),
              const Text('Kedvenc forma', style: TextStyle(color: nfMuted, fontSize: 10, fontWeight: FontWeight.w800)),
              const SizedBox(height: 7),
              Wrap(spacing: 6, children: ['Mandula','Ovális','Kocka','Coffin'].map((v) => ChoiceChip(label: Text(v), selected: shape == v, onSelected: (_) => setLocal(() => shape = v))).toList()),
              const SizedBox(height: 14),
              const Text('Kedvenc stílus', style: TextStyle(color: nfMuted, fontSize: 10, fontWeight: FontWeight.w800)),
              const SizedBox(height: 7),
              Wrap(spacing: 6, children: ['Nude','Francia','Minimal','Őszi','Merész'].map((v) => ChoiceChip(label: Text(v), selected: style == v, onSelected: (_) => setLocal(() => style = v))).toList()),
              const SizedBox(height: 16),
              FilledButton(onPressed: () { c.setProfile(shape: shape, style: style); Navigator.pop(sheetContext); }, style: FilledButton.styleFrom(backgroundColor: nfRose, foregroundColor: Colors.white), child: const Text('Profil mentése')),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: .72), borderRadius: BorderRadius.circular(99), border: Border.all(color: Colors.white)),
        child: Text(text, style: const TextStyle(fontSize: 9.5, color: nfInk)),
      );
}
