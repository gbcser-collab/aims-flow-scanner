# AIMS FLOW v1.9.1 – riportok és hálózati helyreállítás

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
6. Teszttelefonra a `v1.9.1 PILOT build31` APK kerüljön. A pilot külön alkalmazásazonosítót használ. A gyártási alkalmazást ez a csomag nem cseréli le.

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
