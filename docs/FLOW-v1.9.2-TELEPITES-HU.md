# AIMS FLOW v1.9.2 – offline munkanapok és riportok

## Mi változott

- A szerver megőrzi a bejelentkezett sofőr pihenőinek kezdetét, tervezett és tényleges végét.
- A napi és havi jelenléti riport külön mutatja a bruttó FLOW-időt, a rögzített pihenőt és a nettó FLOW-időt. A normaeltérés a nettó időből készül.
- Az átfedő bejegyzések nem duplázzák az időt. Az aznapi járműváltás egy munkanapnak számít. A teljes, hónaphatáron átnyúló heteket is figyeli.
- A korábbi, hiányzó pihenőadat és a nyitott munkanap jelölést kap. Ezekből nem jelenik meg ellenőrzött négyhavi átlag. A nettó FLOW-idő továbbra is a rögzített adatokból számított operatív érték.
- Az ECO nem rendel régi, ismeretlen utat a jármű mai sofőrjéhez; az eltérő sofőrökhöz tartozó, átfedő munkanapok közös szakaszát kihagyja. A hibás GPS-minta nem lesz a következő gyorsulás/fékezés alapja.
- ECO: A 90–100; B 75–90 alatt; C 55–75 alatt; D 55 alatt. Legalább 50 km, 45 perc mozgás, 80 érvényes szakasz és azonosított sofőr kell.
- Az Android hálózati értesítése a kapcsolat visszatérésekor elindítja a sorban álló GPS- és operatív adatok szinkronját. A 350 ms-os összevonás és a meglévő újrapróbálás megmarad.
- A riportműveletek hónaponként zároltak. A próbagenerálás már elküldött hónapra is futtatható, levélküldés nélkül.

## Telepítés a meglévő honlapra

Ez frissítőcsomag: a meglévő `inc/analytics.php`, `inc/portal.php`, adminbelépés és titkos konfiguráció szükséges hozzá. Ezeket nem helyettesíti.

1. Mentsd az érintett `admin/`, `api/aims-tracking/`, `api/aims-flow-auth-v2.php`, `api/aims-flow-login.php` fájlokat és az adatbázist. SQLite esetén készíts konzisztens adatbázis-mentést; aktív WAL mellett ne csak a `.sqlite` fájlt másold.
2. A csomag `admin/` és `api/` mappáját másold a megfelelő meglévő mappákra. A `data/`, feltöltött dokumentumok és az `aims-flow-config.php` maradjon meg.
3. Futtasd a tárhelyen: `php public_html/api/aims-tracking/preflight.php`. Nem módosít adatot és nem küld levelet.
4. Az első adatbázisnyitás létrehozza az új pihenőnaplót. Korábbi pihenőket nem talál ki és nem állít vissza.
5. A központi adminból ellenőrizd: `aims-flow-monthly-report.php`, napi bontás, CSV-export és `aims-flow-eco.php`. Kijelentkezve ezek nem lehetnek elérhetők.
6. Teszttelefonra a `v1.9.2 PILOT build32` APK kerüljön. A pilot külön alkalmazásazonosítót használ. A gyártási alkalmazást ez a csomag nem cseréli le.

## Havi riport próba és cron

Először csak generálj, levélküldés nélkül:

```bash
php public_html/api/aims-tracking/cron/monthly_driver_reports.php --month=2026-09 --dry-run
```

A pontos útvonalat a tárhelyhez kell igazítani. A napi cron 06:05-kor futhat:

```cron
5 6 * * * /usr/local/bin/php /home/CPANEL_USER/public_html/api/aims-tracking/cron/monthly_driver_reports.php >> /home/CPANEL_USER/aims-flow-monthly-report.log 2>&1
```

A script az előző hónapot dolgozza fel, normál esetben a hónap 1–3. napján. A cron időzónáját a tárhelyen ellenőrizni kell; a riport naptári határa Europe/Budapest. A `--force` újraküldésre való, ne kerüljön a napi cronba. A sikeres `mail()` azt jelzi, hogy a levelezőrendszer átvette a levelet, a kézbesítést nem bizonyítja.

Az adatkönyvtárhoz a webgyökéren kívüli `AIMS_TRACKING_DATA_DIR` ajánlott. Apache alatt a riportmappa `.htaccess` tiltást kap; Nginx vagy letiltott AllowOverride esetén a szerverkonfigurációban is tiltani kell a közvetlen HTTP-elérést. A letöltés az adminoldalon történjen.

## Valódi készüléken még ellenőrzendő

- Bejelentkezés, munkanap indítása, pihenő indítása/leállítása, munkanap vége: a riportban helyes bruttó/pihenő/nettó értékek.
- Mobiladat ki/be és repülő mód ki/be: a GPS-sor visszakapcsolódáskor elindul, a pontok egyszer érkeznek meg.
- Wi-Fi és mobilhálózat közötti váltás, háttérbe tett alkalmazás és zárolt képernyő.
- Bejelentkezést kérő Wi-Fi: a hálózat puszta megjelenése nem igazolja az internetet. Szerverhiba esetén a helyi sor megmarad.
- Sofőrváltás és járműváltás: a régi adatok tulajdonosa nem változhat meg.

## Ellenőrzések a forrásból

```bash
php server/aims-tracking/tests/report_regression_test.php
php server/aims-tracking/tests/eco_regression_test.php
flutter analyze
flutter test test/network_recovery_test.dart
```

A GitHub CI ezen felül valódi helyi HTTP-kérésekkel ellenőrzi a munkamenetet, a pihenőnapló sofőrazonosítását és más sofőr munkanapjának elutasítását. A telepítő ZIP csak a PHP- és riportellenőrzések sikeres lefutása után készül. A csomag `SOURCE_COMMIT.txt` és `SHA256SUMS.txt` fájlja rögzíti a forrást és a fájlellenőrző összegeket.

Android megvalósítási referencia: https://developer.android.com/develop/connectivity/network-ops/reading-network-state


## v1.9.2 – offline munkanapok

- A telefon több munkanap indítását és lezárását is megőrzi. Az új munkanap nem írja felül az előző, még vissza nem igazolt napot.
- A helyi napló sofőrönként és rendszámonként tárolja az állapotot. A küldés mindig az eredeti FLOW ID-val és rendszámmal történik; a munkamenethez tartozó másik járműre nem írja át a régi adatokat.
- A küldésre váró napok száma a munkanapkártyán pihenő közben is megjelenik.
- Járműváltás után a régi rendszám napjai megmaradnak, de csak az arra jogosult munkamenettel küldhetők el. Az új jármű munkamenete nem kap hozzáférést a régi járműhöz.
- A frissítés a régi naphoz tartozó helyi azonosítókat a következő be- vagy kijelentkezés előtt megőrzi. Ha a régi rendszám nem állapítható meg biztonságosan, a bejegyzést megtartja, de nem küldi másik jármű nevében.
- A helyi mentés és a küldési sor egy műveletben készül. Késői indítás-visszaigazolás nem nyitja újra a már lezárt munkanapot.
- A szerver az azonos indítás vagy lezárás ismétlését duplikált kilométer-bejegyzés nélkül fogadja. Az eltérő tartalmú ismétlést hibával visszautasítja.
- Érvénytelen offline lezárás nem hagy félkész nyitott napot a szerveren.

### Frissítés és telefonos próba

Először a szervercsomagot telepítsd; a v1.9.2 build32 PILOT APK-t az alábbi aláírási korlát figyelembevételével próbáld ki. A támogatott rendszer Android 7 / API 24 vagy újabb. A csomag továbbra is tesztkiadás, nem éles telepítés igazolása.

1. Tesztsofőrrel hálózat nélkül indíts és zárj két munkanapot. Az alkalmazás újraindítása után mindkettő maradjon a küldési sorban.
2. A hálózat visszatérésekor mindkét lezárás egyszer jelenjen meg a szerveren, az eredeti kezdő/záró kilométerrel.
3. Próbáld ki a lezárt munkanap utáni sofőrcserét ugyanazon a telefonon; az előző sofőr napjai nem jelenhetnek meg az új sofőr munkanapjaként.
4. Ellenőrizd a járműcserét: a régi nap eredeti rendszáma maradjon meg; új jogosultság nélkül maradjon függőben.
5. Munkanapzárás után hálózati hiba esetén is álljon le a GPS-követés.

Az automatizált tesztek nem helyettesítik a valódi telefonos próbát. A frissítés nem állítja vissza a korábbi verzió által már felülírt munkanapokat.


### Ellenőrzött PILOT-aláírási korlát

A build31 és a build32 azonos alkalmazásazonosítót (`hu.logisticaims.aims_flow_scanner.v190`), de eltérő Android Debug aláíró tanúsítványt használ. Emiatt a build32 nem telepíthető közvetlen frissítésként a build31 fölé.

- build31 tanúsítvány SHA-256: `171d5eeb8c9daf2b1b9fa5c7f9b31c6974137e2b6b2ac62044edaf39bb86ec4d`
- build32 tanúsítvány SHA-256: `df6c83e45441ba846f82b0623b19b3a6cd25af7b288177ed1ae86a045d019172`

A korábbi alkalmazást ne töröld, ha abban még el nem küldött munkanap, GPS-pont, dokumentum vagy más helyi adat van. Az eltávolítás törölheti az alkalmazás helyi adatait. A build32 APK-t egyelőre olyan külön teszttelefonon próbáld ki, amelyen nincs korábbi PILOT-telepítés.

Adatmegőrző helyben frissítéshez a build31 eredeti aláíró kulcsával kell új APK-t készíteni. Ez a kulcs a jelen munkakörnyezetben nem áll rendelkezésre. A kiadási folyamathoz tartós, védetten tárolt aláíró kulcs beállítása szükséges; a futásonként létrehozott debug kulcs nem biztosít frissítési folytonosságot.

A helyi munkanapnapló migrációja automatizált teszttel ellenőrzött, de a build31-ről közvetlen telefonos frissítés ezzel az APK-val nincs igazolva és az eltérő aláírás miatt blokkolt.
