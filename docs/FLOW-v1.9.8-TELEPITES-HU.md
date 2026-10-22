# AIMS FLOW v1.9.8 build38 – visszatérés és dokumentumküldés

Kliensfrissítés a v1.9.4 szerverhez. A meglévő háttérkövetés, munkanapok, Safety, riportok és ECO funkciók megmaradnak. Csomagazonosító: `hu.logisticaims.aims_flow_scanner.v190`, minimum Android 7 / API 24.

## Javítások

- Alkalmazás-visszatéréskor a sofőrhöz kötött automatikus frissítések és időzítők csak a helyi belépés ellenőrzése után indulnak. A háttérbe lépés érvényteleníti a még folyamatban lévő ellenőrzést; egy későn visszaérő olvasás nem indíthatja újra az előtéri feladatokat.
- A helyreállítás külön műveletei ismét ellenőrzik a belépést. Megváltozott sofőr, rendszám vagy token esetén a régi képernyő a belépéshez tér vissza. Átmeneti biztonságos-tárhelyhiba felfüggeszti a kéréseket, de nem törli a munkamenetet; későbbi ellenőrzés helyreállíthatja a frissítést.
- Hálózat-visszatéréskor a dokumentumsor is kap szinkronkísérletet, háttérben is. Minden küldési csatorna a saját hitelesítését használja.
- A régi CMR eszköz-API és a FLOW-belépéses Smart Document külön küldési kört kapott. A CMR jóváhagyási hibája, beragadt kérése vagy sérült helyi indexe nem akadályozza a Smart Documentet, és a Smart Document indexhibája sem akadályozza a CMR-t.
- Üres Smart Document-sor esetén nincs belépésolvasás, üres CMR-sor esetén nincs régi eszközregisztrációs hálózati kérés. Smart-only küldés nem hívja a régi CMR eszköz-API-t.
- A Smart Scanner a fotózás elején rögzíti a FLOW ID-t és a rendszámot. A Smart Document ezeket tartósan megőrzi. Új bejegyzések azonosítója véletlen összetevőt is kap, a későbbi ismétlések ugyanazt az eredeti azonosítót használják.
- Idegen sofőr vagy jármű dokumentuma nem küldhető az új belépéssel. A régi, tulajdonos nélkül mentett és a rendszám nélküli rekordok megmaradnak: a szinkronrészletek külön mutatják az azonosítatlan és másik sofőrhöz/járműhöz tartozó darabszámot. Tulajdonost nem találunk ki; a régi rekordok rendezéséhez irodai segítség szükséges.
- A Smart Document a kérés előtt és a válasz után is ellenőrzi, hogy ugyanaz a munkamenet él-e. Hiányos vagy idegen dokumentumra vonatkozó válasz nem nyugtázhatja a helyi dokumentumot.
- A feltöltés teljes válaszára határidő vonatkozik, és a HTTP-kliens bezáródik. Egy küldési körben dokumentumonként egy hálózati próbálkozás van; átmeneti hiba után a későbbi kör próbálkozik újra. 12 MiB fölötti képet az app már a hálózati kódolás előtt elutasít.
- Sikeresen elmentett dokumentumnál a számláló frissítésének külön hibája nem mutat többé megtévesztő mentési hibát.

A tulajdonosi védelem ebben a kiadásban kliensoldali; a szerver végpontjai és telepítőcsomagja nem változtak.

## Ellenőrzés

Új tesztek vizsgálják a háttérbe lépés közben befejeződő belépésellenőrzést, fiók- és rendszámváltást, átmeneti tárhelyhibát, egymástól független dokumentumküldést, sérült naplókat, változó munkamenetet, hibás nyugtát és beragadt HTTP-választ. A teljes [CI-futás](https://github.com/gbcser-collab/aims-flow-scanner/actions/runs/39758993549) sikeres: **165 Flutter-teszt 30 fájlban**, köztük **20 új regressziós teszt**; **10 aláírási teszt**; hibamentes statikus elemzés. A PHP/SQLite és valós HTTP jogosultsági, GPS-visszajátszási, munkanap-, Safety-, havi riport-, DST- és ECO-vizsgálatok is sikeresek. Ellenőrzött forráscommit: `e704e8bbc6f02441f4254149c863dc2140094993`.

## Telefonos átvétel és telepítés

A [v1.9.6 telefonos követési próbái](FLOW-v1.9.6-TELEPITES-HU.md#valódi-telefonos-átvétel) továbbra is szükségesek. Ehhez a kiadáshoz külön próbáld ki a háttérből visszatérést, a Wi-Fi/mobilnet váltást és a két külön sofőrrel használt telefont. Az első sofőr függő dokumentuma ne kerüljön a második belépéséhez. Régi, tulajdonos nélküli Smart Document maradjon meg azonosításra váróként.

Valódi telefonos GPS- és fogyasztásmérés ebben a környezetben nem történt. Kényszerített leállítás vagy telefon-újraindítás után az appot meg kell nyitni. Nulla fogyasztást és teljes folytonossági garanciát nem állítunk.

A release fordítás és a tartós aláírás külön tulajdonság. `ephemeral-debug` aláírás esetén külön teszttelefonra telepíts: korábbi, más kulccsal aláírt PILOT fölé nem garantált az adatmegőrző frissítés. **Függő adatok mellett a régi appot ne töröld, és ne ürítsd az adatait.** A tartós kulcs beállítása: [v1.9.5 útmutató](FLOW-v1.9.5-TELEPITES-HU.md#tartós-pilot-aláírás-beállítása).

Hivatalos API-háttér: [Flutter életciklus](https://api.flutter.dev/flutter/dart-ui/AppLifecycleState.html), [Dart HTTP kliens](https://pub.dev/documentation/http/latest/http/Client-class.html).

## Átadott telepítő

Az [Android release build](https://github.com/gbcser-collab/aims-flow-scanner/actions/runs/39758993489) sikeres. A letöltött ZIP mérete és SHA-256 értéke egyezik a GitHub Actions műtermékével. Az APK ellenőrzőösszege és tanúsítványa egyezik a build nyugtájával. Ellenőrizve: csomagazonosító, verzió, buildszám, Android 7 minimum, nem hibakereshető alkalmazás, letiltott backup, location foreground service, hálózati jogosultságok és a két eredeti értesítési hang változatlan tartalma.

| Tulajdonság | Érték |
| --- | --- |
| Fájl | `AIMS-FLOW-v1.9.8-PILOT-build38.apk` |
| Méret | 98 738 151 bájt (98,7 MB) |
| SHA-256 | `6f515b2baddab7d4af9ff7f7fddc6c9675e02927d391a02d7e1f2315149a4c66` |
| Tanúsítvány SHA-256 | `3575e813c67e22dfddb84ded55933f88576cad5490d1d42433b261d9754af389` |
| Fordítás / aláírás | `release-pilot` / `ephemeral-debug` |

A tanúsítvány eltér a v1.9.7 PILOT tanúsítványától. Ez a csomag külön teszttelefonra telepíthető; éles terítés nem történt. A tartós, adatmegőrző frissítési csatornához az eredeti megőrzött aláírókulcs szükséges.
