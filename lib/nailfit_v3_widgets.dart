import 'package:flutter/material.dart';
import 'nailfit_v3_model.dart';

Widget nfBackground(Widget child) => DecoratedBox(
  decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFFCFA), Color(0xFFFFEEEB), Color(0xFFFFF9F6)])),
  child: child,
);

Widget nfHeader({VoidCallback? onAi, VoidCallback? onNotifications}) => Row(children: [
  const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [Text('NAIL', style: TextStyle(fontSize: 22, letterSpacing: 3.6, fontWeight: FontWeight.w500, color: nfInk)), Text('FIT', style: TextStyle(fontSize: 22, letterSpacing: 3.6, fontWeight: FontWeight.w500, color: nfRose))]),
    Text('B E A U T Y   M E E T S   Y O U', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 6.2, letterSpacing: 1.0, color: nfMuted)),
  ])),
  const SizedBox(width: 6),
  InkWell(
    onTap: onAi,
    borderRadius: BorderRadius.circular(99),
    child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), decoration: BoxDecoration(color: const Color(0xFFFBE4E8), borderRadius: BorderRadius.circular(99), border: Border.all(color: Colors.white)), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.auto_awesome_rounded, size: 13, color: nfRose), SizedBox(width: 4), Text('BEAUTY AI', style: TextStyle(fontSize: 8.2, letterSpacing: .8, color: nfRoseDark, fontWeight: FontWeight.w800))])),
  ),
  const SizedBox(width: 6),
  InkWell(
    onTap: onNotifications,
    borderRadius: BorderRadius.circular(99),
    child: Stack(children: [Container(width: 36, height: 36, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: const Icon(Icons.notifications_none_rounded, size: 20, color: nfInk)), const Positioned(right: 2, top: 2, child: CircleAvatar(radius: 4, backgroundColor: Color(0xFFD97C8F)))]),
  ),
]);

BoxDecoration nfCard([Color? color]) => BoxDecoration(color: color ?? Colors.white.withValues(alpha: .86), borderRadius: BorderRadius.circular(22), border: Border.all(color: Colors.white), boxShadow: const [BoxShadow(color: Color(0x109B6B74), blurRadius: 16, offset: Offset(0, 7))]);

Widget nfSectionTitle(String title, String? trailing, {VoidCallback? onTrailing}) => Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
  Expanded(child: Text(title, style: const TextStyle(fontFamily: 'serif', fontSize: 25, color: nfInk, fontWeight: FontWeight.w600, height: 1))),
  if (trailing != null)
    InkWell(
      onTap: onTrailing,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
        child: Text('$trailing  →', style: const TextStyle(color: nfRoseDark, fontSize: 10, fontWeight: FontWeight.w800)),
      ),
    ),
]);

Widget nfPhoto(String url, {BoxFit fit = BoxFit.cover, Color? tint}) => ColorFiltered(
  colorFilter: tint == null ? const ColorFilter.mode(Colors.transparent, BlendMode.dst) : ColorFilter.mode(tint.withValues(alpha: .10), BlendMode.softLight),
  child: Image.network(url, fit: fit, loadingBuilder: (_, child, p) => p == null ? child : nfPhotoFallback(), errorBuilder: (_, __, ___) => nfPhotoFallback()),
);

Widget nfPhotoFallback() => Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFF6D4D2), Color(0xFFD99D8A)])), child: const Center(child: Icon(Icons.back_hand_outlined, color: Colors.white70, size: 52)));

Widget nfLookCard(PremiumLook look, NailFitV3Controller c) {
  final active = c.look.name == look.name;
  return InkWell(onTap: () => c.select(look), borderRadius: BorderRadius.circular(19), child: AnimatedContainer(duration: const Duration(milliseconds: 180), width: 154, clipBehavior: Clip.antiAlias, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(19), border: Border.all(color: active ? nfRose : Colors.white, width: active ? 2 : 1), boxShadow: const [BoxShadow(color: Color(0x139E6D76), blurRadius: 14, offset: Offset(0, 7))]), child: Column(children: [Expanded(child: nfPhoto(look.image, tint: look.color)), Padding(padding: const EdgeInsets.fromLTRB(10, 8, 9, 9), child: Row(children: [Expanded(child: Text(look.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: nfInk))), Icon(c.favorites.contains(look.name) ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: nfRoseDark, size: 17)]))])));
}

Widget nfLookStrip(List<PremiumLook> data, NailFitV3Controller c) => SizedBox(height: 155, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: data.length, separatorBuilder: (_, __) => const SizedBox(width: 9), itemBuilder: (_, i) => nfLookCard(data[i], c)));

Widget nfQuick(IconData icon, String title, String sub, VoidCallback tap) => InkWell(onTap: tap, borderRadius: BorderRadius.circular(20), child: Container(height: 96, padding: const EdgeInsets.all(12), decoration: nfCard(), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Row(children: [CircleAvatar(radius: 18, backgroundColor: const Color(0xFFF8DCE1), child: Icon(icon, color: nfInk, size: 19)), const Spacer(), const Icon(Icons.chevron_right_rounded, color: nfMuted, size: 18)]), const SizedBox(height: 6), Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 10.5)), Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: nfMuted, fontSize: 8.5))])));

Widget nfPrimary(IconData icon, String label, VoidCallback tap) => FilledButton.icon(onPressed: tap, icon: Icon(icon, size: 18), label: Text(label), style: FilledButton.styleFrom(backgroundColor: nfRose, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23)), textStyle: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800)));
Widget nfSecondary(IconData icon, String label, VoidCallback tap) => OutlinedButton.icon(onPressed: tap, icon: Icon(icon, size: 18), label: Text(label), style: OutlinedButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: .8), foregroundColor: nfInk, side: const BorderSide(color: Colors.white), padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23)), textStyle: const TextStyle(fontSize: 9.8, fontWeight: FontWeight.w700)));
