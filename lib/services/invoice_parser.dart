[Reading 46 lines from start (total: 46 lines, 0 remaining)]

enum InvoiceCategory { fuel, tollVignette, parking, service, parts, other }

class InvoiceData {
  const InvoiceData({required this.category,this.vendor,this.date,this.totalAmount,this.currency,this.documentNumber,this.countryCode,this.liters,this.pricePerLiter,this.rawText='',this.confidence=0});
  final InvoiceCategory category; final String? vendor; final String? date; final double? totalAmount; final String? currency; final String? documentNumber; final String? countryCode; final double? liters; final double? pricePerLiter; final String rawText; final double confidence;
}

class InvoiceParser {
  const InvoiceParser();
  InvoiceData parse(String raw) {
    final text=raw.replaceAll('\r','\n'); final normalized=text.toLowerCase();
    final lines=text.split('\n').map((e)=>e.replaceAll(RegExp(r'\s+'),' ').trim()).where((e)=>e.isNotEmpty).toList();
    final scores=<InvoiceCategory,int>{
      InvoiceCategory.fuel:_score(normalized,const ['diesel','benzin','petrol','gasoil','fuel','tankstelle','töltőállomás','liter','litre','adblue','shell','omv','mol ','orlen','circle k']),
      InvoiceCategory.tollVignette:_score(normalized,const ['vignette','e-vignette','e-matrica','matrica','toll','maut','autobahn','autópálya','motorway','winieta','vignetta','vinieta','road toll','e-myto','e-toll','dars','asfinag']),
      InvoiceCategory.parking:_score(normalized,const ['parking','parkoló','parkolas','parkolás','parkhaus','parken','parkomat']),
      InvoiceCategory.service:_score(normalized,const ['service','szerviz','repair','javítás','werkstatt','garage','munkadíj','arbeitslohn','inspection']),
      InvoiceCategory.parts:_score(normalized,const ['alkatrész','spare part','parts','ersatzteil','autoteile','filter','brake','fék','oil filter','levegőszűrő']),
      InvoiceCategory.other:1,
    };
    final best=scores.entries.reduce((a,b)=>a.value>=b.value?a:b);
    final totals=RegExp(r'(?:grand\s*total|amount\s*due|total|összesen|fizetend[őo]|summe|gesamt|razem|celkem|suma)[^\d]{0,28}(\d{1,9}(?:[\s.,]\d{2})?)\s*(HUF|FT|EUR|€|PLN|CZK|RON|CHF|GBP|£|DKK|SEK|NOK)?',caseSensitive:false).allMatches(text).toList();
    final tm=totals.isEmpty?null:totals.last;
    final cm=RegExp(r'\b(EUR|HUF|PLN|CZK|RON|CHF|GBP|DKK|SEK|NOK)\b|€|£|\bFT\b',caseSensitive:false).firstMatch(text);
    final rc=(tm?.group(2)??cm?.group(0)??'').toUpperCase();
    final currency=rc=='FT'?'HUF':rc=='€'?'EUR':rc=='£'?'GBP':(rc.isEmpty?null:rc);
    final lm=RegExp(r'\b(\d{1,4}(?:[.,]\d{1,3})?)\s*(?:L|LITER|LITRE|LITR[ÓO]W?)\b',caseSensitive:false).firstMatch(text);
    final um=RegExp(r'(?:PRICE/L|UNIT PRICE|EGYS[ÉE]G[ÁA]R|PREIS/L|CENA/L)[^\d]{0,18}(\d{1,6}(?:[.,]\d{1,3})?)',caseSensitive:false).firstMatch(text);
    return InvoiceData(category:best.key,vendor:_vendor(lines),date:_date(text),totalAmount:_money(tm?.group(1)),currency:currency,documentNumber:_documentNumber(lines),countryCode:_country(text),liters:_number(lm?.group(1)),pricePerLiter:_number(um?.group(1)),rawText:raw,confidence:(0.45+(best.value.clamp(0,8)*0.065)).clamp(0.45,0.97).toDouble());
  }
  int _score(String text,List<String> words){var n=0;for(final w in words){if(text.contains(w))n+=w.length>7?2:1;}return n;}
  double? _number(String? v)=>v==null?null:double.tryParse(v.replaceAll(' ','').replaceAll(',','.'));
  double? _money(String? v){if(v==null)return null;var x=v.replaceAll(' ','');if(x.contains(',')&&x.contains('.')){if(x.lastIndexOf(',')>x.lastIndexOf('.'))x=x.replaceAll('.','').replaceAll(',','.');else x=x.replaceAll(',','');}else{x=x.replaceAll(',','.');}return double.tryParse(x);}
  String? _date(String raw){
    final ps=[RegExp(r'\b20\d{2}[./-](?:0?[1-9]|1[0-2])[./-](?:0?[1-9]|[12]\d|3[01])\b'),RegExp(r'\b(?:0?[1-9]|[12]\d|3[01])[./-](?:0?[1-9]|1[0-2])[./-](?:20)?\d{2}\b')];
    for(final p in ps){final m=p.firstMatch(raw);if(m==null)continue;final a=m.group(0)!.split(RegExp(r'[./-]'));if(a[0].length==4)return a[0]+'-'+a[1].padLeft(2,'0')+'-'+a[2].padLeft(2,'0');var y=a[2];if(y.length==2)y='20'+y;return y+'-'+a[1].padLeft(2,'0')+'-'+a[0].padLeft(2,'0');}return null;
  }
  String? _vendor(List<String> lines){for(final line in lines.take(10)){final l=line.toLowerCase();if(line.length<3||line.length>100||RegExp(r'^\d').hasMatch(line))continue;if(RegExp(r'\b(invoice|receipt|nyugta|számla|rechnung|faktura|paragon|total|összesen|datum|date)\b',caseSensitive:false).hasMatch(l))continue;return line;}return null;}
  String? _documentNumber(List<String> lines){const labels=['invoice no','invoice number','számlaszám','szamlaszam','bizonylat szám','receipt no','receipt nr','rechnung nr','rechnungsnummer','faktura nr','document no','transaction no'];for(final line in lines){final lower=line.toLowerCase();for(final label in labels){final i=lower.indexOf(label);if(i<0)continue;final value=line.substring(i+label.length).replaceFirst(RegExp(r'^[\s:;#.-]+'),'').trim();if(value.length>=2)return value.length>80?value.substring(0,80):value;}}return null;}
  String? _country(String raw){final m=RegExp(r'\b(AT|BE|BG|HR|CY|CZ|DE|DK|EE|ES|FI|FR|GR|HU|IE|IT|LT|LU|LV|MT|NL|PL|PT|RO|SE|SI|SK|CH|GB)\b',caseSensitive:false).firstMatch(raw);return m?.group(1)?.toUpperCase();}
}

extension InvoiceCategoryLabel on InvoiceCategory {
  String get wire=>switch(this){InvoiceCategory.fuel=>'fuel',InvoiceCategory.tollVignette=>'toll_vignette',InvoiceCategory.parking=>'parking',InvoiceCategory.service=>'service',InvoiceCategory.parts=>'parts',InvoiceCategory.other=>'other'};
  String get hu=>switch(this){InvoiceCategory.fuel=>'Üzemanyag',InvoiceCategory.tollVignette=>'Útdíj / matrica',InvoiceCategory.parking=>'Parkolás',InvoiceCategory.service=>'Szerviz',InvoiceCategory.parts=>'Alkatrész',InvoiceCategory.other=>'Egyéb'};
}

[executed on device: GABOR-PC (4f5060cc-3a10-4200-947d-55b7a0fc1e22)]