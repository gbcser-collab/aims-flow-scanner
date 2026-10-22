# AIMS FLOW 1.9.10 / build 40 – iOS

A kiadás az Android alkalmazás mellé iOS futtatókörnyezetet és megismételhető Xcode-projektet ad. Minimum iOS 15.5, a dokumentumfelismerő követelménye miatt.

## Működés

- Egyetlen Core Location munkamenet, autós aktivitástípus, 10 méteres elmozdulásszűrés. Az iOS szabályozza a mérés időzítését; nincs garantált 15 másodperces mérés.
- A munkanap végéig engedélyezett háttérhelyzet, látható rendszerjelző, munkanapzáráskor leállítás. Álló járműnél a ritkább események nem indítanak újra és újra GPS-t.
- Wi-Fi/mobilhálózat-váltás utáni szinkronjelzés, meglévő offline sor és visszavonható munkamenet.
- A munkamenet a készülékhez kötött Keychainben az újraindítás utáni első feloldást követően zárolt képernyőnél is olvasható.
- iOS kamera-, hely- és Face ID-engedélyszövegek, iPhone-os követési útmutató, iOS helyi értesítések.

## Fordítás és telepítés

A `v1910-ios.yml` macOS-on a friss Flutter-sablonból létrehozza a projektet, majd a `ci/configure_ios.py` alkalmazza a beállításokat. A munkafolyamat `flutter build ios --release --no-codesign` fordítást futtat.

Az UNSIGNED ZIP nem telepíthető közvetlenül iPhone-ra. A SOURCE ZIP a generált `ios/` projektet, az alkalmazás forrását és a függőségek zárolt listáját tartalmazza.

Macen, Flutter és Xcode telepítése után:

1. A SOURCE ZIP-et csomagold ki; a projektben futtasd: `flutter pub get`, majd `cd ios && pod install`.
2. Nyisd meg az `ios/Runner.xcworkspace` projektet. A Signing & Capabilities részen válaszd ki a saját Apple Developer Teamet és regisztráld az egyedi bundle ID-t. A csomag alapértéke `hu.logisticaims.aims-flow-scanner`.
3. Ellenőrizd a Location updates háttérmódot és a Keychain-jogosultságokat. A signing/provisioning beállításokat az Apple-fiókban kell létrehozni.
4. Fizikai iPhone-on futtasd a próbát. TestFlight/App Store kiadáshoz készíts aláírt archive-ot az Xcode Organizerben.
5. FCM pushhoz regisztrálj külön iOS alkalmazást a Firebase-ben, töltsd fel az APNs-kulcsot, engedélyezd a Push Notifications képességet és a Remote notifications háttérmódot. A buildnek add át az `AIMS_FIREBASE_IOS_APP_ID` és a hozzá tartozó Firebase dart-define értékeket. A generikus, aláírás nélküli build nem ígér működő távoli pushértesítést.

## Telefonos átvétel

Mindig + Pontos hely jogosultság; aktív munkanap; zárolt képernyős út; Wi-Fi/mobilváltás; hálózat nélküli rögzítés és visszatöltés; kamera/OCR; munkanapzárás; újraindítás és újranyitás. Mérd a tényleges fogyasztást legalább egy többórás munkanapon, töltő nélkül. A fordítás nem helyettesíti ezeket a fizikai próbákat.

Az app kilövése, a telefon kikapcsolása vagy az engedély visszavonása után újranyitás szükséges. A weboldal kezdőképernyőre mentése nem ad natív háttér-GPS-t.

Dokumentáció: https://docs.flutter.dev/deployment/ios ; https://pub.dev/packages/geolocator ; https://pub.dev/packages/google_mlkit_text_recognition/versions/0.17.1 ; https://pub.dev/packages/flutter_secure_storage/versions/11.2.0
