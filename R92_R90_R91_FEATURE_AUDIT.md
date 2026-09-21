# R90 / R91 / R92 funkcióaudit

Dátum: 2026-09-21

## Kritikus ághelyzet
Az R90 és R91 nem lineáris verziók. A GitHub compare szerint:
- R91 az R90-hez képest: 55 commit ahead, 20 commit behind.
- R90 és R91 közös merge-base után külön fejlődött.
- Emiatt az R91 NEM tekinthető automatikusan az R90 teljes funkcionalitását tartalmazó újabb verziónak.
- Az R92 jelenleg R91-ből indult, ezért az R90-only funkciókat kontrolláltan vissza kell integrálni.

## R90-only, R91-ből kiesett fontos funkciók / fájlok
- admin/aims-flow-dispatch.php — adminból fuvar kiküldése Flow-ba.
- admin/aims-flow-messages.php — főnökség ↔ sofőr üzenetkezelés.
- server/aims-tracking/driver_messages.php — sofőr/admin üzenet backend.
- api/aims-flow-login.php — 3 betű + 3 szám sofőrkód validáció + admin TOTP + push regisztráció.
- R90 driver_shell dokumentum-kapu logika:
  - végső stop után CMR szükséges;
  - dokumentum gate aktiválása;
  - CMR lokális jobhoz kötése;
  - offline CMR queue figyelése;
  - CMR nélkül az aktív fuvar nem engedi el a dokumentumfolyamatot.
- R90 driver_shell főnökségi üzenetek.
- R90 új fuvar érkezésekor AIMS voice announce.
- R90 next-step hangos visszajelzések.
- R90 push-to-talk stabilitási mód.
- R90 admin/driver push infrastruktúra több eleme.

## R91-ben már ténylegesen meglévő / nem újrafejlesztendő

### Következő lépés
MEGVAN.
- KÖVETKEZŐ LÉPÉS blokk.
- nagy elsődleges navigációs gomb.
- MEGÉRKEZTEM / BEJELENTKEZTEM A REGISZTRÁCIÓN / FELRAKÁS KÉSZ / LERAKÁS KÉSZ állapotváltás.
- R92-ben csak UX finomítás szükséges, nem új funkció.

### Registration Point Learning
MEGVAN R91-BEN.
- registration_points adatbázis.
- cég + cím + pickup/delivery típus szerinti tárolás.
- GPS mentés a regisztrációs gombnál.
- több megerősítésből átlagolt pont.
- driver_jobs visszaadja a tanult pontot.
- NAVIGÁCIÓ A REGISZTRÁCIÓHOZ.
- adminban tanult pont lista.
HIÁNY:
- offline queue a registration point mentéshez.
- fuvarszervezői portal autocomplete/reuse teljes end-to-end igazolása.

### Offline garancia
NAGYRÉSZT MEGVAN.
- GPS pontok tartós helyi queue.
- stop action offline queue + retry.
- driver signal offline queue + retry.
- fuvar cache.
- CMR scan repository + pending/failed SyncCoordinator.
HIÁNY:
- registration point offline queue.
- invoice / Smart Document offline queue.

### Gyors jelzés / BAJ VAN
RÉSZBEN MEGVAN.
R91-ben már van:
- Késés.
- Várakozás.
- Cím/rakodás — „nem található / nem engednek be”.
- Műszaki hiba.
- Baleset/sürgős.
- Egyéb.
- GPS, idő, rendszám és fuvar kontextus csatolás.
- offline signal queue.
R92-ben még fejlesztendő:
- egyetlen jól látható BAJ VAN főgomb.
- külön „Áru nincs kész”.
- külön „Nem találom a bejáratot”.
- külön „Nem engednek be”.
- külön „Cím hibás”.
- külön „Járműprobléma”.
- admin oldali jobb csoportosítás/prioritás.

### Várakozásfigyelés
NEM AZONOS a most kért funkcióval.
Már van:
- általános jármű-tétlenség figyelés 15 / 30 / 60 perces küszöbökkel.
- GPS-zajt szűrő motion logic.
- kézi Várakozás jelzés.
NINCS:
- munkafázishoz kötött 20 percenkénti ismétlődő várakozási esemény.
- referencia + aktuális stop + GPS + várakozási idő együtt.
- 20, 40, 60, 80... perces ismétlődő admin push.
- pihenő/alvás kivétellogika.
Ez valódi új R92 fejlesztés.

### Dokumentum-kapu
FONTOS KORREKCIÓ:
- R90-ben ténylegesen MEGVOLT a document gate.
- R91-ben ez KIESŐ FUNKCIÓ: driver_stop_action szerver oldalon dokumentum nélkül is completed státuszra teszi a stopot és az utolsó stopnál completed státuszra zárja a jobot.
- R91 scanner önmagában nem pótolja a gate-et.
R92 feladat:
- az R90 gate logikát visszahozni;
- kiterjeszteni Smart Document Intelligence-re;
- fuvaronként konfigurálható legyen, hogy CMR/POD/delivery note melyik kötelező.

### Hang / férfi TTS
ALAP MEGVAN.
- Google TTS motor preferálása.
- neural/natural/network voice prioritás.
- férfi hang metaadatának előnyben részesítése.
- driverName alapján megszólítás támogatott.
- announce() folyamat megvan.
FONTOS:
- a notification hang önmagában custom raw sound; nem minden push dinamikus TTS.
- R90-ben új fuvarnál explicit voice announce volt, R91-ben ez nem ugyanúgy van.
- teljes munkafolyamat-záró „köszönjük / további jó utat / nincs több munka” logikát R91-ben nem találtam teljesen megvalósítva.
R92-ben R90 hanglogikát vissza kell integrálni és véglegesíteni.

### Külső navigáció
RÉSZBEN MEGVAN.
- geo: intent.
- Google Maps web fallback.
- koordináta elsődleges, cím megmarad a UI-ban.
- ismert regisztrációs pontra külön navigáció.
NINCS:
- Waze-specifikus lifecycle/return orchestration.
- külső navigáció automatikus bezárása nem megbízható általános Android funkció; Flow fókusz-visszatérés kezelhető.
- érkezés előtti briefing nincs kész.

### Érkezés előtti briefing
NINCS KÉSZ.
- nincs automatikus távolság-alapú TTS, amely előre jelzi a cég nevét + ismert regisztrációs pontot.
- ezt R92-ben kell megépíteni.
- referenciaszám ne hangozzon el vezetés közben; csak érkezés/regisztráció után jelenjen meg.

### CMR PRO scanner
APPOLDALON NAGYRÉSZT MEGVAN R91-BEN.
- veryHigh/high/medium fallback.
- dokumentum crop + perspektíva.
- képjavítás.
- A4 PDF.
- teljes JPG.
- jobb alsó signature/stamp crop.
- confidence.
- preview.
- PDF + signature payload.
HIÁNY / ellenőrizendő:
- live CMR backend teljes PDF+signature tartós fogadása.
- valós CMR mintákon pontossági teszt.
- alacsony confidence kötelező UX.

### Számla scanner
MEGVAN R91 ALAPKÉNT.
- OCR.
- kategóriák.
- vendor/date/amount/currency/doc no.
- fuel liters/unit price.
- toll/vignette.
- partner vehicle lookup.
- server endpoint.
HIÁNY:
- offline dokumentum queue.
- Smart Document egységesítés.
- live deploy/E2E külön igazolandó.

### Smart Document Intelligence
R91-BEN NINCS.
R92-BEN ELKEZDVE:
- smart_document_classifier.dart.
- CMR/POD/invoice/fuel/toll/parking/customs/pallet/delivery note/other osztályozás.
- unit test fájl.
HIÁNY:
- még nincs bekötve az egyetlen SMART SCANNER UI-ba.
- route a megfelelő feldolgozó motorhoz.
- bizonytalan classification választó.
- generic document backend/storage.

### Night Driver Mode
NINCS R91-BEN.
- Auto / Light / Dark nincs implementálva.
- nap/éj logika nincs.
- app brightness cap nincs.
Valódi R92 fejlesztés.

### Egykezes mód
RÉSZBEN MEGVAN.
- nagy 60–64 px főgombok.
- nagy KÖVETKEZŐ LÉPÉS kártya.
NINCS:
- dedikált alsó thumb-zone layout.
- BAJ VAN + fő action egységes egykezes komponálás.
R92 UX finomítás.

### Fuvar törlés
R91 adminban nem találtam kész soft-delete kezelést / külön job delete endpointot.
Ezt jelenlegi repo alapján NEM tekintem késznek.
R92-ben megépítendő vagy a live Portalból visszaimportálandó, ha ott már létezik.

### Egyszeri megbízói live tracking link
NINCS R90/R91 app repóban.
Valódi új fejlesztés.

### Push elfogadás után
MEGVAN.
- cancelJobNotification(jobId) hívás elfogadáskor.

### 3 betű + 3 szám sofőrkód
R90 backendben MEGVAN a pontos 3 betű + 3 szám validáció.
R91 app csak 6 alfanumerikus karakterre korlátoz; az R90 backendfájl maga nincs az R91 ágban.
R92-ben az R90 hitelesítési backend kontrollált visszaintegrálása szükséges.

### App regisztráció / országkereső
MEGVAN részben.
- appos regisztrációs képernyő.
- 2 karaktertől országjavaslat.
- többnyelvű országlista.
Ellenőrizendő:
- sofőr vs cég regisztrációs szerepkör pontos UX-e.

## R92 tisztítási döntés
Nem fejlesztünk újra olyat, ami R90/R91-ben már működik.
Először kontrolláltan össze kell hozni:
1. R90-only document gate + messages + auth + push elemek.
2. R91 registration learning + invoice scanner + CMR PRO + offline signal queue.
3. R92 új fejlesztések: Smart Document Intelligence, 20 perces job waiting monitor, Night Driver Mode, pre-arrival briefing, BAJ VAN final UX, one-handed mode, live tracking link.

Minden integráció után: Analyze + unit + PHP lint + APK + E2E.
