# AIMS FLOW v1.9.5 build35 – szinkronállapot és munkamenetvédelem

Ez kliensfrissítés a v1.9.4 szerverhez. A korábbi havi ország- és jelenléti riportot, ECO-értékelést, Safety-naplót és GPS-adatmegőrzést megtartja. Ehhez a kiadáshoz új szervertelepítés nem szükséges, ha a v1.9.4 szerver már működik.

## Újdonságok

- A sofőrképernyő NET/GPS/SOR sávjára koppintva megnyílik a részletes szinkronállapot.
- Külön látszik a GPS, munkanap, Safety, fuvarművelet, sofőrjelzés, regisztrációs pont, irodai üzenet és dokumentum küldési sora.
- A GPS, munkanap és Safety számláló a jelenlegi sofőr és jármű adataira vonatkozik. Külön darabszám mutatja az azonosítatlan, másik sofőrhöz/járműhöz tartozó és hibásként megőrzött bejegyzéseket. Más sofőr személyes adatai nem jelennek meg.
- A legrégebbi saját várakozó bejegyzés kora segít észrevenni az elakadt sort. Olvasási hibánál „—” jelenik meg, nem megtévesztő nulla.
- A dokumentumszámláló a telefonon elérhető dokumentumokra vonatkozik; a már feltöltött, irodai jóváhagyásra váró CMR külön szerepel.
- Az „Állapot frissítése” csak olvas. A „Küldés újrapróbálása” sorban megpróbálja a különálló küldéseket; egy alrendszer hibája nem akadályozza a következő próbáját. A GPS meglévő adagolása és újrapróbálási szabályai megmaradnak.
- A fő állapotsáv figyelembe veszi a függő munkanap- és Safety-adatokat; a fuvarfrissítés korát FUVAR jelöli. Világos módban javult a feliratok olvashatósága.

## Javított belépési hibák

- Későn visszaérkező ellenőrzési vagy első belépési válasz nem állíthat vissza kijelentkezett fiókot és nem írhat felül újabb munkamenetet/profilt.
- Kijelentkezéskor a helyi munkamenet a hálózati válasz előtt visszavonódik; a régi kijelentkezés nem törölheti egy másik sofőr új belépését.
- Párhuzamos belépéseknél csak a legutóbb indított kérés menthet munkamenetet.
- A biztonságos tárolás hibája nem eredményez olvasható tokent a normál beállítások között. Tartós visszavonási jelző védi a kijelentkezést akkor is, ha a biztonságos törlés nem sikerül.
- Átmeneti hálózati hiba nem törli automatikusan a mentett belépést. A belépőképernyőn újraellenőrzés kérhető.
- A szerver által visszautasított munkamenet üzenete megkülönböztethető a hibás FLOW ID/PIN üzenetétől.

## Tartós PILOT-aláírás beállítása

Az aláírás támogatása elkészült; önmagában a forrásfrissítés nem hoz létre tartós kulcsot. A build továbbra is debug PILOT, nem áruházi release. A csomagazonosító: `hu.logisticaims.aims_flow_scanner.v190`; verziókód: 35; minimum Android 7 / API 24.

A GitHub adattárban a Settings → Secrets and variables → Actions alatt állítsd be az alábbi öt repository secretet. A privát kulcs és a jelszavak ne kerüljenek a forrásba, csevegésbe vagy letölthető csomagba.

| Secret | Tartalom |
| --- | --- |
| `AIMS_ANDROID_KEYSTORE_BASE64` | A megőrzött JKS/PKCS12 kulcstár Base64 kódolása |
| `AIMS_ANDROID_STORE_PASSWORD` | Kulcstár jelszava |
| `AIMS_ANDROID_KEY_ALIAS` | Aláírókulcs aliasa |
| `AIMS_ANDROID_KEY_PASSWORD` | Privát kulcs jelszava |
| `AIMS_ANDROID_CERT_SHA256` | Az elvárt tanúsítvány SHA-256 ujjlenyomata; 64 hexadecimális karakter, kettőspontok megengedettek |

Az eredeti kulcsot és jelszavát a tulajdonos külön védett biztonsági mentésben őrizze meg. A Base64 csak kódolás, a védelmet a GitHub secret tárolás adja. Meglévő kulcsot kell használni, ha a már telepített alkalmazás adatmegőrző frissítése a cél. Új kulcs csak új telepítési sorozatot alapoz meg.

Beállítás után hozz létre `AIMS_REQUIRE_STABLE_SIGNING` nevű repository variable-t `true` értékkel. Ez megakadályozza a későbbi véletlen visszaállást ideiglenes kulcsra. Kézi workflow-indításkor a `require_stable_signing` kapcsoló alapértelmezetten bekapcsolt.

A workflow ellenőrzi a kulcstár tanúsítványát, majd a kész APK aláírását is. Hiányos konfigurációnál, hibás jelszónál vagy eltérő ujjlenyomatnál leáll. A privát kulcs csak a runner ideiglenes fájlja, és az `always()` takarítás eltávolítja. Az APK mellé nyilvános `.signing.json` igazolás kerül: forráscommit, APK SHA-256, tanúsítvány SHA-256, aláírásmód.

Ha egyetlen aláírási secret sincs beállítva és a tartós aláírás nincs megkövetelve, az automatikus build `ephemeral-debug` módban készül. Ez futásonként változó tesztkulcsot használhat. Az előző PILOT fölé történő adatmegőrző telepítést nem garantálja. Ilyen APK-t külön teszttelefonon használj. Függő adatok mellett a régi alkalmazást ne töröld és ne ürítsd az adatait.

Hivatalos háttér: [Android alkalmazásaláírás](https://developer.android.com/studio/publish/app-signing), [GitHub Actions secrets](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets).

## Ellenőrzés

A regressziós tesztek késleltetett HTTP-válaszokkal vizsgálják a kijelentkezést, fiókváltást, profilfrissítést és párhuzamos belépést. Hibainjektálás ellenőrzi a biztonságos tár olvasási/írási/törlési hibáit. A szinkronnézet widgettesztjei az ismeretlen állapotot és a küldési hibát követő frissítést vizsgálják. Az aláírás előellenőrzésének tesztje egyszer használatos tesztkulccsal ellenőrzi az ujjlenyomat-egyezést és az eltérés elutasítását.

Valódi telefonon még végrehajtandó: offline sorok → újraindítás → hálózat visszatérése; belépés és kijelentkezés lassú hálózaton; világos/sötét megjelenés; nagy GPS-sor; azonos tartós kulccsal aláírt két egymást követő APK adatmegőrző frissítése. Ezek a telefonos próbák és az éles telepítés nincsenek elvégezve.

Az azonosítatlan adatok automatikus tulajdonoshoz rendelése és törlése nincs bevezetve. A nézet felismerhetővé teszi a helyzetet, a rendezés irodai egyeztetést igényel.
