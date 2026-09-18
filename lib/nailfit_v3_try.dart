import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'nailfit_painters.dart';
import 'nailfit_v3_model.dart';
import 'nailfit_v3_widgets.dart';

class NailFitV3Try extends StatefulWidget {
  const NailFitV3Try({super.key, required this.c, required this.photo, required this.pick});
  final NailFitV3Controller c;
  final XFile? photo;
  final Future<void> Function(ImageSource) pick;

  @override
  State<NailFitV3Try> createState() => _NailFitV3TryState();
}

class _NailFitV3TryState extends State<NailFitV3Try> {
  final GlobalKey _exportKey = GlobalKey();
  bool _saving = false;

  NailFitV3Controller get c => widget.c;
  XFile? get photo => widget.photo;

  @override
  Widget build(BuildContext context) => nfBackground(
        SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              nfHeader(onAi: () => nfShowStylist(context, c), onNotifications: () => nfShowNotifications(context, c), notificationActive: c.notificationsEnabled && c.appointment != null),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    width: 43,
                    height: 43,
                    decoration: const BoxDecoration(color: Color(0xFFFBE4E7), shape: BoxShape.circle),
                    child: IconButton(onPressed: () => c.go(1), icon: const Icon(Icons.arrow_back_rounded, color: nfInk)),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('V I R T U Á L I S   P R Ó B A', style: TextStyle(color: nfRoseDark, fontSize: 8.5, letterSpacing: 1.4, fontWeight: FontWeight.w800)),
                        Text('Próbáld fel', style: TextStyle(fontFamily: 'serif', color: nfInk, fontSize: 39, height: 1)),
                        SizedBox(height: 4),
                        Text('Forma, szín, hossz és finish élőben a saját kézfotódon.', style: TextStyle(color: nfMuted, fontSize: 11)),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () => widget.pick(ImageSource.camera),
                    child: const CircleAvatar(radius: 22, backgroundColor: Color(0xFFFBE3E7), child: Icon(Icons.camera_alt_rounded, color: nfRoseDark)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _preview(),
              if (photo != null && c.points.length < 5) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: nfCard(const Color(0xFFFFEFEA)),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, color: nfRoseDark, size: 19),
                      const SizedBox(width: 9),
                      const Expanded(child: Text('A pontosabb Try-Onhoz menj vissza a Scan fülre és kalibráld az 5 körmöt.', style: TextStyle(color: nfMuted, fontSize: 9.5))),
                      TextButton(onPressed: () => c.go(1), child: const Text('Scan')),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _beforeAfter(),
              const SizedBox(height: 18),
              _fineTune(),
              const SizedBox(height: 20),
              nfSectionTitle('További stílusok kipróbálása', 'Összes stílus'),
              const SizedBox(height: 10),
              nfLookStrip(premiumLooks, c),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: _action(c.isCurrentFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded, c.isCurrentFavorite ? 'Kedvenc' : 'Kedvencekhez', _favorite)),
                  const SizedBox(width: 8),
                  Expanded(child: _action(Icons.bookmark_border_rounded, _saving ? 'Mentés…' : 'Look mentése', _saving ? () {} : _save)),
                  const SizedBox(width: 8),
                  Expanded(child: _action(Icons.ios_share_rounded, 'Megosztás', _saving ? () {} : _share)),
                ],
              ),
              const SizedBox(height: 18),
              _booking(context),
            ],
          ),
        ),
      );

  Widget _preview() {
    final match = c.currentMatchScore;
    return Container(
      height: 445,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(29),
        border: Border.all(color: Colors.white),
        boxShadow: const [BoxShadow(color: Color(0x20966973), blurRadius: 27, offset: Offset(0, 12))],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              key: _exportKey,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (photo != null)
                    Image.file(File(photo!.path), fit: BoxFit.cover)
                  else
                    nfPhoto(c.look.image, tint: c.look.color),
                  if (photo != null && c.showOverlay && c.points.isNotEmpty)
                    IgnorePointer(
                      child: CustomPaint(
                        painter: NailOverlayPainter(
                          points: List<Offset>.from(c.points),
                          sourceSize: c.photoWidth > 0 && c.photoHeight > 0 ? Size(c.photoWidth.toDouble(), c.photoHeight.toDouble()) : null,
                          color: c.color,
                          shape: c.shape,
                          length: c.length,
                          finish: c.finish,
                          calibration: false,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 14,
            top: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(color: const Color(0x853A2D2C), borderRadius: BorderRadius.circular(99)),
              child: Text(photo == null ? 'STUDIO DEMO' : (c.showOverlay ? 'TRY-ON AKTÍV' : 'EREDETI FOTÓ'), style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
            ),
          ),
          Positioned(
            right: 14,
            top: 14,
            child: InkWell(
              onTap: _favorite,
              child: Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: Icon(c.isCurrentFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: nfRoseDark),
              ),
            ),
          ),
          Positioned(
            left: 14,
            bottom: 14,
            child: Container(
              width: 190,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .92), borderRadius: BorderRadius.circular(19)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(c.look.name, style: const TextStyle(fontFamily: 'serif', fontSize: 19, color: nfInk, fontWeight: FontWeight.w600)),
                  Text('${c.shape} · ${_finishLabel(c.finish)} · ${_lengthLabel(c.length)}', style: const TextStyle(color: nfMuted, fontSize: 9)),
                ],
              ),
            ),
          ),
          Positioned(
            right: 14,
            bottom: 14,
            child: Container(
              width: 145,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xF7FBE7EA), borderRadius: BorderRadius.circular(19), border: Border.all(color: Colors.white)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Row(children: [Icon(Icons.auto_awesome_rounded, color: nfRose, size: 13), SizedBox(width: 4), Text('MATCH', style: TextStyle(color: nfRoseDark, fontSize: 7, fontWeight: FontWeight.w800))]),
                  const SizedBox(height: 7),
                  Text('$match% egyezés', style: const TextStyle(fontFamily: 'serif', fontSize: 21, color: nfInk)),
                  const SizedBox(height: 5),
                  Text(c.currentMatchReason, style: const TextStyle(color: nfMuted, fontSize: 8.2)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _beforeAfter() => Container(
        padding: const EdgeInsets.all(5),
        decoration: nfCard(),
        child: Row(
          children: [
            Expanded(child: _toggleSegment('Előtte', !c.showOverlay, () { if (c.showOverlay) c.toggleOverlay(); })),
            const SizedBox(width: 5),
            Expanded(child: _toggleSegment('Utána', c.showOverlay, () { if (!c.showOverlay) c.toggleOverlay(); })),
          ],
        ),
      );

  Widget _toggleSegment(String label, bool active, VoidCallback tap) => InkWell(
        onTap: tap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(color: active ? const Color(0xFFF8DCE2) : Colors.transparent, borderRadius: BorderRadius.circular(18)),
          child: Text(label, textAlign: TextAlign.center, style: TextStyle(color: active ? nfRoseDark : nfMuted, fontWeight: FontWeight.w800, fontSize: 10)),
        ),
      );

  Widget _fineTune() {
    const shapes = <String>['Mandula', 'Ovális', 'Kocka', 'Coffin'];
    const colors = <Color>[Color(0xFFD99CA6), Color(0xFFE7B8B1), Color(0xFFF1D5CC), Color(0xFFC7A18F), Color(0xFF6B1D2E), Color(0xFF2C1E22)];
    const finishes = <NailFinish>[NailFinish.glossy, NailFinish.french, NailFinish.glitter, NailFinish.chrome];

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: nfCard(const Color(0xFFFFF6F3)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Finomhangolás', style: TextStyle(fontFamily: 'serif', fontSize: 23, color: nfInk, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          const Text('FORMA', style: TextStyle(color: nfMuted, fontSize: 8, letterSpacing: 1, fontWeight: FontWeight.w800)),
          const SizedBox(height: 7),
          Wrap(spacing: 6, runSpacing: 6, children: shapes.map((shape) => ChoiceChip(label: Text(shape), selected: c.shape == shape, onSelected: (_) => c.setShape(shape), selectedColor: const Color(0xFFF4D4DA), labelStyle: const TextStyle(fontSize: 9.5))).toList()),
          const SizedBox(height: 13),
          const Text('SZÍN', style: TextStyle(color: nfMuted, fontSize: 8, letterSpacing: 1, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            children: colors.map((color) => InkWell(
              onTap: () => c.setColor(color),
              borderRadius: BorderRadius.circular(99),
              child: Container(width: 33, height: 33, decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: c.color.toARGB32() == color.toARGB32() ? nfRoseDark : Colors.white, width: c.color.toARGB32() == color.toARGB32() ? 3 : 1))),
            )).toList(),
          ),
          const SizedBox(height: 13),
          const Text('FINISH', style: TextStyle(color: nfMuted, fontSize: 8, letterSpacing: 1, fontWeight: FontWeight.w800)),
          const SizedBox(height: 7),
          Wrap(spacing: 6, runSpacing: 6, children: finishes.map((finish) => ChoiceChip(label: Text(_finishLabel(finish)), selected: c.finish == finish, onSelected: (_) => c.setFinish(finish), selectedColor: const Color(0xFFF4D4DA), labelStyle: const TextStyle(fontSize: 9.2))).toList()),
          const SizedBox(height: 13),
          Row(children: [const Text('HOSSZ', style: TextStyle(color: nfMuted, fontSize: 8, letterSpacing: 1, fontWeight: FontWeight.w800)), const Spacer(), Text(_lengthLabel(c.length), style: const TextStyle(color: nfRoseDark, fontSize: 9.5, fontWeight: FontWeight.w800))]),
          Slider(value: c.length, min: .68, max: 1.35, divisions: 14, activeColor: nfRose, onChanged: c.setLength),
        ],
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback tap) => InkWell(
        onTap: tap,
        borderRadius: BorderRadius.circular(19),
        child: Container(
          height: 62,
          decoration: nfCard(),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            CircleAvatar(radius: 17, backgroundColor: const Color(0xFFF9DBE1), child: Icon(icon, color: nfInk, size: 17)),
            const SizedBox(width: 7),
            Flexible(child: Text(label, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800))),
          ]),
        ),
      );

  Widget _booking(BuildContext context) => InkWell(
        onTap: () => _book(context),
        borderRadius: BorderRadius.circular(22),
        child: Container(
          height: 118,
          clipBehavior: Clip.antiAlias,
          decoration: nfCard(),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const CircleAvatar(radius: 20, backgroundColor: Color(0xFFF8DCE2), child: Icon(Icons.calendar_month_outlined, color: nfRoseDark, size: 20)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Szalonidőpont tervezése', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'serif', fontSize: 15, height: 1.05, color: nfInk, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text(c.appointment == null ? 'Ments egy időpontot ehhez a lookhoz.' : _appointmentLabel(c.appointment!), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: nfMuted, fontSize: 8.6, height: 1.2)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right_rounded, color: nfMuted, size: 19),
                    ],
                  ),
                ),
              ),
              SizedBox(width: 92, child: nfPhoto(nfHeroUrl)),
            ],
          ),
        ),
      );

  void _favorite() {
    c.toggleFavorite();
    _snack(c.isCurrentFavorite ? 'Hozzáadva a kedvencekhez.' : 'Eltávolítva a kedvencekből.');
  }

  Future<String?> _capturePng() async {
    if (_saving) return null;
    setState(() => _saving = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary = _exportKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('Preview not ready');
      final image = await boundary.toImage(pixelRatio: 2.2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) throw StateError('PNG encoding failed');
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/nailfit_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      c.rememberPng(file.path);
      return file.path;
    } catch (_) {
      _snack('A PNG mentés most nem sikerült.');
      return null;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    final path = await _capturePng();
    if (path != null) _snack('Look elmentve PNG-ként.');
  }

  Future<void> _share() async {
    final path = await _capturePng();
    if (path == null || !mounted) return;
    try {
      await SharePlus.instance.share(ShareParams(title: 'NAILFIT look', text: 'Ezt a NAILFIT lookot szeretném: ${c.look.name} · ${c.shape}', files: [XFile(path)]));
    } catch (_) {
      _snack('A megosztási lap nem nyitható meg ezen az eszközön.');
    }
  }

  Future<void> _book(BuildContext context) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
      initialDate: c.appointment?.isAfter(now) == true ? c.appointment! : now.add(const Duration(days: 7)),
      helpText: 'Szalonidőpont napja',
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(context: context, initialTime: c.appointment == null ? const TimeOfDay(hour: 10, minute: 0) : TimeOfDay.fromDateTime(c.appointment!));
    if (time == null) return;
    c.setAppointment(DateTime(date.year, date.month, date.day, time.hour, time.minute));
    _snack('Időpont elmentve a NAILFIT profilodba.');
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _finishLabel(NailFinish finish) => switch (finish) {
        NailFinish.glossy => 'Fényes',
        NailFinish.french => 'Francia',
        NailFinish.glitter => 'Csillámos',
        NailFinish.chrome => 'Króm',
      };

  String _lengthLabel(double value) => value < .82
      ? 'Rövid'
      : value < 1.02
          ? 'Közepes'
          : value < 1.20
              ? 'Hosszú'
              : 'Extra hosszú';

  String _appointmentLabel(DateTime value) => '${value.year}.${value.month.toString().padLeft(2, '0')}.${value.day.toString().padLeft(2, '0')} · ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}
