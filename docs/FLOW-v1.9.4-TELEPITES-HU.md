# AIMS FLOW v1.9.4 build34 – GPS-adatmegőrzés és járműváltás

Ez a v1.9.3 továbbfejlesztése. Megtartja a havi ország- és jelenléti riportot, az ECO-értékelést, a Safety-ellenőrzéseket és az offline munkanapnaplót.

## Javított hibák

- Az új GPS-pontok rögzítéskor megőrzik a sofőr FLOW ID-ját, az eredeti rendszámot és a készülékazonosítót. Későbbi sofőr- vagy járműváltás nem címkézi át őket. A szerver is ellenőrzi a küldő tulajdonosát.
- Az idegen sofőrhöz vagy járműhöz tartozó sorok a telefonon maradnak, és nem akadályozzák az aktuális sofőr saját pontjait. Az eredeti fiókkal és járművel ismét belépve a küldés folytatható.
- A korábbi, FLOW ID nélkül mentett GPS-pontokat megőrzi, de nem rendeli találomra az aktuális sofőrhöz. Ezekről a GPS állapotszövege figyelmeztet; azonosításuk irodai egyeztetést igényel. A korábbi karanténfájlok tartalmát nem módosítja visszamenőleg.
- A helyi GPS-sor frissítése ideiglenes fájlba írással, lemezre ürítéssel, majd ugyanabban a könyvtárban történő átnevezéssel készül. A meglévő sorfájlt nem csonkítja a mentés elején. Mentési hibánál a korábbi sor olvasható marad.
- A 20 000 pontos korlát többé nem távolít el még vissza nem igazolt pontokat az aktív sorból. A helyigény a várakozó adatok mennyiségével nő.
- A visszaigazolás csak a ténylegesen elküldött bejegyzést távolítja el. A közben mentett új pontok és más sofőrök sorai megmaradnak.
- A GPS-azonosítók SHA-256 alapúak. A korábbi 32 bites azonosítónál reprodukált ütközés megszűnt. A szerver az azonos azonosítóval érkező, eltérő tartalmú pontot ütközésként utasítja el, nem nyugtázza sikeres ismétlésként.
- A sérült vagy véglegesen elutasított pontot a program megőrzi a helyi karanténfájlban, mielőtt kiveszi a küldési sorból. Hálózati és jogosultsági hibánál a pont a küldési sorban marad.
- Azonos telefon másik járműhöz rendelésekor az engedélyezett rendszám elsőbbséget kap a telefon régi járműkapcsolatával szemben.
- A késve érkező, régebbi GPS-pont megmarad az előzményekben, de nem forgatja vissza az élő jármű- és országállapotot, illetve nem indít régi helyzetből aktuális fuvaresényt. A régi országátlépési eseményeket ez a javítás nem számolja újra.
- Hibás naptári dátumot, relatív időpontot és öt percnél távolabbi jövőbeli időpontot a szerver elutasít.
- A belépés és nyomkövetés párhuzamos első indulása közös, sorosított készülékazonosító-létrehozást használ. Sérült azonosítófájlt nem ír felül új identitással.
- A munkanap lezárása után is újrapróbálható az offline GPS-sor küldése; ehhez nem kell újraindítani a helymeghatározást. Egy küldés időkorlátja a teljes válasz letöltésére is vonatkozik.

## Telepítés

Ez a meglévő Logistic-A.I.M.S. rendszer frissítőcsomagja; a meglévő adminbelépés, `inc/analytics.php`, `inc/portal.php` és titkos szerverkonfiguráció szükséges hozzá.

1. Készíts konzisztens mentést az adatbázisról és az érintett admin/API fájlokról. Aktív SQLite WAL esetén ne csak a `.sqlite` fájlt másold.
2. A csomag `admin/` tartalma a meglévő `public_html/admin/`, az `api/` tartalma a meglévő `public_html/api/` alá kerül.
3. A meglévő `data/`, feltöltött fotók és dokumentumok, valamint az `aims-flow-config.php` maradjon meg. A csomag adatbázist és titkos kulcsot nem tartalmaz.
4. Futtasd a tárhelyen: `php public_html/api/aims-tracking/preflight.php`.
5. Az első adatbázisnyitás hozzáadja a `points.flow_id` és `points.payload_hash` mezőket. A régi sorok tulajdonosát üresen hagyja; nem rendeli őket a jármű jelenlegi sofőrjéhez.
6. Először a szervert frissítsd, majd külön teszttelefonon próbáld ki az új APK-t. A támogatott rendszer Android 7 / API 24 vagy újabb.

## PILOT-aláírás és adatmegőrzés

A build34 továbbra is debug PILOT APK. A buildfolyamat futásonként létrehozott tesztkulcsot használ; a korábbi PILOT-telepítés fölé történő adatmegőrző frissítést ez nem biztosítja. Az alkalmazásazonosító változatlan: `hu.logisticaims.aims_flow_scanner.v190`.

A korábbi alkalmazást ne töröld, ha még el nem küldött munkanap, GPS-pont, fotó vagy dokumentum van benne. Az APK-t külön teszttelefonon próbáld ki. Helyben frissítéshez a korábbi kiadás eredeti aláírókulcsa szükséges; ez jelenleg nem áll rendelkezésre. A későbbi kiadásokhoz tartós, védetten tárolt aláírókulcsot kell beállítani.

## Ellenőrzés

A CI PHP-szintaxist, SQLite/HTTP-integrációt, a havi riportokat és az ECO-t, valamint a Flutter statikus ellenőrzését és tesztjeit futtatja. Az új tesztek valódi helyi fájlokkal vizsgálják a megszakadt sormentést, a párhuzamos mentést és visszaigazolást, több mint 20 000 pont megőrzését, a sofőr- és járműváltást és az ismert azonosítóütközést. A HTTP-próbák elkülönített adatbázison vizsgálják a feltöltést, a megváltoztatott ismétléseket, az időpontokat és a késve érkező pontok hatását.

Valódi telefonon még ellenőrizendő: offline GPS-rögzítés, alkalmazás újraindítása, hálózat visszatérése lezárt munkanappal, sofőr- és járműváltás, valamint háttérben futás. A telefonos próba és az éles telepítés nincs elvégezve.

A `SOURCE_COMMIT.txt` és `SHA256SUMS.txt` azonosítja a csomag forrását és fájljait. A korábbi Safety-, riport- és cron-leírások az `ELOZMENY-v1.9.3-TELEPITES-HU.md` és `ELOZMENY-v1.9.2-TELEPITES-HU.md` fájlokban találhatók.
