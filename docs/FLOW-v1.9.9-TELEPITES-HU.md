# AIMS FLOW v1.9.9 build39 – dokumentummentés és helyreállítás

Az 1.9.8 kiadás három feltárt hibájának javítása. Ehhez a kiadáshoz APK és új szervercsomag is tartozik. A szerveroldali képmentési javítás az APK telepítésével önmagában nem lép életbe.

## Javítások

- A GPS munkanapellenőrzése megkülönbözteti az igazoltan inaktív munkanapot az olvasási hibától. Átmeneti biztonságos-tárhelyhiba vagy sérült munkanapnapló nem állítja le az újraellenőrzés időzítőjét. A következő ellenőrzés ismét megpróbálja beolvasni az állapotot. Az ismeretlen állapot nem jogosít fel pontmentésre; igazolt kilépés, lejárt belépés vagy lezárt munkanap továbbra is leállítja a követést.
- A dokumentumszinkron közben érkező új kérés megmarad. Az aktuális kör után újabb kör indul, párhuzamos küldés nélkül. Az egy körben érkező kérések összevonódnak, a hívók megvárhatják a teljes feldolgozást. A megszüntetett szinkronkezelő nem indít új kört és nem küld késői képernyőértesítést.
- A Smart Document szerver mentése adatbázis-tranzakcióban történik. Egy kérés saját, véletlen nevű ideiglenes képfájlt ír, ellenőrzi a teljes írást és a lemezre ürítést, majd közzéteszi a képet. Visszagörgetés csak az adott kérés saját új képét törölheti. Párhuzamos ismétlések ugyanazt a dokumentumot kapják vissza.
- Új Smart Document rekordoknál a szerver a hitelesített sofőr azonosítóját és a tartalom SHA-256 lenyomatát menti. Azonos helyi azonosító eltérő tulajdonossal, járművel, képpel vagy metaadatokkal 409-es hibát kap. A mikroszekundum pontosságú rögzítési idő a lenyomat része. Sérült vagy hiányzó, már tárolt képre nem küld sikeres nyugtát.
- Az értesítés külön hibája nem érvényteleníti a már tartósan elmentett dokumentumot. Az ilyen értesítési hiba a szervernaplóban látszik; külön értesítési újraküldő ebben a kiadásban nincs.

## Régi dokumentumok

A meglévő adatbázis automatikusan két új mezővel bővül (`flow_id`, `payload_hash`), a meglévő rekordok és képek megmaradnak. A migráció nem talál ki régi tulajdonosokat. Ha egy korábban már szerverre került, de a telefonon még függő régi dokumentum tulajdonosa/tartalma nem igazolható az új mezőkkel, az ismétlés `document_owner_unverified` hibával helyben megmarad; irodai egyeztetés szükséges. A korábbi kliensoldali, tulajdonos nélküli függő dokumentumok továbbra is megőrződnek.

## Telepítés

1. Készíts mentést a meglévő `admin/`, `api/aims-tracking/` és adatkönyvtárról, valamint az adatbázisról.
2. A SERVER-DEPLOY csomag `admin/` fájljait a `public_html/admin/`, `api/` fájljait a `public_html/api/` megfelelő helyére másold. A meglévő `admin/inc/config.php`, `aims-flow-config.php` és `data/` maradjon meg. A csomag meglévő telepítés frissítése, nem önálló teljes céges honlap.
3. Szükséges PHP 8.1 vagy újabb, PDO SQLite, mbstring és írható adatkönyvtár. A szervercsomag nem tartalmaz adatbázist, ügyféladatokat, képeket vagy titkos konfigurációt.
4. Az új mezők az első backendkéréskor kerülnek be. A korábbi adatok törlése és kézi adatbáziscsere nem szükséges.
5. Az APK-t külön teszttelefonon ellenőrizd. A csomagazonosító `hu.logisticaims.aims_flow_scanner.v190`, minimum Android 7 / API 24.
6. Próbáld ki: munkanapindítás, képernyőzár, hálózatváltás, feltöltés közben új dokumentum mentése, ismételt feltöltés és sofőrváltás. Ellenőrizd az irodai oldalon a dokumentum képét is.

Az alap szerverbeállítások: [v1.9.4 útmutató](FLOW-v1.9.4-TELEPITES-HU.md). A szervercsomag éles telepítése nem történt meg ebben a munkakörnyezetben.

## Aláírás és telefonos próba

A tartós aláírókulcs beállítását a [v1.9.5 útmutató](FLOW-v1.9.5-TELEPITES-HU.md) írja le. Ideiglenes (`ephemeral-debug`) aláírásnál a régebbi PILOT fölé nem garantált az adatmegőrző frissítés. Függő adatok mellett ne töröld a régi appot és ne ürítsd az adatait.

A [v1.9.6 telefonos GPS- és akkumulátorpróbái](FLOW-v1.9.6-TELEPITES-HU.md) továbbra is szükségesek. Ebben a környezetben valódi telefonos mérést nem végeztünk. Kényszerített leállítás vagy telefon-újraindítás után az appot meg kell nyitni.

## Ellenőrzés

Célzott vizsgálatok: átmeneti munkamenet- és naplóolvasási hiba, hibás napló, lejárt/idegen munkamenet, munkanap lezárása a hiba után; új szinkronkérés folyamatban lévő küldés közben, hibás első kör utáni helyreállás, megszüntetés; részleges fájlírás, írási hiba, adatbázis-visszagörgetés, nyolc külön PHP-folyamat egyidejű ismétlése, valódi HTTP jogosultsági és változatlan tartalmú ismétlési próbák.

A kiadási eredmények a teljes CI és Android-fordítás befejezése után kerülnek ide. Műszaki háttér: [SQLite tranzakciók](https://www.sqlite.org/lang_transaction.html), [PHP fsync](https://www.php.net/manual/en/function.fsync.php), [PHP fwrite](https://www.php.net/manual/en/function.fwrite.php).
