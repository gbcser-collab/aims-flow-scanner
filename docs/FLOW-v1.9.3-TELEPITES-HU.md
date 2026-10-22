# AIMS FLOW v1.9.3 build33 – járműellenőrzés és GPS-leállítás

Ez a v1.9.2 továbbfejlesztése. Megtartja a havi ország- és jelenléti riportot, a pihenő/bruttó/nettó bontást, az ECO-értékelést, a hálózati helyreállítást és a többnapos offline munkanapnaplót.

## Javított hibák

- A Safety Check helyi listája több mint 30 még el nem küldött ellenőrzést is megőriz. Csak a már visszaigazolt előzmények száma korlátozott.
- Egy hiányzó fotó vagy elutasított ellenőrzés nem akadályozza a későbbi érvényes bejegyzések feltöltését. Az elutasított bejegyzés megmarad; hálózati vagy belépési hiba esetén a teljes küldés várakozik.
- A lassú feltöltés visszaigazolása az aktuális helyi naplóba kerül, így nem töröl közben mentett új bejegyzést. Egyszerre egy feltöltési menet dolgozik.
- Minden új ellenőrzés megőrzi a FLOW ID-t és az eredeti rendszámot. Másik sofőr vagy jármű munkamenete nem küldi el a régi bejegyzést. A sofőr csak saját, aktuális járművének előzményeit látja.
- A korábbi, sofőrazonosító nélkül mentett ellenőrzések megmaradnak, de nem kapnak találomra tulajdonost. A Safety előzményeknél külön szám jelzi őket; irodai egyeztetés szükséges.
- Az emlékeztető időzítése sofőrönként és járművenként külön tárolódik. Elavult, pontatlan vagy ismeretlen sebességű GPS-adat nem indít álló helyzetet igénylő ellenőrzési felszólítást.
- Mentés közben az ellenőrző űrlap mezői és fotógombjai zároltak. A mentett adatok független másolatot kapnak.
- Munkanapzáráskor a GPS leállítása megelőzi a feltöltést. A hálózati várakozás nem tartja aktívan a helymeghatározást. Egy korábban indított helyengedély-vizsgálat sem indíthatja újra a lezárt GPS-folyamatot.
- A szerver minden fotót ellenőriz, mielőtt adatot ment. A bejegyzés, a négy fotóhivatkozás, a kilométer-bejegyzés és a hibajelzés egy adatbázis-tranzakcióban készül.
- Hibás vagy félbeszakadt mentésnél a tranzakció visszaáll, és a próbálkozás során létrehozott fotófájlokat eltávolítja. Korábbi fájlt nem töröl.
- Az azonos ellenőrzés ismételt feltöltése nem duplázza a kilométer-bejegyzést és a hibajelzést. Megváltozott adatok vagy fotók esetén a szerver ütközést jelez; a korábbi ellenőrzést megőrzi.
- Az eltérő jármű vagy sofőr ellenőrzésazonosítójának újrafelhasználását elutasítja. A kettőspontot és aláhúzást tartalmazó különböző azonosítók sem kerülhetnek ugyanahhoz a fotófájlhoz.

## Telepítés

Ez a meglévő Logistic-A.I.M.S. rendszer frissítőcsomagja; a meglévő adminbelépés, `inc/analytics.php`, `inc/portal.php` és titkos szerverkonfiguráció szükséges hozzá.

1. Készíts konzisztens mentést az adatbázisról és az érintett admin/API fájlokról. Aktív SQLite WAL esetén ne csak a `.sqlite` fájlt másold.
2. A csomag `admin/` tartalma a meglévő `public_html/admin/`, az `api/` tartalma a meglévő `public_html/api/` alá kerül. Az új `api/aims-tracking/safety_check_store.php` is szükséges.
3. A meglévő `data/`, feltöltött fotók és dokumentumok, valamint az `aims-flow-config.php` maradjon meg. A csomag adatbázist és titkos kulcsot nem tartalmaz.
4. Futtasd a tárhelyen: `php public_html/api/aims-tracking/preflight.php`.
5. Az első adatbázisnyitás hozzáadja a `vehicle_safety_checks.flow_id` mezőt. A régi sorok tulajdonosát üresen hagyja; nem rendeli őket a jármű jelenlegi sofőrjéhez.
6. Először a szervert frissítsd, majd külön teszttelefonon próbáld ki az új APK-t. A támogatott rendszer Android 7 / API 24 vagy újabb.

## PILOT-aláírás és adatmegőrzés

A build33 továbbra is debug PILOT APK. A buildfolyamat futásonként létrehozott tesztkulcsot használ; a korábbi PILOT-telepítés fölé történő adatmegőrző frissítést ez nem biztosítja. Az alkalmazásazonosító változatlan: `hu.logisticaims.aims_flow_scanner.v190`.

A korábbi alkalmazást ne töröld, ha még el nem küldött munkanap, GPS-pont, fotó vagy dokumentum van benne. Az APK-t külön teszttelefonon próbáld ki. Helyben frissítéshez a korábbi kiadás eredeti aláírókulcsa szükséges; ez jelenleg nem áll rendelkezésre. A későbbi kiadásokhoz tartós, védetten tárolt aláírókulcsot kell beállítani.

## Ellenőrzés

A GitHub CI PHP-szintaxist, SQLite/HTTP-integrációt, a havi riportokat és az ECO-t, valamint a Flutter statikus ellenőrzését és tesztjeit futtatja. Az új tesztek valódi multipart fotófeltöltést, tulajdonosváltást, ismételt kéréseket, hibás negyedik fotót és a negyedik fájl mentési hibájának visszaállítását is vizsgálják. A tesztek elkülönített adatbázissal dolgoznak.

Valódi telefonon még ellenőrizendő: több offline Safety Check mentése, alkalmazás újraindítása, hálózat visszatérése, sofőr- és járműváltás, valamint munkanapzárás közben megszakadó kapcsolat. A telefonos próba és az éles telepítés nincs elvégezve.

Az új verzió a korábban már elveszett helyi ellenőrzéseket nem tudja visszaállítani. Korábbi, félkészen feltöltött szerveroldali ellenőrzésnél külön hibát jelez; azt nem egészíti ki bizonytalan eredetű fotókkal.

A `SOURCE_COMMIT.txt` és `SHA256SUMS.txt` azonosítja a csomag forrását és fájljait. A korábbi havi riport és cron telepítési leírása változatlanul a csomag `ELOZMENY-v1.9.2-TELEPITES-HU.md` fájljában található.
