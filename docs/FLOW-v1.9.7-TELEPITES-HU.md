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

Az új regressziós tesztek késleltetett feltöltéssel, kapcsolatvesztéssel, hibás nyugtával, párhuzamos szinkronnal, késleltetett GPS-indítással, hibás/beragadt leállítással és több soríróval vizsgálják a működést. A teljes [CI-futás](https://github.com/gbcser-collab/aims-flow-scanner/actions/runs/39754331915) sikeres: **145 Flutter-teszt 28 fájlban**, benne 18 új regresszió; **10 aláírási teszt**; hibamentes statikus elemzés. A PHP/SQLite és valós HTTP jogosultsági, GPS-visszajátszási, munkanap-, Safety-, havi riport-, DST- és ECO-vizsgálatok is sikeresek. Ellenőrzött forráscommit: `09cf3b4d4f4ce78426514733934d333560d4641f`.

## Telepítés és telefonos próba

A release fordítás nem jelent automatikusan tartós aláírást. A nyilvános `.signing.json` tartalmazza az aláírás módját és a csomag ujjlenyomatát. `ephemeral-debug` esetén külön teszttelefon javasolt: más aláírású korábbi PILOT fölé az adatmegőrző frissítés nem garantált. **Függő adatok mellett a régi appot ne töröld, és ne ürítsd az adatait.** A tartós kulcs beállítása: [v1.9.5 útmutató](FLOW-v1.9.5-TELEPITES-HU.md#tartós-pilot-aláírás-beállítása).

A [v1.9.6 telefonos ellenőrzési táblázata](FLOW-v1.9.6-TELEPITES-HU.md#valódi-telefonos-átvétel) továbbra is szükséges. Ebben a környezetben nincs valódi telefon vagy fogyasztásmérés. Kényszerített leállítás és telefon-újraindítás után az appot meg kell nyitni. A GPS nem működik nulla energiafelhasználással; 100%-os folytonosságot vagy mérés nélküli fogyasztáscsökkenést nem állítunk.

Ellenőrzött API-háttér: [Dart stream leállítás](https://api.dart.dev/dart-async/StreamSubscription/cancel.html), [Dart HTTP kliens erőforrás-kezelés](https://pub.dev/documentation/http/latest/).

## Ehhez a javításhoz tartozó telefonos esetek

| Próba | Elvárt eredmény |
| --- | --- |
| Feltöltés alatt megszakadó mobilnet, majd visszatérés | A CMR megmarad a sorban; hibás nyugta nem jelez sikert; új kapcsolatnál újrapróbálható |
| Munkanap lezárása és rövid időn belül új munkanap indítása | A régi művelet befejezése nem kapcsolja ki az új munkanap követését |
| Követési beállítás és alkalmazás-visszatérés munkanaplezárással egy időben | Nincs párhuzamos GPS-indítás/leállítás; lezárt munkanapnál nincs új pontgyűjtés |
| Dokumentum módosítása/törlése folyamatban lévő feltöltés alatt | A késői válasz nem írja vissza a régi helyi adatot |

Ezek a telefonos esetek még nincsenek helyszínen elvégezve. A dokumentum törlése a helyi példányra vonatkozik; már elindított vagy szerverre megérkezett feltöltést nem von vissza.

## Átadott és ellenőrzött telepítő

Az [Android release build](https://github.com/gbcser-collab/aims-flow-scanner/actions/runs/39754331856) sikeres. A letöltött ZIP mérete és SHA-256 értéke egyezik a GitHub Actions műtermékével. Az APK ellenőrzőösszege és tanúsítványa egyezik a build nyugtájával. Külön ellenőrizve a csomagazonosító, 1.9.7 / build37, Android 7 minimum, nem hibakereshető release alkalmazás, letiltott backup, location foreground service, hálózati jogosultságok és a két eredeti értesítési hang változatlan tartalma.

| Tulajdonság | Érték |
| --- | --- |
| Fájl | `AIMS-FLOW-v1.9.7-PILOT-build37.apk` |
| Méret | 98 738 151 bájt (98,7 MB) |
| SHA-256 | `aa4666b49eef35cf12996f8a3685c9b382098fd0bc7df4c4e4840e821f71b689` |
| Tanúsítvány SHA-256 | `8f09b507ae81a976631c643177b5328b69cfe5cba433ff81f4fe1a29eace8b4d` |
| Fordítás / aláírás | `release-pilot` / `ephemeral-debug` |

A tanúsítvány eltér a v1.9.6 PILOT tanúsítványától. A korábbi telepítés fölé történő adatmegőrző frissítéshez az eredeti aláírókulcs szükséges; ezt az ellenőrzött csomagot külön teszttelefonra szánjuk. Éles terítés nem történt.
