import 'package:flutter/material.dart';

const nfInk = Color(0xFF211719);
const nfMuted = Color(0xFF806F71);
const nfRose = Color(0xFFC96579);
const nfRoseDark = Color(0xFFA94C61);
const nfCream = Color(0xFFFFF9F6);
const nfLine = Color(0xFFEEDCDD);

const nfHeroUrl = 'https://images.unsplash.com/photo-1610992015762-45dca7fa3a85?auto=format&fit=crop&q=78&w=1400';
const nfAlmondUrl = 'https://images.unsplash.com/photo-1772983166346-93afb9898264?auto=format&fit=crop&q=78&w=1400';

class PremiumLook {
  const PremiumLook(this.name, this.subtitle, this.color, this.match, this.image, this.category);
  final String name;
  final String subtitle;
  final Color color;
  final int match;
  final String image;
  final String category;
}

const premiumLooks = <PremiumLook>[
  PremiumLook('Rózsás nude', 'Elegáns · Időtlen · Nőies', Color(0xFFD99CA6), 96, nfHeroUrl, 'Nude'),
  PremiumLook('Francia klasszikus', 'Tiszta · Finom · Klasszikus', Color(0xFFE7B8B1), 95, nfAlmondUrl, 'Francia'),
  PremiumLook('Finom csillogás', 'Puha fény · Alkalmi', Color(0xFFE6A4B2), 93, nfHeroUrl, 'Merész'),
  PremiumLook('Őszi elegancia', 'Mély · Elegáns · Karakteres', Color(0xFF6B1D2E), 91, nfAlmondUrl, 'Őszi'),
  PremiumLook('Letisztult bézs', 'Minimal · Természetes', Color(0xFFC7A18F), 90, nfHeroUrl, 'Minimal'),
];

class NailFitV3Controller extends ChangeNotifier {
  int tab = 0;
  PremiumLook look = premiumLooks.first;
  final Set<String> favorites = {};
  final List<PremiumLook> saved = [];

  void go(int value) { tab = value; notifyListeners(); }
  void select(PremiumLook value, {bool tryOn = true}) { look = value; if (tryOn) tab = 2; notifyListeners(); }
  void toggleFavorite([PremiumLook? value]) { final item = value ?? look; favorites.contains(item.name) ? favorites.remove(item.name) : favorites.add(item.name); notifyListeners(); }
  void saveCurrent() { if (!saved.any((e) => e.name == look.name)) saved.insert(0, look); notifyListeners(); }
}
