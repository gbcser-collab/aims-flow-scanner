#!/usr/bin/env python3
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import subprocess, json, textwrap, os

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "demo" / "build"
OUT.mkdir(parents=True, exist_ok=True)
W,H = 1280,720

REG = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

BG=(3,10,18); PANEL=(7,23,37); CYAN=(28,184,255); GREEN=(77,227,164)
WHITE=(245,249,252); MUTED=(155,174,190); WARN=(230,184,92); RED=(255,94,94)

def f(path,size): return ImageFont.truetype(path,size)

def wrap(draw,text,width,font):
    words=text.split(); lines=[]; cur=""
    for w in words:
        t=(cur+" "+w).strip()
        if draw.textbbox((0,0),t,font=font)[2] <= width: cur=t
        else:
            if cur: lines.append(cur)
            cur=w
    if cur: lines.append(cur)
    return lines

def card(draw,xy,title,items,accent=CYAN,button=None):
    x,y,w,h=xy
    draw.rounded_rectangle((x,y,x+w,y+h),28,fill=PANEL,outline=(35,74,96),width=2)
    draw.text((x+28,y+25),title,font=f(BOLD,28),fill=WHITE)
    yy=y+78
    for it in items:
        draw.ellipse((x+30,yy+9,x+39,yy+18),fill=accent)
        for j,line in enumerate(wrap(draw,it,w-82,f(REG,21))):
            draw.text((x+54,yy+j*28),line,font=f(REG,21),fill=MUTED)
        yy += 36 + 28*(len(wrap(draw,it,w-82,f(REG,21)))-1)
    if button:
        draw.rounded_rectangle((x+28,y+h-72,x+w-28,y+h-24),18,fill=accent)
        tw=draw.textbbox((0,0),button,font=f(BOLD,18))[2]
        draw.text((x+w/2-tw/2,y+h-58),button,font=f(BOLD,18),fill=(2,16,25))

def make_slide(i, title, subtitle, left, right, status="MŰKÖDIK"):
    img=Image.new("RGB",(W,H),BG); d=ImageDraw.Draw(img)
    d.rectangle((0,0,10,H),fill=CYAN)
    d.text((55,34),"AIMS FLOW R92 · FUNKCIÓDEMÓ",font=f(BOLD,21),fill=CYAN)
    d.text((55,72),title,font=f(BOLD,42),fill=WHITE)
    y=128
    for line in wrap(d,subtitle,1120,f(REG,24)):
        d.text((58,y),line,font=f(REG,24),fill=MUTED); y+=31
    color = GREEN if status=="MŰKÖDIK" else WARN
    d.rounded_rectangle((1030,34,1215,72),16,fill=(12,42,55))
    d.text((1060,44),status,font=f(BOLD,17),fill=color)
    card(d,(60,220,550,430),**left)
    card(d,(670,220,550,430),**right)
    p=OUT/f"slide_{i:02d}.png"; img.save(p); return p

scenes = [
{
"title":"Mi az AIMS Flow?",
"subtitle":"Sofőrbarát mobil TMS: fuvar, navigáció, kommunikáció, GPS és dokumentumfolyamat egy helyen.",
"left":{"title":"SOFŐR OLDAL","items":["Aktív fuvar és következő teendő","Navigáció, megérkezés, regisztráció","Dokumentumok és üzenetek"],"accent":CYAN,"button":"KÖVETKEZŐ LÉPÉS"},
"right":{"title":"HÁTTÉR","items":["GPS és offline queue","Push és admin események","Dokumentum-gate és szinkron"],"accent":GREEN,"button":"AUTOMATIKUS"},
"narr":"Ez az AIMS Flow R92 jelenlegi működő állapota. A videó vizuális rekonstrukció, nem képernyőfelvétel. A Flow célja, hogy a sofőrnek mindig egyértelmű legyen a következő teendő, miközben a háttérben a fuvar, a GPS, az üzenetek és a dokumentumok is egy rendszerben maradnak."
},
{
"title":"Belépés és jogosultság",
"subtitle":"A sofőr rendszámmal és 3 betű + 3 szám kóddal lép be. Az admin külön kétfaktoros belépést használ.",
"left":{"title":"SOFŐR BELÉPÉS","items":["Felhasználónév: rendszám","Kód: pontosan 3 betű + 3 szám","HU / EN / DE nyelv"],"accent":CYAN,"button":"BELÉPÉS"},
"right":{"title":"ADMIN BELÉPÉS","items":["Külön admin útvonal","TOTP kétfaktoros védelem","Mobil push regisztráció"],"accent":WARN,"button":"2FA ELLENŐRZÉS"},
"narr":"A sofőr rendszámmal lép be. A kód pontosan három betűből és három számból áll. Az admin belépése ettől különválik, és megmarad a kétfaktoros TOTP védelem. A kezelőfelület magyarul, angolul és németül is használható."
},
{
"title":"Új fuvar és push",
"subtitle":"A pushból a konkrét munka nyitható meg. Elfogadás után a fuvarértesítés törlődik.",
"left":{"title":"ÚJ FUVAR ÉRKEZETT","items":["Felrakó és lerakó","Referencia és megbízásadatok","LÁTTAM / ELFOGADOM"],"accent":GREEN,"button":"ELFOGADOM"},
"right":{"title":"FUVAR RÉSZLETEI","items":["Cég, cím, koordináta","Kapcsolattartó és telefon","Áru, súly, instrukciók"],"accent":CYAN,"button":"NAVIGÁCIÓ A FELRAKÓRA"},
"narr":"Új munka esetén a telefon push értesítést kap. A kiválasztott magyar férfihang ugyanaz a hu-HU-TamasNeural hang, amely ezt mondja: Új fuvar érkezett. A konkrét fuvar megnyitható, elfogadható, és az elfogadás után az értesítés törlődik."
},
{
"title":"Mindig egy következő lépés",
"subtitle":"A munkafázis vezérli a fő gombot: navigáció, megérkezés, regisztráció, felrakás vagy lerakás kész.",
"left":{"title":"MOST","items":["NAVIGÁCIÓ A FELRAKÓRA","MEGÉRKEZTEM","BEJELENTKEZTEM"],"accent":GREEN,"button":"MEGÉRKEZTEM"},
"right":{"title":"KÖVETKEZŐ","items":["FELRAKÁS KÉSZ","KÖVETKEZŐ CÍM","LERAKÁS KÉSZ"],"accent":CYAN,"button":"KÖVETKEZŐ LÉPÉS"},
"narr":"A sofőr főképernyőjén a rendszer a munkafázis alapján emeli ki a következő lépést. Navigáció, megérkezés, regisztráció, felrakás kész, következő cím vagy lerakás kész. Nem kell menük között keresgélni."
},
{
"title":"Navigáció és telephely-emlékezet",
"subtitle":"A cím olvasható marad, a navigáció koordinátára indul, a regisztrációs GPS-pont pedig tanulható.",
"left":{"title":"NAVIGÁCIÓ","items":["Koordináta az elsődleges cél","Cím továbbra is látható","Natív térkép, Google Maps fallback"],"accent":CYAN,"button":"INDÍTÁS"},
"right":{"title":"TANULT REGISZTRÁCIÓ","items":["Cég + cím + stop-típus","Több megerősítésből finomodik","Következő fuvarnál újra használható"],"accent":GREEN,"button":"NAVIGÁCIÓ A REGISZTRÁCIÓHOZ"},
"narr":"A navigáció pontos koordinátára indul, de az olvasható cím továbbra is látható. A Flow képes megtanulni a valódi regisztrációs pontot. A következő azonos telephelyes fuvarnál már külön navigáció indulhat erre a pontra."
},
{
"title":"Üzenetek, gyors jelzés, várakozás",
"subtitle":"Kétirányú üzenetek, gyors problémabejelentés és automatikus 20 perces várakozásfigyelés.",
"left":{"title":"KOMMUNIKÁCIÓ","items":["Főnökség ↔ sofőr üzenetek","Új üzenet push","Késés, várakozás, műszaki, sürgős"],"accent":RED,"button":"JELZÉS KÜLDÉSE"},
"right":{"title":"AUTOMATIKUS VÁRAKOZÁS","items":["20 perc után első esemény","Utána 20 percenként új jelzés","Fázisváltáskor automatikusan leáll"],"accent":WARN,"button":"MÉG VÁRAKOZIK"},
"narr":"A sofőr és a főnökség kétirányú üzeneteket válthat. A gyors jelzésekhez automatikusan társul a fuvar, a rendszám, az időpont és a GPS. Ha a sofőr megérkezett, de a munkafázis nem halad tovább, a Flow húszpercenként várakozási eseményt készít."
},
{
"title":"GPS és offline működés",
"subtitle":"A fontos műveleteket a telefon helyben elfogadja, majd kapcsolatkor automatikusan újraküldi.",
"left":{"title":"OFFLINE QUEUE","items":["GPS tracking pontok","MEGÉRKEZTEM / KÉSZ események","Sofőrjelzések és regisztrációs pont"],"accent":WARN,"button":"ELMENTVE A TELEFONON"},
"right":{"title":"SZINKRON","items":["Automatikus retry","Fuvarlista helyi cache","Idempotens újraküldés"],"accent":GREEN,"button":"ELKÜLDVE"},
"narr":"A Flow fontos része az offline garancia. A GPS pontok, a megérkezés és kész események, a sofőrjelzések és a regisztrációs GPS-pont kapcsolat nélkül is helyben maradnak. A fuvarlista cache-ből visszatölthető, és internet visszatérésekor a rendszer automatikusan szinkronizál."
},
{
"title":"CMR scanner és dokumentum-kapu",
"subtitle":"A lerakás után a fuvar dokumentumra váró állapotban marad, amíg a szükséges CMR nincs rögzítve.",
"left":{"title":"CMR PRO","items":["Perspektíva-korrekció és képjavítás","OCR, A4 PDF és teljes JPG","Aláírás / pecsét crop + confidence"],"accent":CYAN,"button":"SCANNELÉS"},
"right":{"title":"DOCUMENT PENDING","items":["Utolsó stop után még nem completed","CMR nélkül a fuvar nem záródik le","Offline CMR később is szinkronizálható"],"accent":WARN,"button":"DOKUMENTUM RÖGZÍTÉSE"},
"narr":"A CMR scanner kiegyenesíti és javítja a dokumentumot, OCR-t futtat, A4 PDF-et és teljes JPG-t készít, és külön kezeli az aláírás vagy pecsét zónát. Az utolsó lerakás után a fuvar document pending állapotban marad. A dokumentum rögzítése zárja le végleg."
},
{
"title":"Számla és bizonylat scanner",
"subtitle":"OCR-rel kinyerhetők az alap pénzügyi mezők, valamint tankolási és útdíj-adatok.",
"left":{"title":"SZÁMLA","items":["Kibocsátó, dátum, végösszeg","Pénznem és bizonylatszám","Tankolás: liter és egységár"],"accent":CYAN,"button":"FELDOLGOZÁS"},
"right":{"title":"ÚTDÍJ / MATRICA","items":["Ország és érvényesség","Partner járműhöz kapcsolás","Havi rendezés alapja"],"accent":GREEN,"button":"MENTÉS"},
"narr":"A számla és bizonylat scanner OCR-rel felismeri a kibocsátót, dátumot, összeget, pénznemet és bizonylatszámot. Tankolásnál liter és egységár, útdíjnál vagy matricánál további adatok is feldolgozhatók."
},
{
"title":"Ami még NEM kész",
"subtitle":"Ezek az R92 roadmap részei, de a jelenlegi mobilbuildben nem tekintjük őket kész funkciónak.",
"left":{"title":"MÉG FEJLESZTENDŐ","items":["Night Driver Mode","Érkezés előtti automatikus briefing","Egységes egygombos Smart Scanner"],"accent":WARN,"button":"ROADMAP"},
"right":{"title":"MÉG FEJLESZTENDŐ","items":["Egyszeri megbízói live tracking link","Végleges BAJ VAN thumb-zone UX","Waze-specifikus lifecycle és teljes document offline queue"],"accent":WARN,"button":"KÖVETKEZŐ KÖR"},
"narr":"Amit még nem állítunk késznek: a Night Driver Mode, az érkezés előtti automatikus briefing, a teljesen egységes Smart Scanner, az egyszeri megbízói live tracking link, a végleges nagy Baj van felület, a Waze-specifikus életciklus és a számla valamint egyéb dokumentumok teljes offline feltöltési sora."
},
{
"title":"R92 jelenlegi állapot",
"subtitle":"A build ellenőrzései átmentek: Flutter analyze, unit tesztek, PHP syntax, geocoder, document-gate E2E és APK integrity.",
"left":{"title":"LÁTHATÓ","items":["Fuvar és következő lépés","Navigáció és kommunikáció","Scanner és dokumentumfolyamat"],"accent":GREEN,"button":"MOBIL APK"},
"right":{"title":"NEM LÁTHATÓ, DE MŰKÖDIK","items":["Offline queue és retry","Várakozásmonitor","Idempotencia és dokumentum-gate"],"accent":CYAN,"button":"HÁTTÉRRENDSZER"},
"narr":"Ez az AIMS Flow R92 jelenlegi működő állapota. A buildben a Flutter analyze, a unit tesztek, a PHP ellenőrzés, a geocoder regresszió, a dokumentum-gate teljes végponttól végpontig tesztje és az APK integritás is sikeresen lefutott. A következő fejlesztési kör a még nem látható funkciókat zárja le."
}
]

clips=[]
for i,s in enumerate(scenes,1):
    slide=make_slide(i,s["title"],s["subtitle"],s["left"],s["right"],"MŰKÖDIK" if "NEM kész" not in s["title"] else "ROADMAP")
    audio=OUT/f"audio_{i:02d}.mp3"
    subprocess.run(["edge-tts","--voice","hu-HU-TamasNeural","--rate","-3%","--text",s["narr"],"--write-media",str(audio)],check=True)
    probe=subprocess.check_output(["ffprobe","-v","error","-show_entries","format=duration","-of","json",str(audio)],text=True)
    dur=float(json.loads(probe)["format"]["duration"])+0.35
    clip=OUT/f"clip_{i:02d}.mp4"
    subprocess.run(["ffmpeg","-y","-loop","1","-i",str(slide),"-i",str(audio),
                    "-t",f"{dur:.3f}","-vf","scale=1280:720,format=yuv420p",
                    "-c:v","libx264","-preset","medium","-r","30","-c:a","aac","-b:a","160k",
                    "-shortest",str(clip)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    clips.append(clip)

concat=OUT/"concat.txt"
concat.write_text("\n".join([f"file '{p.as_posix()}'" for p in clips]),encoding="utf-8")
final=ROOT/"demo"/"AIMS-Flow-R92-Demo-HU.mp4"
subprocess.run(["ffmpeg","-y","-f","concat","-safe","0","-i",str(concat),
                "-c","copy",str(final)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)

print(final)
