# AIMS FLOW v1.9.6 build36 – követés és adatbiztonság

Kliensfrissítés a v1.9.4 szerverhez. A korábbi havi riportok, ECO, Safety, munkanap- és jogosultságkezelés megmaradnak. A csomagazonosító változatlan: `hu.logisticaims.aims_flow_scanner.v190`; minimum Android 7 / API 24.

## Mi változott?

- Android release fordítás készül: az alkalmazás nem a korábbi debug futtatókörnyezetet tartalmazza. Ettől az aláírás még lehet ideiglenes PILOT-kulcs; ez külön kérdés.
- Visszatéréskor újra ellenőrizzük a helyi belépést. Lejárt vagy megváltozott fiókkal a megőrzött képernyő nem folytatja a régi sofőr kéréseit.
- A munkanap alatt futó Flutter-feldolgozás az Android-képernyő leválasztása után is megmarad a folyamatban. A geolocator látható foreground értesítése jelzi a követést. A hálózati figyelő az alkalmazáshoz kötődik, nem tart meg bezárt Activityt.
- Menet közben 15 másodperces helyfrissítést kérünk. Legalább két perc jó minőségű álló helyzet után 60 másodperces mérési profilt kérünk, és legfeljebb kétpercenként mentünk álló pontot. A mérési időköz Android-kérés, nem garantált határidő.
- A profilváltás csak akkor indítja újra a GPS-t, ha az app előtérben van, vagy van „Mindig” helyengedély. Egy működő háttérszolgáltatást nem állítunk le azért, hogy az Android által tiltott újraindítást kíséreljünk meg. „Használat közben” engedélynél a háttérben megmaradhat a sűrűbb mérési profil.
- Új mozgás vagy 35 méternél nagyobb elmozdulás visszaállítja a mozgó profilt a következő elfogadott mintánál. Rossz pontosság, régi minta vagy háromperces mintakimaradás nem minősíti parkolónak a járművet.
- Megszűnt a folyamatos stream melletti külön félperces, nagy pontosságú GPS-lekérés. Nincs egész munkanapra fogott CPU- vagy Wi-Fi-ébresztési zár. Az Android helyszolgáltatása és a foreground követés megmarad.
- Automatikus hálózati ismétlés: 2, 5, 10, 30, 60, 120, majd legfeljebb 300 másodperc. Az új GPS-minta és az állapotellenőrző nem kerülheti meg ezt. Hitelesített új hálózat, roaming-hálózatváltás vagy kézi újrapróbálás azonnali kísérletet indíthat.
- A GPS-hibák ismétlése is korlátozott. Régi stream késői hibája nem állíthatja le az új streamet; régi vagy ismételt időbélyeg nem írja vissza az aktuális helyet. Bekapcsolt helyszolgáltatás után van automatikus helyreállítás.
- Az aktív, helyben elmentett munkanap a követés forrása: egy félbeszakadt indulás után nem szükséges új munkanapot létrehozni a helyreállításhoz.

## Helyi adatbiztonság

A GPS-napló új pont mentésekor csak az új bejegyzést írja, nem a teljes korábbi sort. Előbb tartós átmeneti napló készül; megszakadás után visszajátszható. A visszajátszás megismételhet egy pontot, de a változatlan pontazonosító miatt a szerver nem számítja új pontnak. A sérült rész külön megőrződik. A szerver által nem nyugtázott pontoknak nincs automatikus darabszám szerinti törlése.

A CMR és Smart Document helyi írásai egymás után futnak, több repository példány esetén is. CMR-indexcserekor nincs élő fájl törlése az átnevezés előtt. A jóváhagyott régi dokumentum képe csak a sikeresen elmentett indexmódosítás után törlődik.

A hiányzó képfájlhoz tartozó bejegyzés látható és függő marad. Sérült indexből nem lesz látszólag üres küldési sor; új mentés nem írhatja felül a sérült eredetit. Smart Document esetén érvényes biztonsági másolatból helyreállítható a napló, a sérült elsődleges példány külön megmarad. Friss telepítésen az első dokumentum mentése külön regressziós tesztet kapott.

## Követési állapot a telefonon

1. Nyisd meg a sofőrképernyő NET / GPS / SOR sávját.
2. A szinkronoldal felső GPS ikonján nyisd meg a **Megbízható követés** oldalt.
3. Ellenőrizd a pontos helymeghatározást és a helyengedélyt. A „Mindig” engedélyt az Android alkalmazásbeállításaiban kell megadni; az app ezt nem állítja át helyetted.
4. Ha a telefon leállítja a követést, az AIMS FLOW akkumulátorhasználatát állítsd korlátlanra, és vedd ki az alvó/mélyen alvó alkalmazások közül. A pontos elnevezés gyártónként eltér.
5. Ellenőrizd az értesítési engedélyt. Az oldalon látszik az aktív profil, a kért mérési időköz, a függő pontok száma és a követési hiba. Visszatéréskor az állapot újra beolvasódik.

A követés kizárólag az aktív munkanap alatt fut. A „Mindig” helyengedély nem változtat ezen.

## Aláírás és telepítés

A release fordítás és a tartós aláírás két külön tulajdonság. A tartós aláírókulcs beállítását a [v1.9.5 útmutató](FLOW-v1.9.5-TELEPITES-HU.md#tartós-pilot-aláírás-beállítása) írja le. A build mellett lévő nyilvános `.signing.json` közli a forráscommitot, az APK és a tanúsítvány SHA-256 ujjlenyomatát és az aláírás módját.

`ephemeral-debug` aláírás esetén külön teszttelefonon telepíts. Az előző PILOT fölé nem garantált az adatmegőrző frissítés. **Függő adatok mellett a régi alkalmazást ne töröld, és ne ürítsd az adatait.** Tartós frissítési csatornához megőrzött azonos kulcs szükséges.

## Automatizált ellenőrzés

Forrás: `a737320fcbf3fbc0517631a2466983903cccaae0`. [CI-futás](https://github.com/gbcser-collab/aims-flow-scanner/actions/runs/39750597768): 127 Flutter-teszt, 26 tesztfájl, 10 aláírási teszt; hibamentes statikus elemzés. A PHP/SQLite és valós HTTP jogosultsági, GPS-visszajátszási, munkanap-, Safety-, havi riport-, DST- és ECO-ellenőrzések sikeresek.

Az [Android release build](https://github.com/gbcser-collab/aims-flow-scanner/actions/runs/39750597762) is sikeres. A kész APK-n külön ellenőrizve: 1.9.6 / build36, Android 7 minimum, nem hibakereshető alkalmazás, letiltott automatikus backup, location foreground service, hálózati jogosultságok, a két eredeti értesítési hang változatlan tartalma, aláírás és SHA-256.

| Átadott APK | Érték |
| --- | --- |
| Név | `AIMS-FLOW-v1.9.6-PILOT-build36.apk` |
| Méret | 98 721 763 bájt (98,7 MB), a v1.9.5 207 639 995 bájtja helyett |
| SHA-256 | `85d5db2e90cce45fedaf346b3ba8bc36d7ff2df1215fddc33de50ac804115ec2` |
| Tanúsítvány SHA-256 | `6123aa09d06f1e4ec11e0124eade7f1b9e900935f8d4381f6b46b35525f4cc20` |
| Fordítás | `release-pilot` |
| Aláírás | `ephemeral-debug`, ideiglenes tesztkulcs |

A release optimalizálás célzott szabályt kapott a bővítmény négy, az app által nem használt opcionális OCR-írásrendszerére. A build ellenőrzi, hogy a kliens továbbra is kizárólag `TextRecognitionScript.latin` módot használ; új írásrendszerhez a függőségeket és a szabályokat együtt kell módosítani. Az értesítési hangok és ikon, valamint a munkanapot megtartó Android Fragment megőrzése külön beállítás.

## Valódi telefonos átvétel

Az automatizált tesztek nem helyettesítik a telefonos GPS- és fogyasztásmérést. Ezeket a próbákat ehhez a kiadáshoz még el kell végezni; valós telefon, éles terítés és mért akkumulátoreredmény nem áll rendelkezésre.

| Próba | Elvárt eredmény |
| --- | --- |
| Munkanap indítása, majd 30 perc lezárt kijelzővel | Látható követési értesítés, folytatódó helyi pontmentés és szerverfrissítés |
| 10 perc állás, majd elindulás | Takarékos profil; az új elfogadott mozgó minta után mozgó profil |
| 15 perc repülő mód, majd hálózat-visszatérés | Megmaradó saját adatok, a visszatérés után ürülő küldési sor |
| Wi-Fi → mobilnet, illetve roaming-váltás | Új szinkronkísérlet, nincs újrabelépési kényszer átmeneti hálózati hiba miatt |
| GPS kikapcsolása, majd visszakapcsolása | Érthető hibajelzés, majd helyreállítás a megadott engedélyek keretei között |
| Legutóbbi alkalmazásokból eltávolítás | A gyártói korlátozások mellett ellenőrizni kell a foreground követés és a megőrzött engine működését |
| Kényszerített leállítás / telefon-újraindítás | App újbóli megnyitása után az aktív munkanap és a helyi sor helyreáll; a kiesett időre nem gyártunk pontot |
| Munkanap lezárása | GPS és foreground követés leáll; a korábbi függő adatok továbbra is elküldhetők |
| Párhuzamos dokumentummentés és szinkron | Mindegyik dokumentum megmarad, hibánál nincs megtévesztő üres sor |
| 4 órás összehasonlító próba azonos telefonon/útvonalon | Rögzítsd az induló/záró töltöttséget, kijelzőidőt, töltést, térerőt és pontkimaradásokat |

Kényszerített leállítás, kikapcsolt telefon, visszavont engedély vagy az Android által megszüntetett folyamat esetén nincs abszolút folytonossági garancia. Automatikus újraindulást teljes folyamatvesztés vagy telefon-újraindítás után ez a kiadás nem valósít meg: az appot meg kell nyitni. A GPS nem működik nulla energiafelhasználással. Fogyasztáscsökkenési százalékot mérés nélkül nem állítunk.

Hivatalos háttér: [Android helymeghatározás és akkumulátor](https://developer.android.com/develop/sensors-and-location/location/battery), [helyalapú foreground szolgáltatás feltételei](https://developer.android.com/about/versions/14/changes/fgs-types-required), [geolocator Android-beállítások](https://pub.dev/documentation/geolocator_android/latest/geolocator_android/AndroidSettings-class.html).
