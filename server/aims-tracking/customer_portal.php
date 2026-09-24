<?php
declare(strict_types=1);

header('Cache-Control: no-store, private, max-age=0');
header('Pragma: no-cache');
header('Referrer-Policy: no-referrer');
header('X-Content-Type-Options: nosniff');
header('X-Frame-Options: DENY');
header("Content-Security-Policy: default-src 'self'; connect-src 'self'; frame-src https://www.openstreetmap.org; img-src 'self' data:; style-src 'unsafe-inline'; script-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'");

$lang = strtolower(trim((string)($_GET['lang'] ?? 'hu')));
if (!in_array($lang, ['hu','en','de'], true)) $lang = 'hu';
?><!doctype html>
<html lang="<?=htmlspecialchars($lang, ENT_QUOTES, 'UTF-8')?>">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="theme-color" content="#07131a">
<title>AIMS Flow · Shipment Tracking</title>
<style>
:root{color-scheme:dark;--bg:#071014;--panel:#0d1b22;--line:#1b3d4a;--text:#f2f7f9;--muted:#8ca7b2;--cyan:#35d7ff;--ok:#59e391;--warn:#ffd166;--bad:#ff6b6b}
*{box-sizing:border-box}body{margin:0;background:radial-gradient(circle at 50% -10%,#123443 0,#071014 42%);font:15px/1.5 Inter,Segoe UI,Arial,sans-serif;color:var(--text)}
.shell{width:min(1120px,calc(100% - 28px));margin:auto}.top{position:sticky;top:0;z-index:5;background:rgba(7,16,20,.92);backdrop-filter:blur(14px);border-bottom:1px solid var(--line)}
.topin{display:flex;align-items:center;justify-content:space-between;gap:16px;padding:15px 0}.brand{font-weight:900;letter-spacing:.08em}.brand span{display:block;color:var(--cyan);font-size:11px;letter-spacing:.18em}
.lang a{color:var(--muted);text-decoration:none;margin-left:8px}.lang a.active{color:white}.hero{padding:34px 0 18px}.eyebrow{font-size:12px;color:var(--cyan);font-weight:800;letter-spacing:.16em}
h1{margin:7px 0 4px;font-size:clamp(28px,6vw,52px);line-height:1.03}.sub{color:var(--muted)}.grid{display:grid;grid-template-columns:1.15fr .85fr;gap:16px;padding:12px 0 36px}
.card{background:linear-gradient(180deg,rgba(17,35,44,.96),rgba(10,24,30,.96));border:1px solid var(--line);padding:18px;box-shadow:0 18px 50px rgba(0,0,0,.25)}
.card h2{margin:0 0 14px;font-size:17px}.status{display:flex;flex-wrap:wrap;gap:8px;margin:14px 0}.pill{border:1px solid #2b5260;padding:7px 10px;font-size:12px;font-weight:800}.pill.ok{border-color:#275d44;color:var(--ok)}.pill.warn{border-color:#705f2c;color:var(--warn)}
.kpis{display:grid;grid-template-columns:repeat(3,1fr);gap:10px}.kpi{border:1px solid var(--line);padding:14px}.kpi b{display:block;font-size:22px}.kpi span{color:var(--muted);font-size:12px}
.stop{border-left:3px solid #325968;padding:10px 12px;margin:9px 0;background:#09161c}.stop.done{border-left-color:var(--ok)}.stop.next{border-left-color:var(--cyan)}.stop small,.timeline small{color:var(--muted)}
.timeline{position:relative}.event{padding:0 0 15px 18px;border-left:1px solid #2b4a55;margin-left:6px}.event:before{content:"";width:9px;height:9px;border-radius:50%;background:var(--cyan);position:absolute;margin-left:-23px;margin-top:6px}
.map{height:350px;border:1px solid var(--line);background:#061014}.map iframe{width:100%;height:100%;border:0}.muted{color:var(--muted)}.notice{padding:13px;border:1px solid #664f2a;background:#241f12;color:#ffe2a5;margin:12px 0}.error{border-color:#623238;background:#261315;color:#ffb0b0}
.footer{border-top:1px solid var(--line);padding:22px 0 40px;color:var(--muted);font-size:12px}
@media(max-width:820px){.grid{grid-template-columns:1fr}.kpis{grid-template-columns:1fr 1fr}.map{height:280px}}@media(max-width:480px){.kpis{grid-template-columns:1fr}}
</style>
</head>
<body>
<header class="top"><div class="shell topin"><div class="brand">LOGISTIC-A.I.M.S.<span>AIMS FLOW · CUSTOMER TRACKING</span></div><div class="lang"><a href="?lang=hu" data-lang="hu">HU</a><a href="?lang=en" data-lang="en">EN</a><a href="?lang=de" data-lang="de">DE</a></div></div></header>
<section class="hero"><div class="shell"><div class="eyebrow">LIVE TRANSPORT STATUS</div><h1 id="title">Fuvar követése</h1><div class="sub" id="subtitle">Biztonságos, időkorlátos megbízói nézet.</div><div id="notice"></div></div></section>
<main class="shell grid">
<section>
  <div class="card">
    <h2 id="overviewTitle">Áttekintés</h2>
    <div class="status"><span class="pill" id="stage">—</span><span class="pill" id="vehicle">—</span><span class="pill" id="fresh">—</span></div>
    <div class="kpis">
      <div class="kpi"><b id="eta">—</b><span id="etaLabel">Becsült érkezés</span></div>
      <div class="kpi"><b id="distance">—</b><span id="distanceLabel">Hátralévő távolság</span></div>
      <div class="kpi"><b id="speed">—</b><span id="speedLabel">Aktuális sebesség</span></div>
    </div>
  </div>
  <div class="card" style="margin-top:16px"><h2 id="routeTitle">Útvonal és megállók</h2><div id="stops"></div></div>
  <div class="card" style="margin-top:16px"><h2 id="timelineTitle">Eseménynapló</h2><div class="timeline" id="timeline"></div></div>
</section>
<aside>
  <div class="card"><h2 id="mapTitle">Jármű helyzete</h2><div class="map" id="map"><div class="muted" style="padding:18px">—</div></div><p class="muted" id="gpsTime"></p></div>
  <div class="card" style="margin-top:16px"><h2 id="docsTitle">Fuvarokmányok</h2><div id="docs" class="muted">—</div></div>
  <div class="card" style="margin-top:16px"><h2 id="detailsTitle">Fuvaradatok</h2><div id="details" class="muted">—</div></div>
</aside>
</main>
<footer class="footer"><div class="shell">Logistic-A.I.M.S. Kft. · A megosztott link csak az adott fuvar nyomkövetési adataihoz ad hozzáférést.</div></footer>
<script>
(() => {
  const LANG = <?=json_encode($lang, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES)?>;
  const dict = {
    hu:{title:'Fuvar követése',subtitle:'Biztonságos, időkorlátos megbízói nézet.',overview:'Áttekintés',route:'Útvonal és megállók',timeline:'Eseménynapló',map:'Jármű helyzete',docs:'Fuvarokmányok',details:'Fuvaradatok',eta:'Becsült érkezés',distance:'Hátralévő távolság',speed:'Aktuális sebesség',fresh:'GPS friss',stale:'GPS nem friss',minutes:'perc',noeta:'Számítás alatt',docok:'CMR / dokumentum rögzítve',docwait:'Dokumentumra vár',linkbad:'A követési link érvénytelen vagy lejárt.',pickup:'Felrakás',delivery:'Lerakás',done:'Kész',next:'Következő',assigned:'Kiosztva',accepted:'Elfogadva',in_transit:'Úton',delivered:'Lerakva',completed:'Teljesítve'},
    en:{title:'Track shipment',subtitle:'Secure, time-limited customer view.',overview:'Overview',route:'Route and stops',timeline:'Event log',map:'Vehicle location',docs:'Transport documents',details:'Shipment details',eta:'Estimated arrival',distance:'Remaining distance',speed:'Current speed',fresh:'GPS fresh',stale:'GPS stale',minutes:'min',noeta:'Calculating',docok:'CMR / document received',docwait:'Waiting for document',linkbad:'The tracking link is invalid or expired.',pickup:'Pickup',delivery:'Delivery',done:'Done',next:'Next',assigned:'Assigned',accepted:'Accepted',in_transit:'In transit',delivered:'Delivered',completed:'Completed'},
    de:{title:'Sendung verfolgen',subtitle:'Sichere, zeitlich begrenzte Kundenansicht.',overview:'Übersicht',route:'Route und Stopps',timeline:'Ereignisprotokoll',map:'Fahrzeugposition',docs:'Transportdokumente',details:'Transportdaten',eta:'Voraussichtliche Ankunft',distance:'Reststrecke',speed:'Aktuelle Geschwindigkeit',fresh:'GPS aktuell',stale:'GPS veraltet',minutes:'Min.',noeta:'Wird berechnet',docok:'CMR / Dokument erfasst',docwait:'Dokument ausstehend',linkbad:'Der Tracking-Link ist ungültig oder abgelaufen.',pickup:'Beladung',delivery:'Entladung',done:'Erledigt',next:'Nächster',assigned:'Zugewiesen',accepted:'Akzeptiert',in_transit:'Unterwegs',delivered:'Entladen',completed:'Abgeschlossen'}
  };
  const t = dict[LANG] || dict.hu;
  const qs = new URLSearchParams(location.search);
  const incoming = qs.get('t') || '';
  if (incoming) {
    sessionStorage.setItem('aims_customer_tracking_token', incoming);
    const clean = new URL(location.href);
    clean.searchParams.delete('t');
    history.replaceState({}, '', clean.pathname + (clean.searchParams.toString() ? '?' + clean.searchParams.toString() : ''));
  }
  const token = incoming || sessionStorage.getItem('aims_customer_tracking_token') || '';
  document.querySelectorAll('[data-lang]').forEach(a => {
    const u = new URL(location.href);
    u.searchParams.set('lang', a.dataset.lang);
    if (token) u.searchParams.set('t', token);
    a.href = u.pathname + '?' + u.searchParams.toString();
    if (a.dataset.lang === LANG) a.classList.add('active');
  });
  [['title','title'],['subtitle','subtitle'],['overviewTitle','overview'],['routeTitle','route'],['timelineTitle','timeline'],['mapTitle','map'],['docsTitle','docs'],['detailsTitle','details'],['etaLabel','eta'],['distanceLabel','distance'],['speedLabel','speed']].forEach(([id,k])=>document.getElementById(id).textContent=t[k]);
  const stageNames={assigned:t.assigned,accepted:t.accepted,in_transit:t.in_transit,delivered:t.delivered,completed:t.completed};
  const escText = (el, value) => { el.textContent = value == null || value === '' ? '—' : String(value); };
  const fmt = iso => { if(!iso) return '—'; const d=new Date(iso); return Number.isNaN(d.getTime())?'—':d.toLocaleString(LANG==='hu'?'hu-HU':LANG==='de'?'de-DE':'en-GB'); };
  function setNotice(msg,bad=false){const n=document.getElementById('notice');n.className=msg?'notice'+(bad?' error':''):'';n.textContent=msg||''}
  function renderMap(gps){
    const box=document.getElementById('map');box.replaceChildren();
    if(!gps){const d=document.createElement('div');d.className='muted';d.style.padding='18px';d.textContent='—';box.append(d);return}
    const lat=Number(gps.latitude),lon=Number(gps.longitude),pad=.018;
    const src='https://www.openstreetmap.org/export/embed.html?bbox='+encodeURIComponent([lon-pad,lat-pad,lon+pad,lat+pad].join(','))+'&layer=mapnik&marker='+encodeURIComponent(lat+','+lon);
    const f=document.createElement('iframe');f.src=src;f.loading='lazy';f.referrerPolicy='no-referrer';f.sandbox='allow-scripts allow-same-origin';f.title=t.map;box.append(f);
  }
  function renderStops(stops,nextStop){
    const box=document.getElementById('stops');box.replaceChildren();
    (stops||[]).forEach(s=>{
      const d=document.createElement('div');d.className='stop'+(s.completed?' done':(nextStop&&s.id===nextStop.id?' next':''));
      const b=document.createElement('b');b.textContent=(s.type==='pickup'?t.pickup:t.delivery)+' · '+(s.company||s.address);d.append(b);
      const p=document.createElement('div');p.textContent=s.address;d.append(p);
      const small=document.createElement('small');small.textContent=s.completed?t.done+' · '+fmt(s.completedAt):(nextStop&&s.id===nextStop.id?t.next:(s.arrived?fmt(s.arrivedAt):''));d.append(small);box.append(d);
    });
    if(!(stops||[]).length)box.textContent='—';
  }
  function renderTimeline(items){
    const box=document.getElementById('timeline');box.replaceChildren();
    (items||[]).slice().reverse().forEach(e=>{const d=document.createElement('div');d.className='event';const b=document.createElement('b');b.textContent=e.label;const s=document.createElement('small');s.style.display='block';s.textContent=fmt(e.at);d.append(b,s);box.append(d)});
    if(!(items||[]).length)box.textContent='—';
  }
  function renderDetails(order){
    const box=document.getElementById('details');box.replaceChildren();const entries=Object.entries(order||{});
    entries.forEach(([k,v])=>{const p=document.createElement('p');const b=document.createElement('b');b.textContent=k.replaceAll('_',' ') + ': ';p.append(b,document.createTextNode(String(v)));box.append(p)});
    if(!entries.length)box.textContent='—';
  }
  async function refresh(){
    if(!token){setNotice(t.linkbad,true);return}
    try{
      const res=await fetch('customer_tracking.php?t='+encodeURIComponent(token),{cache:'no-store',credentials:'same-origin'});
      const data=await res.json().catch(()=>null);
      if(!res.ok||!data||!data.ok){throw new Error('bad_link')}
      const s=data.shipment||{},gps=s.gps,eta=s.eta;
      setNotice('');
      escText(document.getElementById('title'),s.reference||t.title);
      escText(document.getElementById('stage'),stageNames[s.stage]||s.stage);
      document.getElementById('stage').className='pill '+(s.stage==='completed'||s.stage==='delivered'?'ok':'');
      escText(document.getElementById('vehicle'),s.vehicle);
      escText(document.getElementById('fresh'),gps?(gps.fresh?t.fresh:t.stale):t.stale);
      document.getElementById('fresh').className='pill '+(gps&&gps.fresh?'ok':'warn');
      escText(document.getElementById('eta'),eta?eta.minutes+' '+t.minutes:t.noeta);
      escText(document.getElementById('distance'),eta?eta.distanceKm+' km':'—');
      escText(document.getElementById('speed'),gps&&gps.speedKmh!=null?Math.round(gps.speedKmh)+' km/h':'—');
      document.getElementById('gpsTime').textContent=gps?fmt(gps.capturedAt):'—';
      renderMap(gps);renderStops(s.stops,s.nextStop);renderTimeline(s.timeline);renderDetails(s.order);
      document.getElementById('docs').textContent=s.document&&s.document.received?t.docok+' · '+fmt(s.document.receivedAt):t.docwait;
    }catch(e){setNotice(t.linkbad,true)}
  }
  refresh(); setInterval(refresh,20000);
})();
</script>
</body>
</html>
