# AIMS FLOW v1.9.7 build37 – megszakítások és szinkron

Kliensfrissítés a v1.9.4 szerverhez. Az adaptív, munkanaphoz kötött háttérkövetés és az előző funkciók megmaradnak. Csomag: `hu.logisticaims.aims_flow_scanner.v190`, minimum Android 7 / API 24.

## Javítások

- A CMR csak ismert szerverállapot és dokumentumazonosító mellett kaphat feltöltött/jóváhagyott állapotot. Üres, HTML, hibás JSON, hiányos vagy más helyi dokumentumra vonatkozó válasz nem nyugta. A HTTP 200-ba csomagolt alkalmazáshiba is hiba marad.
- A régi eszköz/CMR API kéréseinél a határidő a válasz teljes letöltésére is vonatkozik; a kérés saját HTTP-kliense végül bezáródik.
- Hálózati hiba, túlterhelés vagy hibás nyugta után a CMR-küldési kör megáll. Nem próbálja végig ugyanazon hibás kapcsolaton az összes függő dokumentumot. Későbbi szinkron újrapróbálja a megőrzött sorból.
- Üres dokumentumsornál nincs eszközregisztrációs és státuszlekérő hálózati kör.
- A CMR és Smart Document feltöltési eredménye csak az eredetileg küldött, azóta változatlan helyi bejegyzést módosíthatja. Késői válasz nem támaszthat fel törölt CMR-t és nem írhat felül közben módosított adatot.
- A munkanaphoz tartozó GPS-indítás/leállítás a tartós helyi műveletek sorrendjében történik. A GPS indítás, helyreállítás, profilváltás és leállítás közös műveleti sorba került. Egy korábbi munkanap késői lezárása nem kapcsolja ki az időközben tartósan elindított új munkanap követését.
- A helyszolgáltatás-figyelő hibás vagy beragadt leállítása nem akadályozza a GPS leállításának, a helyi állapot mentésének és a natív állapot törlésének megkísérlését. A takarítás legfeljebb tíz másodpercig vár egy műveletre; hiba esetén az app jelzi, hogy a leállítás nem igazolható teljesen.
- A GPS-sor számlálója több helyi író mellett is frissül. Az új pontok mentése továbbra sem írja újra a teljes sor tartalmát.

## Ellenőrzés

Az új regressziós tesztek késleltetett feltöltéssel, kapcsolatvesztéssel, hibás nyugtával, párhuzamos szinkronnal, késleltetett GPS-indítással, hibás/beragadt leállítással és több soríróval vizsgálják a működést. A teljes CI és Android build eredménye az elkészült csomag ellenőrzése után kerül ide.

## Telepítés és telefonos próba

A release fordítás nem jelent automatikusan tartós aláírást. A nyilvános `.signing.json` tartalmazza az aláírás módját és a csomag ujjlenyomatát. `ephemeral-debug` esetén külön teszttelefon javasolt: más aláírású korábbi PILOT fölé az adatmegőrző frissítés nem garantált. **Függő adatok mellett a régi appot ne töröld, és ne ürítsd az adatait.** A tartós kulcs beállítása: [v1.9.5 útmutató](FLOW-v1.9.5-TELEPITES-HU.md#tartós-pilot-aláírás-beállítása).

A [v1.9.6 telefonos ellenőrzési táblázata](FLOW-v1.9.6-TELEPITES-HU.md#valódi-telefonos-átvétel) továbbra is szükséges. Ebben a környezetben nincs valódi telefon vagy fogyasztásmérés. Kényszerített leállítás és telefon-újraindítás után az appot meg kell nyitni. A GPS nem működik nulla energiafelhasználással; 100%-os folytonosságot vagy mérés nélküli fogyasztáscsökkenést nem állítunk.

Ellenőrzött API-háttér: [Dart stream leállítás](https://api.dart.dev/dart-async/StreamSubscription/cancel.html), [Dart HTTP kliens erőforrás-kezelés](https://pub.dev/documentation/http/latest/).
