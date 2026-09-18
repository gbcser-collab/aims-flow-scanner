import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'nailfit_painters.dart';
import 'nailfit_v3_model.dart';
import 'nailfit_v3_widgets.dart';

class NailFitV3Scan extends StatelessWidget {
  const NailFitV3Scan({super.key, required this.c, required this.photo, required this.pick});
  final NailFitV3Controller c;
  final XFile? photo;
  final Future<void> Function(ImageSource) pick;

  @override
  Widget build(BuildContext context) {
    final result = c.scan;
    return nfBackground(
      SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            nfHeader(onAi: () => nfShowStylist(context, c), onNotifications: () => nfShowNotifications(context, c), notificationActive: c.notificationsEnabled && c.appointment != null),
            const SizedBox(height: 22),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Kéz szkennelése', style: TextStyle(fontFamily: 'serif', fontSize: 37, color: nfInk, height: 1)),
                      SizedBox(height: 8),
                      Text('Fotó + 5 pontos körömkalibráció. A pontokat a körmök közepére tedd.', style: TextStyle(color: nfMuted, fontSize: 12, height: 1.35)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _progress(),
              ],
            ),
            const SizedBox(height: 16),
            _preview(context),
            const SizedBox(height: 12),
            _calibrationToolbar(context),
            const SizedBox(height: 14),
            _qualityCard(result),
            const SizedBox(height: 12),
            _feature('Bőrtónus', result == null ? 'Fotóelemzés után' : '${result.tone}, ${result.undertone}', Icons.circle),
            _feature('Kézforma', result?.handShape ?? '5 pont után pontosabb becslés', Icons.back_hand_outlined),
            _feature('Try-On skála', result?.nailBed ?? '5 pontos kalibráció után', Icons.water_drop_outlined),
            _feature('Ajánlott forma', result?.recommendedShape ?? c.preferredShape, Icons.auto_awesome_rounded),
            const SizedBox(height: 12),
            _analysis(result),
            const SizedBox(height: 20),
            nfSectionTitle('Ajánlott stílusok neked', 'Összes'),
            const SizedBox(height: 10),
            nfLookStrip(_recommended(result), c),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(child: nfPrimary(Icons.auto_awesome_rounded, c.analyzing ? 'Elemzés…' : 'Elemzés + Try-On', c.analyzing ? () {} : () => _runAnalysis(context))),
                const SizedBox(width: 9),
                Expanded(child: nfSecondary(Icons.camera_alt_outlined, 'Fotó újra', () => pick(ImageSource.camera))),
              ],
            ),
            const SizedBox(height: 9),
            nfSecondary(Icons.photo_library_outlined, 'Kép kiválasztása a galériából', () => pick(ImageSource.gallery)),
            const SizedBox(height: 12),
            const Text(
              'A szkennelés helyi képfeldolgozást és 5 pontos kalibrációt használ. A Smart pontok csak kiindulópontok: húzd őket pontosan a körmök közepére, vagy töröld/jelöld újra őket. Pontos press-on méretezéshez referencia-méret vagy AR kalibráció szükséges.',
              style: TextStyle(color: nfMuted, fontSize: 9.2, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }

  Widget _progress() {
    final value = photo == null
        ? .12
        : c.points.length < 5
            ? .48 + c.points.length * .07
            : c.scan == null
                ? .88
                : 1.0;
    final label = photo == null
        ? 'FOTÓ'
        : c.points.length < 5
            ? 'KALIBRÁCIÓ'
            : c.scan == null
                ? 'ELEMZÉS'
                : 'KÉSZ';
    return SizedBox(
      width: 88,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('${c.points.length}/5 pont', style: const TextStyle(color: nfRoseDark, fontWeight: FontWeight.w800, fontSize: 10)),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(value: value.clamp(0, 1), minHeight: 6, color: nfRose, backgroundColor: nfLine),
          ),
          const SizedBox(height: 5),
          Text(label, style: const TextStyle(color: nfMuted, fontSize: 7.8, letterSpacing: .9)),
        ],
      ),
    );
  }

  Widget _preview(BuildContext context) => Container(
        height: 430,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white),
          boxShadow: const [BoxShadow(color: Color(0x1B90636B), blurRadius: 24, offset: Offset(0, 10))],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: photo == null || c.points.length >= 5 || c.analyzing
                ? null
                : (details) => c.addPoint(details.localPosition, constraints.biggest),
            onPanStart: photo == null || c.points.isEmpty || c.analyzing
                ? null
                : (details) => c.beginPointDrag(details.localPosition, constraints.biggest),
            onPanUpdate: photo == null || c.points.isEmpty || c.analyzing
                ? null
                : (details) => c.updatePointDrag(details.localPosition, constraints.biggest),
            onPanEnd: photo == null ? null : (_) => c.endPointDrag(),
            onPanCancel: photo == null ? null : c.endPointDrag,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (photo != null)
                  Image.file(File(photo!.path), fit: BoxFit.cover)
                else
                  CustomPaint(
                    painter: DemoHandPainter(
                      color: c.color,
                      shape: c.shape,
                      length: c.length,
                      finish: c.finish,
                      scanPose: true,
                    ),
                  ),
                CustomPaint(painter: ScanOverlayPainter(complete: c.points.length == 5)),
                if (photo != null)
                  IgnorePointer(
                    child: CustomPaint(
                      painter: NailOverlayPainter(
                        points: List<Offset>.from(c.points),
                        sourceSize: c.photoWidth > 0 && c.photoHeight > 0 ? Size(c.photoWidth.toDouble(), c.photoHeight.toDouble()) : null,
                        color: c.color,
                        shape: c.shape,
                        length: c.length,
                        finish: c.finish,
                        calibration: true,
                      ),
                    ),
                  ),
                Positioned(
                  left: 15,
                  right: 15,
                  top: 15,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: const Color(0x81392E2C), borderRadius: BorderRadius.circular(99)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(photo == null ? Icons.camera_alt_rounded : Icons.touch_app_rounded, color: Colors.white, size: 16),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            photo == null ? 'Készíts vagy válassz kézfotót' : (c.points.length < 5 ? 'Következő: ${c.nextCalibrationFinger} · érintsd meg a köröm közepét' : 'Kalibráció kész · a pontokat húzással finomíthatod'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (photo == null)
                  Center(
                    child: FilledButton.icon(
                      onPressed: () => pick(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt_rounded),
                      label: const Text('Kéz fotózása'),
                      style: FilledButton.styleFrom(backgroundColor: nfRose, foregroundColor: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );

  Widget _calibrationToolbar(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: nfCard(),
        child: Row(
          children: [
            Expanded(
              child: _miniAction(
                Icons.auto_fix_high_rounded,
                'Smart pontok',
                photo == null ? null : () {
                  c.seedCalibration();
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(c.hasSmartCalibration
                        ? 'Képalapú kiindulópontok beállítva. Ellenőrizd mind az 5 pontot.'
                        : 'Biztos kézterületet nem találtam, ezért sablonpontokat tettem le. Jelöld újra kézzel.'),
                  ));
                },
              ),
            ),
            const SizedBox(width: 7),
            Expanded(child: _miniAction(Icons.undo_rounded, 'Utolsó törlése', c.points.isEmpty ? null : c.undoPoint)),
            const SizedBox(width: 7),
            Expanded(child: _miniAction(Icons.restart_alt_rounded, 'Nullázás', c.points.isEmpty ? null : c.clearPoints)),
          ],
        ),
      );

  Widget _miniAction(IconData icon, String label, VoidCallback? tap) => InkWell(
        onTap: tap,
        borderRadius: BorderRadius.circular(16),
        child: Opacity(
          opacity: tap == null ? .38 : 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Column(
              children: [
                Icon(icon, color: nfRoseDark, size: 20),
                const SizedBox(height: 4),
                Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 8.7, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      );

  Widget _qualityCard(ScanResult? result) {
    final score = result?.qualityScore ?? 0;
    final text = result == null ? (photo == null ? 'Nincs fotó' : 'Előzetes képelemzés folyamatban / indítható') : '${result.quality} · $score/100';
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: nfCard(const Color(0xFFFFF4F2)),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFFF8DCE2),
            child: Icon(score >= 70 ? Icons.check_circle_outline_rounded : Icons.light_mode_outlined, color: nfRoseDark, size: 21),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(child: Text('Fotóminőség', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800))),
                    if (result != null) Text(result.resolution, style: const TextStyle(color: nfMuted, fontSize: 7.8)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(text, style: const TextStyle(color: nfMuted, fontSize: 9.4)),
                if (result != null) ...[
                  const SizedBox(height: 3),
                  Text(result.hint, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: nfMuted, fontSize: 8.4, height: 1.2)),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(value: score / 100, minHeight: 5, color: nfRose, backgroundColor: nfLine),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _feature(String title, String sub, IconData icon) => Container(
        margin: const EdgeInsets.only(bottom: 7),
        padding: const EdgeInsets.all(11),
        decoration: nfCard(),
        child: Row(
          children: [
            CircleAvatar(radius: 18, backgroundColor: const Color(0xFFF6D8DE), child: Icon(icon, size: 17, color: nfRoseDark)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 10.5)),
                  Text(sub, style: const TextStyle(color: nfMuted, fontSize: 9.3)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _analysis(ScanResult? result) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFFFE7EA), Color(0xFFF6D6DB)]),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.analytics_outlined, color: nfRose, size: 15),
                SizedBox(width: 5),
                Text('SMART SCAN · HELYI BECSLÉS', style: TextStyle(color: nfRoseDark, fontSize: 8, letterSpacing: .8, fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              result == null ? 'Készíts fotót és kalibrálj.' : '${result.recommendedShape} forma ajánlott.',
              style: const TextStyle(fontFamily: 'serif', fontSize: 25, color: nfInk),
            ),
            const SizedBox(height: 6),
            Text(
              result == null
                  ? 'A rendszer ellenőrzi a fényt, kontrasztot és kézterületet, majd az 5 pontból becsli a kéz arányait.'
                  : '${result.tone}, ${result.undertone} tónusbecslés · ${result.handShape}. A javaslat vizuális segítség, nem milliméterpontos mérés.',
              style: const TextStyle(color: nfMuted, fontSize: 10, height: 1.35),
            ),
          ],
        ),
      );

  List<PremiumLook> _recommended(ScanResult? result) {
    if (result == null) return premiumLooks.take(3).toList();
    final exact = premiumLooks.where((e) => e.shape == result.recommendedShape).toList();
    return <PremiumLook>{...exact, ...premiumLooks}.take(3).toList();
  }

  Future<void> _runAnalysis(BuildContext context) async {
    if (photo == null) {
      await pick(ImageSource.camera);
      return;
    }
    if (c.points.length < 5) c.seedCalibration();
    final result = await c.analyzePhoto(photo!);
    if (!context.mounted || result == null) return;
    if (result.qualityScore < 54) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('A fotó minősége gyenge: ${result.hint}. A Try-On elindul, de érdemes új fotót készíteni.')));
    }
    c.go(2);
  }
}
