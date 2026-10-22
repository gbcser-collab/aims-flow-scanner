# V41 – Honlap + admin + AIMS FLOW

A csomag a meglévő logistic-aims.hu frissítése: V39 nyilvános honlap, V40 teljes admin és FLOW 1.9.10 / Android build 40. A FLOW PHP háttérrendszere az ellenőrzött 1.9.9 szerverkiadás; a 1.9.10 az iOS-klienst és a honlap-integrációt bővíti.

**Feltöltés:** a `FELTOLTENDO` mappa TARTALMÁT másold a meglévő webgyökérbe (általában `public_html`). Az `index.html` közvetlenül a webgyökérbe kerüljön. Ne hozz létre `public_html/FELTOLTENDO` vagy `admin/admin` mappát.

## Mi van benne?

- A teljes nyilvános honlap, az eredeti arculattal, termékoldalakkal, űrlapokkal és jogi oldalakkal.
- A teljes rendelkezésre álló admincsomag, PDF/OCR-motorokkal. A részletes, többmegállós fuvarfeladás megmaradt.
- A friss FLOW API, offline GPS- és dokumentumszinkron, sofőr-hozzáféréskezelés.
- A FLOW-központ és a havi riport frissítése: bruttó idő, rögzített pihenő, nettó FLOW-idő, napi bontás, nyitott/hiányos munkanap jelzése; riportküldési zárolás.
- A közös `/flow/app/` belépési és letöltési oldal, benne az új Android APK-val.
- iPhone/Safari űrlapméretek és képernyőszéli igazítások. A dekoratív animációk korábbi mobilos takarékos kezelése megmaradt.

## Mely meglévő részek szükségesek?

Ez **nem üres tárhelyre szánt, teljes új telepítő**. A kapott forrásokból hiányzik az éles `inc/`, a külön `partner/` és `app/` portál, a hitelesítési konfiguráció és az adatbázisok. Ezeket a már működő tárhelyről használja.

Őrizd meg:

- a teljes `inc/`, `partner/`, `app/` könyvtárat;
- az eredeti gyökér `.htaccess`-t és benne a működő API-átirányításokat;
- az `api/device/enroll`, `api/device/status`, `api/cmr/sync` régi CMR-szolgáltatás útvonalait és működő háttérrendszerét; a forrásuk nem része ennek a csomagnak;
- a webgyökér FELETT lévő `aims-flow-config.php` titkos beállításait;
- az adatbázisokat, feltöltött dokumentumokat, képeket és szerveroldali privát adatkönyvtárakat.

**Ne használj olyan FTP-szinkront, amely törli a csomagból hiányzó szerverfájlokat.** A `data/.htaccess` kizárólag hozzáférésvédelmet ad; a meglévő `data/` teljes tartalma maradjon meg.

## Telepítési sorrend

1. Készíts visszaállítható mentést a honlapról, adminról, API-ról, privát konfigurációról és a FLOW SQLite-adatbázisról. Élő SQLite esetén konzisztens adatbázis-mentést használj; az aktív WAL-fájlt nem lehet figyelmen kívül hagyni.
2. Próbakörnyezetben ellenőrizd a meglévő függőségeket és útvonalakat. A `DOKUMENTACIO/check-host.php` CLI-ből fut: `php check-host.php /teljes/ut/public_html`. Nem hoz létre adatbázist, nem írja ki a titkokat, és nem teszteli a belépést.
3. Töltsd fel a `FELTOLTENDO` tartalmát a meglévő webgyökérbe, kizárólag fájlok hozzáadásával/felülírásával. A készülékek a logistic-aims.hu domainhez kapcsolódnak; más domainhez külön kliensbeállítás és új build kell.
4. A gyökér `.htaccess` nincs az automatikusan felülírandó fájlok között. A `SZERVERBEALLITAS/honlap-apache-minta.conf` biztonsági szabályait a működő átirányítások megtartásával vezesd össze. A mellékelt `api/aims-tracking/.htaccess` és `data/.htaccess` Apache 2.4-et és engedélyezett felülbírálást igényel. Nginx esetén a `/api/aims-tracking/data/` URL teljes kiszolgálását tiltsd le, a PHP-hoz használt belső fájlolvasás maradjon engedélyezett.
5. A működő `AIMS_TRACKING_DATA_DIR` beállítást tartsd meg; ennek megváltoztatása másik adatbázis megnyitását okozhatja. Javasolt a webgyökéren kívüli adattárolás, tervezett áthelyezéssel. Ellenőrizd a PHP 8.1+, PDO SQLite, mbstring, cURL, fileinfo és OpenSSL rendelkezésre állását.
6. Nyisd meg az adminfelületet. Az API a meglévő séma szükséges bővítéseit első használatkor végzi; ezért az előzetes adatbázis-mentés kötelező.
7. Ürítsd az érintett weboldalak CDN-/tárhely-gyorsítótárát. Próbáld ki a főoldal és FLOW oldal új „Belépés és app” hivatkozását.
8. Saját tesztfiókkal ellenőrizd: admin 2FA; partnerbelépés; többmegállós feladás; PDF/OCR; sofőr FLOW ID/PIN; munkanap; GPS; Smart Document; a régi CMR-feltöltés; havi riport és ECO. A levelezés valódi megérkezését külön ellenőrizd.
9. Egy tesztjárművön végezz zárolt képernyős, hálózatvesztéses és visszakapcsolási próbát. Munkanapzárás után a követés álljon le.

## Android

A `flow/app/downloads/AIMS-FLOW-v1.9.10-PILOT-build40.apk` a honlapról letölthető. SHA-256: `037f27508a847c84bd32f2962fcfbb50acb357c12c869db83a6e236d8fb3678a`.

Ez ellenőrzött **PILOT tesztkiadás, ideiglenes aláírással**. Egy korábbi kiadásra a különböző aláírás miatt nem feltétlenül telepíthető rá. Ne töröld a korábbi appot, amíg küldésre váró adat van rajta. Tartós frissítési lánchoz a GitHubban állandó Android-aláírókulcsot kell beállítani; a kulcs nincs ebben a csomagban.

## iOS

A külön iOS-csomag tartalmazza a sikeresen lefordított, aláírás nélküli iPhone-alkalmazást és a teljes Xcode-forrásprojektet. Minimum iOS 15.5. Közvetlenül nem telepíthető iPhone-ra: az Apple Developer Team, a tanúsítvány/provisioning, a TestFlight/App Store kiadás és az APNs/Firebase beállítás a saját Apple-fiókban szükséges. Részletek a `FLOW-v1.9.10-IOS-HU.md` útmutatóban.

A weboldal Safariban használható, de a kezdőképernyőre mentett weboldal nem helyettesíti a natív háttérkövetést.

## Ellenőrzések és korlátok

Az 1.9.10 kliensnél 178 Flutter-teszt, statikus elemzés, Android release-fordítás és aláírásellenőrzés, valamint macOS/Xcode aláírás nélküli iOS release-fordítás sikeres. A FLOW PHP/SQLite és HTTP regressziós tesztjei sikeresek. A módosított admin PHP-fájlokat külön szintaxisellenőrzés vizsgálja.

A tényleges tárhely-belépést, levélküldést, Apple pushszolgáltatást és többórás fizikai telefonos akkumulátorfogyasztást ez a csomag nem igazolja. A legfrissebb böngészős vizsgálat eredményét a `DOKUMENTACIO/ELLENORZES-V41.json` tartalmazza.

A havi riport cronbeállítása és a honlap `maintenance.php` időzítése külön szerverfeladat. Meglévő időzítést ne duplázz meg. A korábbi telepítési/jogi dokumentumok a `DOKUMENTACIO` alatt megmaradtak; az összeépített kiadás feltöltésénél ez az útmutató az irányadó.

## Visszaállítás

Hiba esetén állítsd vissza az érintett programfájlok mentését. Adatbázist csak az azóta keletkezett adatok megőrzésének rendezése után állíts vissza. A frissítéshez nem kell törölni a sofőrfiókokat, a járműveket vagy a korábbi dokumentumokat.
