# AIMS honlap — V42 feltöltési javítás

A `AIMS-HONLAP-FLOW-V42-WEBROOT.zip` a V41 csomag feltöltendő fájljait tartalmazza közvetlenül a ZIP gyökerében. Az `index.html`, az `assets/`, a `flow/`, az `admin/` és az `api/` már nem két csomagmappa alatt található. A fájlok tartalma megegyezik a V41 ellenőrzött fájllistájával; a csomagolásból kimaradnak a nem listázott ideiglenes fájlok.

## Feltöltés meglévő honlapra

1. A tárhely fájlkezelőjében nyisd meg a `logistic-aims.hu` dokumentumgyökerét: azt a mappát, ahol a jelenlegi `index.html` és `assets` mappa van. Gyakran `public_html`, de a tárhely más nevet is használhat.
2. Készíts biztonsági másolatot a meglévő állapotról. Ne töröld vagy ürítsd ki a honlap mappáját.
3. Töltsd fel ide a **V42-WEBROOT.zip** fájlt, és válaszd a kibontást **ebbe a mappába**. Az azonos fájlneveket felül lehet írni, a mappákat össze kell fésülni. Ne válassz olyan szinkronizálást, amely a ZIP-ből hiányzó fájlokat törli.
4. Kibontás után a meglévő `index.html` helyén kell lennie az új `index.html` fájlnak. Ne maradjon köztes `AIMS-HONLAP-FLOW-V42`, `AIMS-HONLAP-FLOW-V41` vagy `FELTOLTENDO` mappa az útvonalban.
5. Frissítsd a főoldalt gyorsítótár nélkül, vagy nyisd meg privát ablakban. Ellenőrizd a `/flow/app/` oldalt és az `/assets/mobile-v41.css` fájlt is. Ezeknek elérhetőnek kell lenniük; a CSS-fájl megnyitásakor stíluskód jelenik meg.

**A ZIP feltöltése önmagában nem telepítés: ki is kell bontani.**

Ha a korábbi V41 ZIP már ki van bontva a tárhelyen, új letöltés helyett az `AIMS-HONLAP-FLOW-V41/FELTOLTENDO/` mappa **tartalmát** másolhatod a honlap dokumentumgyökerébe. Mappákat összefésülni, a meglévő állományokat megőrizni kell.

## Megőrzendő meglévő részek

Ez meglévő rendszer frissítése. Az `inc/`, a `partner/`, a korábbi `app/`, az adatbázisok, a feltöltött dokumentumok, a szerver konfigurációja és a meglévő gyökér `.htaccess` a tárhelyen maradnak. Ezeket a V41 forráscsomag nem tartalmazta teljes egészében. A V42 nem pótol törölt adatbázist vagy belépési konfigurációt, és nem állít be új tárhelyet.

## Ellenőrzés és a hiba behatárolása

2026. október 22-én az élő főoldal HTTP 200 választ adott és böngészőben megjelent. A `/flow/app/` és az `/assets/mobile-v41.css` HTTP 404 választ adott. A kiszolgált főoldal nem egyezett a V41 csomag főoldalával. Ez azt igazolja, hogy az új fájlok nem voltak elérhetők a várt útvonalon; a tárhelyen lévő tényleges kicsomagolási helyet szerverhozzáférés nélkül nem lehetett megállapítani.

Ha a helyes kibontás után is hibás az oldal, a pontos URL és a képernyőkép szükséges. HTTP 500 esetén a tárhely hibajegyzékének idevágó sorai segítenek; jelszót, munkamenetazonosítót vagy API-kulcsot ne küldj.

## Fejlesztői csomagolás

Az összeállítás után a `ci/package_website.py --assembled-dir <összeállítás> --output <új-zip>` parancs készíti el a közvetlenül kibontható csomagot. Minden bemeneti fájl méretét és SHA-256 lenyomatát ellenőrzi a `FAJLLISTA.json` alapján. Csak az ott felsorolt fájlokat csomagolja, olvasható 0644 fájljogosultságokkal. Hibás, hiányos vagy útvonalból kilépő bejegyzés esetén leáll.
