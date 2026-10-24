# V44 – rendszám, hazautak és időszaki elszámolás

A V43 meglévő tárhelyre készült csomagjának bővítése. A kész ZIP tartalma közvetlenül a meglévő `public` mappába kerül, fájlfelülírással. A mappát nem szabad kiüríteni. Meglévő adatbázist, belépési rendszert és gyökérszintű szerverbeállítást nem tartalmaz és nem cserél. Az új SQLite-táblák az első adminmegnyitáskor létrejönnek.

## Használat

Az adminmenüben: **Riportok → Kilométer és árrés** (`admin/aims-flow-mileage.php`).

1. A „Sofőr lakóhelye rendszám szerint” részen válassz rendszámot, szükség esetén konkrét sofőrt, majd add meg a címet és a kezdőnapot. A térképen kattintással vagy a jármű otthon rögzített GPS-helyének átvételével pontosítsd a helyet. Ellenőrizd a GPS időpontját. A körzet alapértelmezetten 200 méter.
2. Sofőrcserénél vagy költözésnél új kezdőnappal ments. A korábbi lakóhely érvényessége lezárul. Az utolsó mentett kezdőnap újbóli használata a legutóbbi adat javítása; a módosítás előtti érték naplóban megmarad.
3. A „Megbízási kilométer és bevétel” részen add meg a megbízás kilométerét és az ügyféltől kapott nettó EUR-összeget. Az üres érték ismeretlen; a 0 ténylegesen nulla. A teljesítés napja alapértelmezetten a lezárt utolsó lerakó napja, de kézzel pontosítható. A sofőr is megadható, ha a korabeli adatokból nem azonosítható.
4. Válassz hónapot, egy napot vagy tetszőleges kezdő–záró dátumot. A zárónapot is beleértjük, budapesti idő szerint. A „Ma”, „Tegnap”, „Utolsó 3 nap”, „Ez a hónap” és „Előző hónap” gombok gyorsítják a szűrést. Rendszámra és sofőrre külön is szűrhetsz.
5. Az összesítő, a napi bontás és a hazautak külön CSV-ként letölthetők. A nyomtatási nézet PDF-be menthető a böngészőből.

## Számítás

- Megtett kilométer: a rögzített, minőségszűrt GPS-szakaszok hossza. GPS-ből számított becslés, nem hitelesített kilométeróra-mérés.
- Hazaút: a legutóbbi, teljesített fuvar utolsó lezárt lerakójától a lakóhely körzetében észlelt első GPS-pontig vezető út. A hazaérkezést legalább két megfelelő pontnak, legalább két percig a körzetben maradásnak kell megerősítenie. Új felrakó, sofőr-/eszközváltás, nem teljesített rakomány, rossz GPS, hiányzó lerakói kiindulópont vagy 48 órán túli szakasz esetén nincs bizonytalan automatikus levonás.
- Korrigált km = megtett GPS-km − igazolt hazaút-km.
- Bruttó eltérés = megtett GPS-km − megbízás szerinti km.
- Korrigált eltérés = korrigált km − megbízás szerinti km.
- Önköltség = az összes megtett GPS-km × **0,30 EUR**. A hazautak költsége is szerepel. Üzemanyagot, útdíjat és más költséget nem adunk hozzá még egyszer.
- Árrés = ismert nettó EUR-bevétel − önköltség. Hiányzó bevétel vagy ellenőrizendő GPS esetén nem jelenik meg lezárt árrés.
- A megbízási km és bevétel a teljesítés napjára, a GPS-km a megtétel napjára kerül. A folyamatban lévő, még nem teljesített fuvar bevétele ezért még nem része a riportnak.
- A nap- vagy hónaphatáron átnyúló GPS-szakaszokat időarányosan bontjuk. A teljes hazaút és a kiválasztott időszakra jutó része külön látható.

A hiányos GPS-szakaszokat nem töltjük ki légvonalból vagy tervezett útvonallal. A hibás pontok, tíz percnél hosszabb mozgási adathiányok és irreális ugrások ellenőrzési jelzést kapnak. A lezárt, egy napon belüli munkanap km-óra-különbségét kontrollként vetjük össze a GPS-szel; jelentős eltérésnél az árrés nem lezárt.

Az országidő-, jelenléti és külföldi tartózkodási riport kezdő–záró dátummal is kérhető; az ECO-riport meglévő dátumszűrése továbbra is elérhető. Részidőszakos jelenléti riportban nem állítunk teljes havi normát vagy négyhavi átlagot. A meglévő automatikus havi e-mail továbbra is a teljes hónapos országidő- és jelenléti csatolmányokat küldi; egyedi időszak CSV-ként exportálható.

## Működés és ellenőrzés

A hazautak felismerése a riport megnyitásakor a tárolt GPS-adatokból történik; nem kér új telefonos mérést, nincs hozzá külön cron vagy APK-csere. A korábban hiányzó vagy később beérkező pontokkal a riport újra számolható. Ugyanaz a pont vagy hazaút nem számítódik kétszer.

A lakóhelyek, nettó bevételek és önköltségek adminadatok. A bevételi adat külön táblába kerül, és nem jelenik meg a sofőrnek visszaadott fuvaradatokban. A mentéseket adminhitelesítés, CSRF-védelem, adatellenőrzés, tranzakció és változásnapló védi. A CSV-kben a szöveges képletkezdeteket semlegesítjük.

Ellenőrzések: PHP/SQLite számítási regressziók; valós HTTP-mentés, jogosultság és export; adminoldalak renderelése; WebKit mobil-, tablet- és asztali nézet, térképi helyválasztás és háromnapos szűrő; meglévő nyomkövetési, jelenléti és Flutter regressziók.

Az éles tárhely adataival és tényleges sofőrútvonallal külön üzempróba szükséges. A fejlesztés nem tölt fel automatikusan a tárhelyre.
