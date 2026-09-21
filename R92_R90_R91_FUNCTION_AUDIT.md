# R92 – R90/R91 tényleges funkcióaudit

Dátum: 2026-09-21
Cél: megszüntetni a duplikált fejlesztést és visszakeresni a regressziókat.

## Fontos branch-helyzet
Az R90 és R91 elágazott.
- Az R91 a közös alaphoz képest sok saját fejlesztést kapott.
- A jelenlegi R90-ban 20 olyan későbbi commit is van, amely nincs benne az R91-ben.
- Ezért az R92-be nem szabad vakon sem az R90-et, sem az R91-et teljes egészében bemásolni; funkciónként kell összeolvasztani.

## A. R91-ben ténylegesen benne van – NEM KELL ÚJRAFEJLESZTENI

### A1. Egyetlen következő teendő alaplogika
- A sofőr főképernyőjén van KÖVETKEZŐ LÉPÉS / NEXT STEP.
- A fő művelet a stop állapotából számolódik.
- A regisztrációs lépés beépült a fő folyamatba.
R92: csak UX-finomhangolás, nem új funkció.

### A2. Registration Point Learning
- MEGÉRKEZTEM után regisztrációs lépés.
- BEJELENTKEZTEM A REGISZTRÁCIÓN esemény aktuális GPS-t ment.
- Cég + cím + pickup/delivery szerint tárol.
- Több megerősítésből finomít.
- Ismert pont esetén NAVIGÁCIÓ A REGISZTRÁCIÓHOZ.
- Adminban a tanult pontok listázhatók.
R92: a fuvarszervezői portál automatikus újrafelhasználását még ellenőrizni/építeni kell.

### A3. Offline alap
R91-ben tényleges:
- stop esemény tartós offline queue + retry;
- sofőrjelzés tartós offline queue + retry;
- fuvarlista helyi cache;
- GPS tracking tartós fájlqueue és retry;
- scanner/CMR szinkron pending/failed állapot és retry.
R92 hiány:
- registration-point save tartós offline queue;
- invoice/Smart Document upload tartós offline queue.

### A4. Külső navigáció
- A Flow külső geo/navigációs alkalmazást indít.
- Koordinátát használ, ha rendelkezésre áll, különben címet.
- Webes Google Maps fallback van.
R92: nem kell a Flow-t a Waze fölé tenni.
Külső navigációs app kényszerített bezárása nincs implementálva és platformfüggő.

### A5. Hangmotor
- Flutter TTS működik.
- A kód természetes/network hangot preferál, és ha elérhető, férfi hangot pontoz előre.
- Érkezés és regisztráció során már vannak hangos instrukciók.
R92: teljes folyamat regressziós ellenőrzése szükséges.

### A6. Problémajelzések alapja
R91-ben már van:
- Késés;
- Várakozás;
- Cím / rakodás (nem található / nem engednek be);
- Műszaki hiba;
- Baleset / sürgős;
- Egyéb;
- offline queue.
R92: a külön nagy BAJ VAN belépő és részletes gyorsgombok még új UX.

### A7. Általános állásfigyelés
Backendben már van járműállás-figyelés 15 / 30 / 60 perces küszöbökkel.
Ez NEM ugyanaz, mint az elfogadott job-specifikus várakozásfigyelés.

### A8. Invoice scanner / járműbizonylat
- OCR és kategorizálás;
- tankolás/útdíj/parkolás/szerviz/alkatrész kategóriák;
- járműhöz rendelés;
- matrica létrehozás támogatás;
- backend havi könyvtárszerkezet.
R92: egységes Smart Scannerbe integrálni, offline upload queue-val.

### A9. CMR PRO scanner
R91 legvégén elkészült:
- magas felbontású capture fallbackkal;
- perspektíva-korrekció és javítás;
- A4 PDF;
- külön aláírás/pecsét kép;
- signature confidence;
- review preview;
- PDF + signature payload.
R92: live backend tartós PDF/signature kezelés és valós mintateszt még szükséges.

## B. KORÁBBAN ELKÉSZÜLT, DE R91-BŐL KIESETT – VISSZAÁLLÍTANDÓ REGRESSZIÓ

### B1. CMR dokumentum-kapu
R90-ben ténylegesen megvolt:
- végső stop után CMR kötelező;
- a sofőr nem léphetett ki a lezárt munkából CMR nélkül;
- job ↔ CMR kapcsolat helyben tárolódott;
- offline CMR is elfogadható volt és sorba állt.
A jelenlegi R91 driver_shell-ben ez a gate nincs meg.
R92: visszaállítani és Smart Document gate-té bővíteni.

### B2. Sofőr ↔ főnökség élő chat
A késői R90-ben megvolt:
- driver-office chat;
- admin válasz;
- push vissza a sofőrnek;
- admin élő üzenetpanel.
R91-ben a szükséges driver_messages és admin message fájlok hiányoznak.
R92: funkciónként visszahozni, ha megtartjuk.

### B3. Flow admin dispatch endpoint
A késői R90 tartalmazza az admin/aims-flow-dispatch.php endpointot.
R91 admin felülete erre hivatkozik, de maga a fájl nincs az R91 branchben.
R92: kritikus regresszióként visszaállítani vagy az új dispatch flow-ra átvezetni.

### B4. 3 betű + 3 szám login backend
A késői R90 api/aims-flow-login.php fájlban explicit 6 karakteres, pontosan 3 betű + 3 szám validáció van.
Ez a fájl nincs az R91 branchben.
R92: az aktuális live auth rendszerrel összevetve kontrolláltan visszahozni.

### B5. Parkolóban állok kézi jelzés
A késői R90 külön Parkolóban állok gyorsjelzést tartalmaz.
R91 jelenlegi signal gridjéből ez kiesett.
R92: a pihenő/várakozás tervezésénél dönteni, hogy visszahozzuk-e külön.

## C. RÉSZBEN VAN MEG – NEM ÚJRAÍRNI, HANEM BEFEJEZNI

### C1. BAJ VAN
Alap jelzőmotor + GPS/idő/fuvar kontextus és offline signal queue már van.
Hiányzik:
- egyetlen nagy BAJ VAN belépő;
- külön NEM TALÁLOM A BEJÁRATOT;
- ÁRU NINCS KÉSZ;
- NEM ENGEDNEK BE;
- CÍM HIBÁS;
- JÁRMŰPROBLÉMA;
- egyértelmű admin prioritás/UX.
R92: meglévő _sendSignal motorra építeni.

### C2. Offline garancia
Erős alap már van.
Hiányzik a registration-point és Smart Document/invoice tartós queue.
R92: csak ezeket kell egységesíteni.

### C3. Egykezes mód
Nagy főgombok már vannak, de nincs teljes, következetes egykezes UX-rendszer.
R92: layout-pass, nem új működési motor.

### C4. Telephely-emlékezet
App/backend oldalon kész.
Hiányzik/ellenőrizendő:
- fuvarszervező gépeléskor telephely-felismerés;
- cím + tanult GPS automatikus visszatöltése az új fuvarba.

### C5. Hangos push
- magas prioritású push csatorna van;
- férfihangot preferáló TTS van;
- munkafázis TTS részben van.
Viszont R91 _handlePush nem mondja ki külön TTS-sel az új fuvar szövegét, és a kód egy aims_new_job raw sound erőforrásra hivatkozik, amely nincs az R91 branch fájljai között.
R92: a háttér/lezárt képernyős hangos push működést tényleges eszközön validálni és egységesíteni.

## D. NINCS KÉSZ – VALÓDI ÚJ / MÉG MEGÉPÍTENDŐ

### D1. Job-specifikus várakozásfigyelés
Elfogadott új szabály:
- megérkezéstől számít;
- 20 perc után első jelzés;
- utána 20 percenként;
- fuvar/ref/GPS/sofőr/helyszín;
- admin push + Flow főnökségi esemény;
- leáll, ha a munkafázis továbbmegy.
A jelenlegi 15/30/60 általános járműállásfigyelés ezt nem helyettesíti.

### D2. Pihenő / alvó sofőr kezelése
Még nincs végleges szabály.
A várakozásfigyelés fals riasztásainak elkerüléséhez külön megoldás kell.

### D3. Érkezés előtti briefing
Nincs kész.
Kért logika:
- rövid hangos briefing;
- cég + város;
- ismert regisztrációs pont jelzése;
- referenciaszámot vezetés közben ne olvassa fel;
- referenciaszám csak megérkezés/bejelentkezési fázisban jelenjen meg.

### D4. Automatikus / világos / sötét Driver Night Mode
R91-ben nincs valódi ThemeMode + app brightness szabályozás.
Megépítendő:
- Auto / Light / Dark;
- hely/idő alapú auto;
- éjszakai max kb. 35% app brightness;
- ne emelje fel, ha a rendszer már sötétebb.

### D5. Egységes Smart Document Intelligence
R91-ben külön CMR és Invoice scanner van.
Nincs egyetlen automatikus dokumentumos belépő.
R92-ben a classifier első kódja már elkészült, de a teljes UI/router/upload még nincs kész.
Cél: CMR/POD/delivery note/invoice/fuel/toll/parking/customs/pallet/other.

### D6. Egyfuvaros megbízói live tracking link
R91-ben csak terv/checkpoint szinten szerepel.
Nincs kész tokenes publikus tracking endpoint és lifecycle.
Megépítendő:
- egy fuvarra érvényes token;
- címzett e-mail;
- megnyitási audit;
- lezáráskor azonnali revoke;
- lezárás után nincs élő GPS;
- végleges CMR automatikus küldése.

### D7. Munka törlése / soft delete
A jelenlegi R91-ben nincs külön job delete/soft-delete endpoint.
A job_assign csak az adott job stopjait törli újraküldéskor, ez nem felhasználói munkatörlés.
R92: valódi admin törlés / archiválás + push/cache frissítés szükséges.

### D8. Fuvarszervezői telephely-autocomplete + tanult GPS újrafelhasználás
A tanult GPS adatbázis megvan, de a dispatch form automatikus site lookup/reuse nincs igazolva.
R92: megépíteni/ellenőrizni.

## E. NEM KELL ÚJ FUNKCIÓKÉNT KEZELNI

- „Flow ne takarja el a Waze-t”: a Flow eleve külső navigációt nyit.
- A navigációs app kényszerített bezárása nem legyen önálló prioritás; a munkafolyamat a Flow-ba való visszatérés után folytatódik.
- Férfi hang, munkafázis-visszajelzés, regisztrációs hangok: baseline, csak regressziót kell javítani.
- Registration Point Learning: baseline, csak portal reuse hiányzik.
- Offline stop/GPS/signal/cache: baseline, csak a két hiányzó queue-t kell hozzáadni.
- CMR PRO képfeldolgozás: baseline R91, csak backend/integráció és valós teszt maradt.

## R92 összevonási szabály
1. R91-et nem tekintjük automatikusan „legteljesebb” ágnak.
2. A késői R90 regressziómentes funkcióit szelektíven vissza kell emelni.
3. Már meglévő motort nem írunk újra; arra építjük az új UX-et.
4. Minden restore után Analyze + unit + APK + célzott regresszió.
5. Csak a fenti D kategória valódi új fejlesztés.
