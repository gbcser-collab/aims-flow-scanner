# AIMS Flow — v1.0 Road specification

Ez a dokumentum rögzíti a következő fejlesztési irányt az AIMS Flow mobilapphoz és a Logistic-A.I.M.S. webes adminhoz.

## 1. Kamera és scanner
- A kamera indulása legyen gyorsabb, a scanner reakcióideje legyen érezhetően rövidebb.
- A vaku három módja maradjon: KI / AUTO / BE.
- A BE mód fényképezőgépként működjön: csak a fotó elkészítésekor villanjon, ne világítson a feldolgozás és OCR közben.
- A scanner kerete tényleges crop-terület legyen: csak a keretben lévő dokumentum kerüljön a feldolgozásba, OCR-be és mentésbe.
- A kereten kívüli háttér, asztal és egyéb részletek ne maradjanak a scannelt képen.
- Perspektíva-korrekció csak indokolt esetben fusson; az eleve egyenesen fotózott CMR-t ne torzítsa.

## 2. Mentés és kézi megosztás
- A CMR / scannelt fájl kizárólag az AIMS Flow alkalmazás saját, privát tárhelyén maradjon; ne kerüljön a Galériába, Letöltések közé vagy más nyilvánosan böngészhető telefonmappába.
- A privát app-tárhelyen lévő dokumentum titkosítva legyen, és más alkalmazás számára közvetlenül ne legyen olvasható.
- Legyen alul „Küldés e-mailben” és „Küldés / megosztás” gomb.
- Viber a rendszer megosztási felületén keresztül legyen választható, ha a Viber telepítve van.
- Teljesen automatikus Viber-küldés csak külön Viber Business/Bot integrációval készüljön.

## 3. Automatikus céges CMR-szinkron és megőrzés
- Minden elkészült és mentett CMR kerüljön automatikus szinkron-sorba.
- Ha nincs internet, a dokumentum biztonságosan várjon az alkalmazás privát tárhelyén.
- Amikor internetkapcsolat elérhető, az app HTTPS-en töltse fel a dokumentumot a Logistic-A.I.M.S. backendjére.
- A szerver továbbítsa az adatot és a dokumentumot az office@logistic-aims.hu címre.
- SMTP-jelszó vagy levelezési titok ne kerüljön az APK-ba.
- A küldés tartalmazza a scannelt dokumentumot, a CMR-adatokat, az esemény idejét és — engedély esetén — a helyadatot / térképlinket.
- A dokumentum állapotai: `LOCAL_PENDING` -> `UPLOADED` -> `EMAILED` -> `ADMIN_APPROVED` -> `DELETE_SCHEDULED` -> `DELETED`.
- Az e-mail sikeres elküldése önmagában még ne törölje a dokumentumot a készülékről.
- Az admin felületen legyen egy „CMR rendben / jóváhagyva” művelet.
- A 15 napos törlési idő kizárólag az admin jóváhagyás időpontjától induljon.
- `delete_at = admin_approved_at + 15 nap`.
- A 15 nap letelte után az app saját tárhelyéről automatikusan törlődjön a CMR képe / scannelt fájl és a hozzá tartozó helyi OCR-példány.
- Törlés előtt a rendszer ellenőrizze, hogy a dokumentum valóban e-mailben továbbítva lett és admin által jóvá lett hagyva; ellenkező esetben ne töröljön.
- A telefonon a törlés után csak minimális audit-metaadat maradhat: CMR azonosító/hash, küldési idő, admin-jóváhagyás ideje, törlés ideje és sikeres törlési állapot. Maga a dokumentumkép ne maradjon meg.
- Az office@logistic-aims.hu postafiókban lévő e-mailes példány ettől nem törlődik automatikusan; annak megőrzése külön e-mail/iratkezelési szabály szerint kezelendő.

## 4. Állandó jármű-követés
- A helymeghatározás legyen folyamatosan aktív a céges használat alatt, ne csak egy-egy fuvar idejére.
- Az app rendszeres időközönként küldje a jármű aktuális helyzetét a backendnek.
- Rossz vagy megszűnő internetkapcsolat esetén a pontokat helyben pufferelje, majd kapcsolat helyreállásakor szinkronizálja.
- A tracking adat legalább: készülék/jármű azonosító, időpont, szélesség, hosszúság, pontosság, sebesség (ha elérhető), irány (ha elérhető), töltöttség (ha elérhető).
- Androidon a folyamatos háttérkövetés foreground service-szel és látható rendszerértesítéssel fusson; ne legyen rejtett nyomkövetés.
- A sofőr számára egyértelmű legyen, hogy a céges jármű-követés aktív.

## 5. Logistic-A.I.M.S. webes admin — Élő flotta
- A jelenlegi weboldal admin részébe kerüljön egy új „Élő flotta” / „Nyomkövetés” modul.
- Belépés csak admin jogosultsággal, később 2FA-val.
- Főnézet: teljes képernyős interaktív térkép, rajta minden aktív jármű.
- Járműkártyák: rendszám, sofőr / eszköz neve, utolsó adat időpontja, aktuális státusz, sebesség, akkumulátor, online/offline állapot.
- Egy járműre kattintva: aktuális pozíció, utolsó ismert cím, aznapi útvonal, megállások, mozgási idő, utolsó CMR esemény.
- Történeti nézet: dátum alapján visszajátszható útvonal.
- „Offline” figyelmeztetés, ha egy eszköz meghatározott ideje nem küldött pozíciót.
- CMR és helyadat kapcsolható legyen össze: a CMR mentési/küldési helye jelenjen meg a térképen.
- A CMR admin-listában jelenjen meg a küldési állapot, a jóváhagyás állapota és a tervezett automatikus törlés dátuma.
- Későbbi bővítés: geofence, érkezési/elhagyási események, ügyfélnek megosztható időszakos tracking link, ETA.

## 6. Backend
- Mobil app -> HTTPS API -> saját backend -> adatbázis -> webes admin térkép.
- A backend kezelje külön a pozíciókat, járműveket/eszközöket, CMR-eket és szinkron-sorokat.
- Minden API-kérés hitelesített legyen; kliensoldali titok ne kerüljön könnyen visszafejthető formában az APK-ba.
- Admin felület közvetlenül ne érje el a nyers adatbázist; kizárólag jogosultság-ellenőrzött API-n keresztül dolgozzon.
- A CMR-jóváhagyás és törlési ütemezés szerveroldali állapot legyen, ne kizárólag a telefon helyi órájára támaszkodjon.

## 7. Weboldal integrációs alap
- A következő admin fejlesztés kiindulási weboldal-alapja: Logistic-AIMS-V60-UNIFIED-HEADER.
- A tracking admin ne nyilvános menüpont legyen, hanem védett admin terület.

## Fejlesztési sorrend
1. Scanner gyorsítás + valódi frame crop + vaku viselkedés javítása.
2. Mobil tracking service + offline puffer.
3. Tracking backend API + adatmodell.
4. Webes admin élő térkép.
5. CMR automatikus szerver-szinkron + e-mail továbbítás.
6. Admin CMR-jóváhagyás + 15 napos automatikus app-tárhely törlés.
7. Történeti útvonal, geofence, értesítések, 2FA és auditnapló.
