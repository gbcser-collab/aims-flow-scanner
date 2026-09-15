# AIMS Flow Scanner MVP

Első működő forráskód az AIMS Flow saját CMR-scanneréhez.

## Mit tud ez a verzió?

- Android/iOS Flutter felület
- kamera-előnézet és saját AIMS scanner overlay
- saját dokumentumélek-becslés Sobel-gradienssel
- saját négypontos perspektíva-korrekció / bilineáris warp
- automatikus kontrasztjavítás
- élesség-, fényerő-, becsillanás- és dokumentumméret-ellenőrzés
- on-device Latin OCR a Google ML Kit natív motorján keresztül
- saját CMR-parser: CMR szám, feladó, címzett, fel-/lerakóhely, dátum, rendszám, darabszám, tömeg, áru
- offline lokális mentés
- fuvaradat-vs-CMR összehasonlító service előkészítve

## Fontos architekturális döntés

A dokumentum-scanner logika nem külső scanner SDK: a detektálás, perspektíva-korrekció, minőségmérés és CMR-értelmezés a projekt saját Dart kódja. Külső komponensből a kamera plugin és az OCR motor kerül felhasználásra.

## Követelmény

A függőségek jelenlegi verziói miatt ajánlott:
- Flutter >= 3.44
- Dart >= 3.12
- Android minSdk legalább 24 (a kamera plugin miatt)
- iOS deployment target legalább 15.5 (ML Kit miatt)

## Indítás

Ha a platform könyvtárak még nincsenek generálva:

```bash
flutter create --platforms=android,ios .
flutter pub get
```

Ezután a `platform_snippets/` alatt lévő kamera permission beállításokat kell összevezetni a generált Android/iOS projekttel.

Majd:

```bash
flutter run
```

## Teszt

```bash
flutter test
flutter analyze
```

## Következő fejlesztési lépcső

1. élő kamera-frame alapú automatikus dokumentumkeret és auto-capture
2. kézzel állítható négy sarok, ha az automata detektálás bizonytalan
3. aláírás/bélyegző jelenlét-detektálás
4. többoldalas scan + PDF export
5. CMR sablonok régiónként / nyelvenként
6. backend szinkron, felhasználók, admin/sofőr jogosultságok, 2FA, push
7. fuvaradatok automatikus összevetése a CMR-rel
8. audit log és GDPR-adatmegőrzés
