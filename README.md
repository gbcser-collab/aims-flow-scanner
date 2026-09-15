# AIMS Flow Smart Scanner

Saját CMR-scanner Flutter alkalmazás a Logistic-A.I.M.S. munkafolyamataihoz.

## Aktuális fejlesztési verzió: v0.7

A v0.6 END-TO-END PASSED alapra építve a v0.7 már nem csak felismeri a dokumentumot, hanem használható offline munkafolyamatot is ad hozzá:

- kamera-előnézet és saját AIMS scanner overlay
- saját dokumentumélek-becslés Sobel-gradienssel
- saját négypontos perspektíva-korrekció / bilineáris warp
- automatikus kontrasztjavítás
- élesség-, fényerő-, becsillanás- és dokumentumméret-ellenőrzés
- on-device Latin OCR a Google ML Kit natív motorján keresztül
- saját CMR-parser: CMR szám, feladó, címzett, fel-/lerakóhely, dátum, rendszám, darabszám, tömeg, áru
- szerkeszthető OCR/CMR mezők mentés előtt
- kitöltöttségi visszajelzés
- offline CMR mentés a készülék alkalmazás-tárhelyére
- mentési előzmények a kezdőlapon
- mentett CMR újranyitása és módosítása
- mentett dokumentum törlése
- E2E teszt: kamera → fotó → dokumentumfeldolgozás → OCR → CMR eredmény → offline mentés → újraindítás → mentés visszatöltése

## Fontos architekturális döntés

A dokumentum-scanner logika nem külső scanner SDK: a detektálás, perspektíva-korrekció, minőségmérés és CMR-értelmezés a projekt saját Dart kódja. Külső komponensből a kamera plugin és az OCR motor kerül felhasználásra.

A v0.7 offline mentése JSON-indexet és a feldolgozott CMR-képek tartós másolatát használja az alkalmazás saját dokumentumtárában. Egy sérült előzménybejegyzés nem blokkolhatja a scanner indulását.

## Követelmény

A függőségek jelenlegi verziói miatt ajánlott:

- Flutter >= 3.44
- Dart >= 3.12
- Android minSdk legalább 24
- iOS deployment target legalább 15.5

## Indítás

Ha a platform könyvtárak még nincsenek generálva:

```bash
flutter create --platforms=android,ios .
flutter pub get
```

Ezután a kamera permission beállításokat össze kell vezetni a generált Android/iOS projekttel.

Majd:

```bash
flutter run
```

## Teszt

```bash
flutter test
flutter analyze
```

A GitHub Actions Android workflow API 35 emulátoron végigfuttatja a teljes Smart Scanner folyamatot, és tesztbizonyítékokat ment.

## Következő fejlesztési lépcső

1. élő kamera-frame alapú automatikus dokumentumkeret és auto-capture
2. kézzel állítható négy sarok, ha az automata detektálás bizonytalan
3. aláírás/bélyegző jelenlét-detektálás
4. többoldalas scan + PDF export
5. CMR sablonok régiónként / nyelvenként
6. backend szinkron, felhasználók, admin/sofőr jogosultságok, 2FA, push
7. fuvaradatok automatikus összevetése a CMR-rel
8. audit log és GDPR-adatmegőrzés
