# AIMS Flow R92 – DRIVER FIRST ALL-IN-ONE MASTER ROADMAP

Dátum: 2026-09-21
Alap: R91 teljes aktuális fejlesztési állapota
Cél: egyetlen összefogott, production-ready, sofőrbarát Flow ág.

## 1. Fuvarmegbízás → Flow
- Partner/Flow Portálból PDF/megbízás adatainak kiküldése a Flow appba.
- Dupla kattintás ne hozzon létre új munkát.
- Sofőr push: új fuvar érkezett.
- Pushból közvetlenül a konkrét fuvar nyíljon meg.
- Fuvar elfogadása után NAVIGÁCIÓ A FELRAKÓRA.
- Felrakó cég + város + cím, lerakó cég + város + cím jól látható.
- GPS-koordináta + olvasható cím együtt jelenjen meg.
- Fuvar törölhető legyen adminból/Flow Portálból, naplózott soft delete-tel.
- Régi/hibás 3 munka ne maradjon örökké a sofőrnél.

## 2. Fuvarmegbízás e-mail visszaigazolás
- A külső címzett először ELOLVASOM, utána ELFOGADOM lépést kap.
- A dokumentum/munka csak ezen a kontrollált folyamaton keresztül nyíljon meg.
- Mindkét művelet menjen vissza e-mail/audit eseményként.
- Nyitás, olvasás, elfogadás időpontja legyen naplózva.

## 3. Registration Point Learning – PRIORITÁS
- GPS érzékeli, hogy a sofőr a felrakó/lerakó környezetében van.
- MEGÉRKEZTEM megerősítés.
- Következő kötelező képernyő: BEJELENTKEZÉS A REGISZTRÁCIÓHOZ.
- A szükséges pickup/delivery/customer referencia jól látható.
- BEJELENTKEZTEM A REGISZTRÁCIÓN gombnál aktuális GPS mentése.
- Cég + cím + pickup/delivery típus alapján tanult regisztrációs pont.
- Több sofőr/megerősítés finomítja a pontot.
- Következő azonos telephelyes fuvarnál NAVIGÁCIÓ A REGISZTRÁCIÓHOZ.
- Flow adminban pont, megerősítések száma, utolsó frissítés látható.

## 4. Sofőrbarát hangos folyamat
- Új fuvar push: férfi gépi hang.
- Navigáció indításakor hangos visszajelzés.
- Érkezési zónában hangos kérés: erősítse meg az érkezést.
- MEGÉRKEZTEM után hangos regisztrációs utasítás.
- Felrakás/lerakás végén köszönő hang.
- Ha van további munka: további jó utat / következő feladat.
- Ha nincs további munka: kulturált záróüzenet.
- A fontos gombnyomások emberi, rövid visszajelzést kapjanak.

## 5. GPS / navigáció finomhangolás
- Koordinátára navigálás, cím mindig látható alatta.
- Ismert regisztrációs pont külön célpont.
- Partnerenként/telephelyenként tanult pontok.
- Offline/gyenge adatkapcsolat esetén is a már letöltött cím/koordináta elérhető.
- Navigációs fallback natív térkép → Google Maps web.
- Cél: a sofőrnek ne kelljen címet másolnia vagy keresnie.

## 6. Smart Document Intelligence – EGYETLEN SMART SCANNER
- A dokumentum menüben egyetlen SMART SCANNER főgomb.
- Egy fotó → négy sarok felismerés → perspektíva-korrekció → fehérítés → élesítés → OCR.
- Automatikus dokumentumtípus-besorolás több jelből, confidence értékkel.
- Típusok:
  - CMR
  - POD / átvételi igazolás
  - szállítólevél
  - számla
  - tankolási bizonylat
  - útdíj / matrica
  - parkolási bizonylat
  - vámokmány
  - raklapcsere-papír
  - egyéb dokumentum
- Fuvar állapota/kontekstuksa segítse a besorolást.
- Bizonytalan felismerésnél sofőr egy érintéssel kiválasztja a típust.
- Felismert típus mindig kézzel módosítható.

## 7. CMR PRO
- veryHigh kamera, high/medium fallback.
- Teljes CMR kiegyenesítve, javítva.
- A4 PDF automatikus generálás.
- Teljes javított JPG megőrzése.
- Jobb alsó aláírás/pecsét zóna külön felismerése.
- Tinta/pecsét tartalom alapján biztonsági ráhagyásos külön JPEG.
- Signature confidence.
- Previewban külön ellenőrizhető.
- CMR csomag: PDF + signature/stamp JPEG + kompatibilitási teljes JPG.
- Alacsony confidence esetén sofőr figyelmeztetés / újrafotózás lehetőség.

## 8. Számla/bizonylat scanner
- OCR.
- Kibocsátó, dátum, végösszeg, pénznem, bizonylatszám.
- Tankolás: liter + egységár.
- Útdíj/matrica felismerés + ország + érvényesség.
- Partner járműhöz automatikus feltöltés.
- Havi mappázás.
- Offline queue/retry fejlesztendő.

## 9. Megbízói egyszeri live tracking link
- Egyedi, hosszú tokenes link csak az adott fuvarhoz.
- Címzett e-mail automatikusan a fuvarmegbízás e-mailjéből, küldés előtt módosítható.
- Csak az adott fuvar pozíciója/státusza/ETA.
- Másik munka/jármű nem látható.
- Megnyitások naplózása.
- Admin kézzel visszavonhatja/újragenerálhatja.
- Utolsó munka lezárásakor token azonnal lejár.
- Lezárás után nincs élő koordináta.
- Végleges CMR automatikusan ugyanarra az ellenőrzött megbízói e-mailre.
- Ha CMR később szinkronizál, küldés várakozó sorból automatikusan megtörténik.

## 10. Megjelenés / Night Driver Mode
- AUTOMATIKUS / VILÁGOS / SÖTÉT.
- Választható már a belépőképernyőn és később a beállításokban.
- Auto: GPS + helyi idő szerinti nappal/éjszaka; GPS nélkül időalapú fallback.
- Éjszaka app-fényerő legfeljebb kb. 35%, nem a telefon teljes rendszerfényereje.
- Ha rendszerfényerő 35% alatt van, ne emelje fel.
- Nappal vissza a rendszer fényerőkezelésére.
- Éjszakai UI ne vakítsa a sofőrt: sötétebb panelek, visszafogott kiemelések.

## 11. Sofőr belépés / használhatóság
- Rendszám felhasználónév.
- 3 betű + 3 szám sofőrkód.
- Sofőrnév bekérése és név szerinti hangos megszólítás.
- Appos regisztráció.
- Országkereső.
- Elfelejtett kód admin jóváhagyással.
- Admin 2FA változatlanul külön és erős.
- Chrome/back navigáció webes partner loginban kezelve.

## 12. Push / értesítések
- Elfogadás után push törlődjön.
- Új fuvar / új üzenet külön hangos szöveg.
- Admin értesítési központ.
- Járműmozgás/állás jelzések.
- „Következő feladat” logika.

## 13. Flow Portál / partner admin
- Flow Portál branding.
- Partner járművek, számlák, havi csoportosítás, vignette/útdíj.
- Partner e-mail canonical account logika.
- Törölt fiók újraregisztrálható kontrolláltan.
- Admin értesítési harang.
- Tanult regisztrációs pontok listája.
- Live tracking link vezérlés.
- CMR státusz és kiküldés állapota.

## 14. Főoldali térkép – külön, szigorú scope
- Csak térképkód/CSS módosítható.
- Belgium/országpontok valós helyükön.
- Semmilyen marker/label ne fedje egymást.
- Más főoldali rész ugyanebben a térképes módosításban nem érinthető.

## 15. Stabilitás / offline / QA
- Offline stop action queue.
- Offline driver signal queue.
- Automatikus újraküldés.
- Cache-elt fuvaradatok.
- Push/fuvar idempotencia.
- Flutter Analyze PASS.
- Unit + fuzz.
- PHP syntax.
- APK build + integrity.
- Emulator/device E2E.
- Éles E2E külön csak kontrollált deploy után.

## R92 fejlesztési sorrend
1. Smart Document Intelligence + egységes scanner.
2. CMR PRO teljes end-to-end.
3. Night Driver Mode.
4. Registration Point Learning végső teszt.
5. Live tracking link + CMR handoff.
6. Fuvar lifecycle/hangos UX finomhangolás.
7. Portál/admin integráció.
8. Teljes regresszió + APK.
9. Célzott live deploy és éles E2E.

Ez a fájl az R92 master scope. Új Flow-feladatot ehhez kell hozzáadni, hogy ne vesszen el.


## 16. AIMS DRIVE MODE – elfogadott sofőrbarát fejlesztések

### 16.1 Mindig csak egy következő teendő — ELFOGADVA / PRIORITÁS
A sofőr főképernyője mindig csak a következő szükséges lépést emelje ki nagy, egyértelmű fő műveletként.

Példa folyamat:
NAVIGÁCIÓ A FELRAKÓRA → MEGÉRKEZTEM → MENJ A REGISZTRÁCIÓHOZ → BEJELENTKEZTEM → FELRAKÁS KÉSZ → KÖVETKEZŐ CÍM.

Követelmények:
- egyszerre egy domináns főgomb;
- a következő lépést a fuvar állapota határozza meg;
- a sofőrnek ne kelljen menük között keresni;
- a következő teendő rövid hangos visszajelzést is kaphat;
- hibás/érvénytelen lépést ne engedjen átugrani;
- offline állapotban is ugyanaz a lépéslogika maradjon, helyi sorba mentéssel;
- a főképernyőn mindig látszódjon: MOST / KÖVETKEZŐ.


### 16.2 Navigáció marad elöl — MÓDOSÍTVA / ELFOGADVA
- Vezetés közben a külső navigációs app (pl. Waze) maradjon az előtérben.
- A Flow ne próbáljon vezetés közben saját felületet a térkép elé tenni.
- A navigáció indítása után a sofőr a navigációs appot használja.
- Amikor a sofőr a Flow-ban megnyomja a MEGÉRKEZTEM gombot, a Flow folytassa automatikusan a következő munkafázissal.
- A cél az, hogy a navigáció és a Flow ne versenyezzen egymással, hanem egymást váltsa a munkafolyamat szerint.
- Automatikus külső app-bezárást csak olyan platform/API esetén szabad használni, ahol ez megbízható és engedélyezett; enélkül a Flow a fókusz-visszatérést kezeli.


### 16.3 BAJ VAN — ELFOGADVA / PRIORITÁS
A sofőr főképernyőjén legyen egy nagy, egyértelmű BAJ VAN gomb.

Gyors opciók:
- NEM TALÁLOM A BEJÁRATOT
- ÁRU NINCS KÉSZ
- NEM ENGEDNEK BE
- CÍM HIBÁS
- JÁRMŰPROBLÉMA
- BALESET / SÜRGŐS
- EGYÉB

Automatikusan csatolt adatok:
- fuvarazonosító;
- jármű/rendszám;
- aktuális felrakó vagy lerakó;
- időpont;
- aktuális GPS-koordináta, ha elérhető;
- sofőr neve;
- aktuális munkafázis.

Működés:
- egy érintésből küldhető legyen;
- sürgős esemény külön prioritást és push-t kapjon;
- kapcsolat nélkül helyben sorba álljon és automatikusan újraküldődjön;
- admin/Flow Portál oldalon egyértelmű eseményként jelenjen meg;
- opcionálisan rövid hangos visszajelzés: „A jelzést elküldtem.”


### 16.4 Automatikus várakozásfigyelés — ELFOGADVA / PRIORITÁS
A Flow automatikusan érzékelje, ha a sofőr megérkezett egy felrakóhoz/lerakóhoz, de a munkafázis hosszabb ideig nem halad tovább.

Alaplogika:
- érkezési időpont rögzítése;
- ha 20 perc után még ugyanabban a várakozó munkafázisban van, első várakozási esemény;
- utána 20 percenként ismétlődő státuszjelzés, amíg a munkafázis nem változik;
- példa: 10:00 érkezés → 10:20 → 10:40 → 11:00 → 11:20 stb.;
- minden új státusz külön időbélyeget kap.

Minden várakozási jelzés tartalmazza:
- jármű / rendszám;
- sofőr;
- fuvarazonosító;
- referencia / pickup / delivery referencia;
- aktuális felrakó vagy lerakó;
- GPS koordináta;
- GPS pontosság, ha elérhető;
- érkezés időpontja;
- aktuális várakozási idő;
- aktuális munkafázis;
- utolsó státuszváltozás ideje.

Értesítések:
- push az admin/főnökségi telefonra;
- esemény a Flow admin/főnökségi felületen;
- jól látható státusz: „MÉG VÁRAKOZIK”;
- ugyanazon fuvar ismételt jelzései csoportosíthatók, de az időpontok külön megmaradnak.

Leállítás:
- automatikusan megszűnik, ha a sofőr továbblép a következő munkafázisra;
- automatikusan megszűnik, ha a fuvar lezárul;
- admin kézzel nyugtázhatja, de a nyugtázás önmagában ne törölje a további várakozásfigyelést.

Nyitott külön feladat:
- pihenő/alvó sofőr felismerése vagy sofőr által kapcsolható PIHENŐ MÓD, hogy a jogos pihenést a rendszer ne értelmezze hibás várakozásként;
- ezt külön UX/szabályként kell megtervezni a Driver Mode véglegesítése előtt.


### 16.5 Dokumentum-kapu / lezárási feltétel — MÁR KORÁBBAN FEJLESZTVE, R92-BEN MEGTARTANDÓ
- Lerakás után a következő munkafázis a szükséges CMR/POD/delivery dokumentum kezelése.
- A fuvar ne legyen véglegesen lezárható, amíg a szükséges dokumentum nincs rögzítve/feltöltve.
- CMR esetén az aláírás/pecsét megléte külön ellenőrzési pont.
- Hiányzó kötelező dokumentum vagy bizonytalan aláírás/pecsét esetén a Flow jelezzen a sofőrnek.
- Offline mentés és háttérszinkron megmarad.
- Admin jóváhagyási lánc megmarad.
- R92 feladat: a már meglévő gatinget a Smart Document Intelligence rendszerrel egységesíteni és regressziósan ellenőrizni, nem újra feltalálni.

### 16.6 Egykezes sofőrmód — ELFOGADVA
- A fő műveleti gombok a képernyő alsó, könnyen elérhető részén legyenek.
- A legfontosabb következő művelet nagy, teljes szélességű gomb.
- Másodlagos műveletek ne versenyezzenek a fő lépéssel.
- Kritikus akcióhoz ne kelljen apró ikonra célozni.
- A BAJ VAN, MEGÉRKEZTEM, REGISZTRÁCIÓ, KÉSZ és dokumentum-scan műveletek egy kézzel kényelmesen kezelhetők legyenek.
- A végleges UX-et a teljes Driver Mode átbeszélése után zárjuk le.


### 16.7 Offline garancia — KÓDBAN ELLENŐRIZVE / MEGLÉVŐ ALAP
Ellenőrzött meglévő funkciók:
- GPS tracking pontok tartós helyi queue-ban tárolódnak és kapcsolat visszatérésekor automatikusan feltöltődnek.
- Stop események (MEGÉRKEZTEM / KÉSZ) SharedPreferences-alapú tartós queue-val és automatikus retry-val rendelkeznek.
- Sofőrjelzések / BAJ VAN események tartós offline queue-ba kerülnek és automatikusan újraküldődnek.
- Fuvarlista helyi cache-ből visszatölthető kapcsolat nélkül.
- CMR scanner dokumentumok pending/failed állapotban helyben maradnak és a SyncCoordinator automatikusan újrapróbálja őket.

R92-ben bezárandó offline rések:
- Registration Point Learning GPS-mentés kapjon ugyanilyen tartós offline queue + retry mechanizmust.
- Smart Document / számla / egyéb dokumentum feltöltés kapjon tartós offline queue + retry mechanizmust.
- A UI egységesen mutassa: ELMENTVE A TELEFONON / SZINKRONRA VÁR / ELKÜLDVE.
- App újraindítás után se vesszen el egyetlen függő művelet vagy dokumentum sem.

Végső cél:
A sofőrnek ne kelljen eldöntenie, van-e internet. Minden érvényes műveletet azonnal helyben elfogad a Flow, és a hálózat visszatérésekor idempotensen szinkronizál.


### 16.8 Érkezés előtti briefing — ELFOGADVA / MÓDOSÍTVA
A Flow a cél előtt rövid, vezetés közben is könnyen érthető hangos briefinget adjon.

Példa:
„BMW Dingolfing következik. Ismert regisztrációs pont áll rendelkezésre. A bejelentkezéshez szükséges referenciaszámokat a megérkezés és a bejelentkezés megerősítése után mutatom.”

Szabályok:
- vezetés közben ne olvasson fel hosszú referenciaszámokat;
- előre csak azt jelezze, hogy ismert regisztrációs pont van;
- a konkrét referenciaszámok csak a megfelelő munkafázisban jelenjenek meg;
- a briefing tartalmazhatja a cég nevét, várost és azt, hogy ismert-e a regisztrációs pont;
- ha nincs tanult regisztrációs pont, ezt ne állítsa;
- a briefing ne takarja el a Waze/navigációt, csak hangos jelzés legyen;
- a referenciaszám megjelenítése a megérkezési/regisztrációs folyamat kontrollált lépéséhez kötődjön.


### 16.9 Telephely-emlékezet / tanult regisztrációs GPS — MÁR KIFEJLESZTVE, INTEGRÁCIÓ ELLENŐRIZENDŐ
Már elkészült:
- a sofőr a BEJELENTKEZTEM A REGISZTRÁCIÓN gombbal rögzíti az aktuális GPS-pontot;
- a pont cég + cím + stop-típus (felrakó/lerakó) szerint tárolódik;
- ugyanazon telephely következő fuvarjánál a backend visszaadja a korábban tanult regisztrációs pontot;
- az app ismert pont esetén NAVIGÁCIÓ A REGISZTRÁCIÓHOZ lehetőséget ad;
- több megerősítés finomítja a pontot;
- Flow adminban a tanult pontok és megerősítésszám megjeleníthető.

R92-ben ellenőrizendő portálintegráció:
- a fuvarszervező a cég/cím gépelésekor felismeri-e a már ismert telephelyet;
- az ismert regisztrációs GPS-pont automatikusan bekerül-e az új fuvar kiküldött adatai közé;
- a kiküldött munkában egyszerre maradjon meg az olvasható postai cím és a pontos regisztrációs GPS-koordináta;
- eltérő felrakó/lerakó regisztrációs pontokat ne keverjen össze.


## R92 baseline – korábban már eldöntött, nem új ötlet
Az alábbiakat a további ötletelés során nem szabad új fejlesztési javaslatként felsorolni; ezek a Flow megtartandó alapfunkciói:
- férfi hangos push új fuvar és fontos üzenet érkezésekor;
- a sofőr lépésről lépésre történő hangos végigvezetése a munkafolyamaton;
- navigáció indításának hangos visszajelzése;
- megérkezéskor hangos felszólítás a következő teendőre;
- regisztrációs/bejelentkezési lépés hangos vezetése;
- felrakás/lerakás lezárásakor megfelelő visszajelzés;
- ha van következő munka, további jó utat / következő feladat jelzése;
- ha nincs további munka, köszönő és kulturált záróüzenet;
- a fontos munkafázisok push + hang kombinációja.

Ezeket R92-ben regressziósan ellenőrizni kell, de nem új funkcióként kezeljük.
