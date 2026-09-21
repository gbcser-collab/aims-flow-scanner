# AIMS Flow R91 – mentett folytatási pont

Dátum: 2026-09-21

## Aktuális branch
`aims-flow-driver-v1-r91-invoice-scanner`

## Elkészült / branchben elmentve
- Fuvarmegbízás → Flow app adatkapcsolat
- Pushból konkrét munka megnyitása
- NAVIGÁCIÓ A FELRAKÓRA
- Fuvarmegbízás operatív adatainak megjelenítése a sofőr appban
- Flow munka törlés adminoldalról, naplózott soft delete
- Számlaszkenner R91 alap
- Partner fuvarmegbízás ELOLVASOM → ELFOGADOM biztonsági folyamat
- Offline stop/signal sor és automatikus újraküldés
- Registration Point Learning:
  - MEGÉRKEZTEM után kötelező regisztrációs lépés
  - regisztrációs referenciaszámok megjelenítése
  - BEJELENTKEZTEM A REGISZTRÁCIÓN gomb
  - gombnyomáskor aktuális GPS-pont mentése
  - telephely + stop-típus alapú tanult regisztrációs pont
  - több megerősítésből finomított GPS-pont
  - ismert pont esetén NAVIGÁCIÓ A REGISZTRÁCIÓHOZ
  - Flow adminban tanult regisztrációs pontok listája

## Fontos backend fájlok
- `server/aims-tracking/bootstrap.php`
- `server/aims-tracking/registration_point.php`
- `server/aims-tracking/driver_jobs.php`
- `server/aims-tracking/job_assign.php`

## Fontos app fájlok
- `lib/screens/driver_shell_screen.dart`
- `lib/services/driver_api_service.dart`
- `lib/services/vehicle_tracking_service.dart`
- `lib/services/driver_push_service.dart`
- `lib/screens/invoice_scanner_screen.dart`

## Fontos admin fájl
- `admin/aims-flow.php`

## Tesztállapot
Az R91 CI, invoice-scanner workflow és Android deep-test workflow a legfrissebb commitokra automatikusan fut.

Korábbi körökben:
- Flutter Analyze PASS
- unit tesztek PASS
- 10k fuzz PASS
- PHP syntax PASS
- 10k GPS/country teszt PASS
- stop E2E PASS
- 10k HTTP load PASS
- APK build PASS
- APK integrity PASS

A Registration Point Learning utáni legfrissebb teljes CI/deep-test eredményt a következő munkamenetben ellenőrizni kell.

## Még nyitott
1. Legfrissebb Registration Point Learning commitok teljes CI/deep-test eredményének ellenőrzése.
2. Live szerver célzott frissítése a GABOR-PC bridge visszatérése után.
3. Live bootstrapnál meg kell tartani a frissebb 6 karakteres sofőrkód/jelszó logikát, és csak az új R91 mezőket/funkciókat kell beolvasztani.
4. Éles E2E próba: fuvar kiküldés → push → felrakó → MEGÉRKEZTEM → regisztráció → GPS mentés → következő azonos telephelyes fuvar → regisztrációs navigáció.
5. Főoldali térkép országpontok átfedésmentes finomhangolása még külön nyitott tétel.

## UX-szabály
A sofőr fő folyamata:
1. Navigáció a helyszínre
2. MEGÉRKEZTEM
3. Regisztráció / szükséges referenciák
4. BEJELENTKEZTEM A REGISZTRÁCIÓN → GPS-tanulás
5. Rakodás/lerakás kész
6. Következő stop vagy záró hangüzenet


## Új fejlesztési feladat – egyszer használatos megbízói live tracking link
- Minden fuvarhoz generálható legyen egy egyedi, hosszú véletlen tokenes nyomkövető link.
- A link csak az adott fuvar GPS-adatait mutathatja, más járművet/fuvart soha.
- A link címzett e-mail címe automatikusan töltődjön ki a fuvarmegbízás/partner adataiból, de admin módosíthassa küldés előtt.
- A link a megbízói e-mail címhez legyen kötve; első megnyitás és további megnyitások naplózva legyenek.
- A megbízó a link alatt lássa legalább: aktuális járműpozíció, utolsó frissítés, felrakó/lerakó, fuvar státusza és ETA, de a sofőr egyéb munkái ne legyenek láthatók.
- A sofőr utolsó „munka befejezve” eseményére a tracking token azonnal legyen visszavonva/lejárt státuszú.
- Lezárás után a régi link többé ne mutasson élő helyzetet; csak „A fuvar lezárult” állapotot vagy 410 Gone választ adjon.
- A CMR lezárás/szinkron után automatikusan menjen ki ugyanarra a hitelesített megbízói e-mail címre.
- Ha a CMR még nincs kész a munka lezárásakor, a rendszer várja meg a végleges CMR feltöltést/szinkront, majd küldje ki automatikusan.
- Legyen audit: link generálva, elküldve, első megnyitás, további megnyitások, lejárat/visszavonás, CMR elküldve/hibás küldés.
- Adminból lehessen a linket kézzel azonnal visszavonni és új linket generálni.
- Biztonság: token csak hash formában legyen tárolva; noindex/noarchive; rövid cache tiltás; rate limit; nincs publikus járműlista.
