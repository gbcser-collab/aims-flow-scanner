(()=>{"use strict";
const file=(location.pathname.split('/').pop()||'index.php').toLowerCase();
const login=!!document.querySelector('form input[name="password"]');
if(login){document.body.classList.add('aims-login');return}
// The final layout class is emitted server-side. Keep this only as a safe fallback.
if(!document.body.classList.contains('aims-unified'))document.body.classList.add('aims-unified');
const existingSide=document.getElementById('aimsUnifiedShell');
const existingTop=document.getElementById('aimsUnifiedTop');

const primary=[
 ['home.php','⌂','Kezdőlap'],['index.php','↔','Fuvarok'],['aims-fleet.php','▣','Flotta'],
 ['partners.php','◇','Partnerek'],['messages.php','▤','Üzenetek'],['notifications.php','◌','Jelzések']
];
const secondary=[
 ['control-tower.php','Control Tower'],['dispatch-optimizer.php','Dispatch Optimizer'],['billing-ready.php','Számlázási kapu'],['incidents.php','Incident Center'],['autopilot.php','Autopilot'],['aims-flow.php','Flow-vezérlés'],
 ['aims-flow-mileage.php','Kilométer és árrés'],['aims-flow-monthly-report.php','Időszaki riport'],['analytics.php','Analytics'],['automation.php','E-mail-bot'],['logout.php','Kilépés']
];
const family={
 'partner.php':'partners.php','freight.php':'index.php','freights.php':'index.php','order-ai.php':'index.php','order-details.php':'index.php',
 'aims-flow-job-stops.php':'aims-flow.php','mailbox-setup.php':'automation.php','message.php':'messages.php','setup.php':'home.php',
 'foreign-stay-report.php':'aims-fleet.php'
};
const active=family[file]||file;
const e=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const prim=primary.map(([href,icon,label])=>'<a href="'+href+'" class="'+(active===href?'on active':'')+'"><i>'+icon+'</i><span>'+label+'</span>'+(href==='notifications.php'?'<b class="home6-badge aims-nav-count" data-nav-count="'+href+'" hidden>0</b>':'')+'</a>').join('');
const secondaryActive=secondary.some(([href])=>href===active);
const more='<details class="home6-more aims-more" '+(secondaryActive?'open data-active="1"':'')+'><summary><i>•••</i><span>Továbbiak</span></summary><div class="aims-more-menu">'+
 secondary.map(([href,label])=>'<a href="'+href+'" class="'+(active===href?'active ':'')+(href==='logout.php'?'exit':'')+'">'+label+'</a>').join('')+'</div></details>';

let side=existingSide;
if(!side){
 side=document.createElement('aside');
 side.id='aimsUnifiedShell';
 side.className='home6-side';
 side.innerHTML='<a class="home6-brand aims-shell-brand" href="home.php"><img src="../assets/brand-logo-blend.png" alt="AIMS"><div><b>AIMS</b><small>TRANSPORT & LOGISTICS</small></div></a>'+
  '<nav class="home6-nav aims-shell-nav">'+prim+'</nav>'+more+'<div class="home6-sidefoot aims-shell-foot"><strong data-aims-system-health>● Rendszer ellenőrzése…</strong><br><span data-aims-system-health-detail>GPS / push állapota</span></div>';
 document.body.insertBefore(side,document.body.firstChild);
}
let top=existingTop;
if(!top){
 top=document.createElement('header');
 top.id='aimsUnifiedTop';
 top.className='home6-top';
 top.innerHTML='<form class="home6-search aims-global-search" action="search.php" method="get"><input name="q" placeholder="Jármű, fuvar, partner keresése…" autocomplete="off"></form>'+
  '<div class="home6-topright aims-top-actions"><details class="aims-notify" id="aimsNotify"><summary class="home6-iconbtn" aria-label="Jelzések"><span class="aims-notify-bell">◌</span><b class="aims-notify-badge" data-notify-badge hidden>0</b></summary><div class="aims-notify-menu"><div class="aims-notify-head"><div><b>Élő jelzések</b><small data-notify-health>Kapcsolódás…</small></div><a href="notifications.php">Központ →</a></div><div class="aims-notify-items" data-notify-items><div class="aims-notify-empty">Betöltés…</div></div><div class="aims-notify-foot" data-notify-foot></div></div></details>'+
  '<div class="home6-profile aims-admin-profile"><span class="home6-avatar">A</span><div><b>Admin</b><small>AIMS Transport</small></div></div></div>';
 document.body.insertBefore(top,document.body.firstChild);
}

const command=document.createElement('div');
command.id='aimsCommandPalette';
command.innerHTML='<div class="aims-command-backdrop" data-command-close></div><div class="aims-command-box"><div class="aims-command-title"><b>AIMS gyorskereső</b><button type="button" data-command-close>×</button></div><form action="search.php" method="get"><input name="q" autocomplete="off" placeholder="Fuvar, referencia, rendszám, partner, sofőr…" data-command-input><button type="submit">KERESÉS</button></form><small>Ctrl+K / ⌘K • Esc bezár</small></div>';
const commandStyle=document.createElement('style');
commandStyle.textContent='#aimsCommandPalette{display:none;position:fixed;inset:0;z-index:50000}#aimsCommandPalette.open{display:block}.aims-command-backdrop{position:absolute;inset:0;background:#02070dbd;backdrop-filter:blur(5px)}.aims-command-box{position:relative;width:min(680px,calc(100% - 30px));margin:12vh auto 0;padding:15px;border:1px solid #2c4558;border-radius:16px;background:#0a1721;box-shadow:0 30px 90px #0009}.aims-command-title{display:flex;align-items:center;justify-content:space-between;margin-bottom:10px}.aims-command-title b{color:#eef5f8;font-size:13px}.aims-command-title button{border:0;background:transparent;color:#8093a1;font-size:24px;cursor:pointer}.aims-command-box form{display:grid;grid-template-columns:1fr auto;gap:8px}.aims-command-box input{height:48px;border:1px solid #2c4659;border-radius:10px;background:#10202e;color:#fff;padding:0 14px;font-size:14px;outline:none}.aims-command-box input:focus{border-color:#5ba8ff;box-shadow:0 0 0 3px #2c659433}.aims-command-box form button{height:48px;border:0;border-radius:10px;background:linear-gradient(135deg,#f5cf71,#bd8d31);color:#111;font-weight:900;padding:0 16px;cursor:pointer}.aims-command-box small{display:block;color:#6f8391;font-size:8px;margin-top:9px}@media(max-width:600px){.aims-command-box form{grid-template-columns:1fr}.aims-command-box{margin-top:8vh}}';
document.head.appendChild(commandStyle);document.body.appendChild(command);
const commandInput=command.querySelector('[data-command-input]');
function openCommand(){command.classList.add('open');setTimeout(()=>commandInput?.focus(),0)}
function closeCommand(){command.classList.remove('open')}
command.querySelectorAll('[data-command-close]').forEach(x=>x.addEventListener('click',closeCommand));
document.addEventListener('keydown',ev=>{if((ev.ctrlKey||ev.metaKey)&&String(ev.key).toLowerCase()==='k'){ev.preventDefault();openCommand()}else if(ev.key==='Escape'&&command.classList.contains('open'))closeCommand()});

document.querySelectorAll('.tms-side').forEach(n=>n.style.display='none');
document.querySelectorAll('.aims-module-ribbon').forEach(n=>n.remove());

// Shared, accessible mobile navigation. Every module remains reachable.
document.body.classList.add('aims-shell-ready');
const menuToggle=top.querySelector('.aims-menu-toggle');
function closeMenu(restoreFocus=false){document.body.classList.remove('aims-menu-open');menuToggle?.setAttribute('aria-expanded','false');menuToggle?.setAttribute('aria-label','Adminmenü megnyitása');if(restoreFocus)menuToggle?.focus()}
menuToggle?.addEventListener('click',()=>{const open=document.body.classList.toggle('aims-menu-open');menuToggle.setAttribute('aria-expanded',String(open));menuToggle.setAttribute('aria-label',open?'Adminmenü bezárása':'Adminmenü megnyitása');if(open)side.querySelector('a[aria-current="page"],a')?.focus()});
document.addEventListener('keydown',ev=>{if(ev.key==='Escape'&&document.body.classList.contains('aims-menu-open'))closeMenu(true)});
document.addEventListener('click',ev=>{if(!side.contains(ev.target)&&!menuToggle?.contains(ev.target))closeMenu()});
window.addEventListener('resize',()=>{if(window.innerWidth>760)closeMenu()});

const nbox=document.getElementById('aimsNotify'),badge=top.querySelector('[data-notify-badge]'),items=top.querySelector('[data-notify-items]'),health=top.querySelector('[data-notify-health]'),foot=top.querySelector('[data-notify-foot]');
const navNotify=side.querySelector('[data-nav-count="notifications.php"]');
const systemHealth=side.querySelector('[data-aims-system-health]'),systemHealthDetail=side.querySelector('[data-aims-system-health-detail]');
let notifyTimer=null,notifyDelay=12000,notifyBusy=false;
const tm=v=>{if(!v)return'';const d=new Date(v);return Number.isNaN(d.getTime())?'':d.toLocaleTimeString('hu-HU',{hour:'2-digit',minute:'2-digit',timeZone:'Europe/Budapest'})};
function toast(n){
 if(!n||!['critical','error','warning'].includes(String(n.severity||'').toLowerCase()))return;
 const key='aims-toast-'+n.source+'-'+n.id;if(sessionStorage.getItem(key))return;sessionStorage.setItem(key,'1');
 let box=document.getElementById('aimsToastStack');if(!box){box=document.createElement('div');box.id='aimsToastStack';document.body.appendChild(box)}
 const t=document.createElement('a');t.className='aims-toast '+(['critical','error'].includes(n.severity)?'critical':'warning');t.href=n.url||'notifications.php';
 t.innerHTML='<span class="aims-toast-icon">!</span><span><b>'+e(n.title||'Riasztás')+'</b><small>'+e((n.plate?n.plate+' • ':'')+(n.detail||''))+'</small></span><span class="aims-toast-close">×</span>';
 t.querySelector('.aims-toast-close').addEventListener('click',ev=>{ev.preventDefault();ev.stopPropagation();t.remove()});
 box.appendChild(t);setTimeout(()=>t.classList.add('show'),20);setTimeout(()=>{t.classList.remove('show');setTimeout(()=>t.remove(),250)},9000);
 try{navigator.vibrate?.([90,60,90])}catch(_){}
}
function renderNotify(d){
 const c=d.counts||{},q=d.queue||{},g=d.gps||{},total=+c.unread||0;
 const failed=(+q.failed||0)+(+q.dead||0),queued=(+q.pending||0)+(+q.retry||0)+(+q.sending||0),fresh=+g.fresh||0,gTotal=+g.total||0;
 if(systemHealth){const warn=failed>0||(gTotal>0&&fresh<gTotal);systemHealth.textContent=warn?'● Rendszer figyelmet kér':'● Rendszer online';systemHealth.style.color=warn?'#f5b941':'#42d887';}
 if(systemHealthDetail)systemHealthDetail.textContent='GPS '+fresh+'/'+gTotal+' • push '+queued+(failed?' • hiba '+failed:'');
 badge.hidden=total<1;badge.textContent=total>99?'99+':String(total);badge.classList.toggle('critical',(+c.critical||0)>0);
 if(navNotify){navNotify.hidden=total<1;navNotify.textContent=total>99?'99+':String(total)}
 nbox?.classList.toggle('has-critical',(+c.critical||0)>0);
 health.textContent='GPS '+(+g.fresh||0)+'/'+(+g.total||0)+' • push '+((+q.pending||0)+(+q.retry||0)+(+q.sending||0))+' sorban';
 const arr=Array.isArray(d.items)?d.items.slice(0,7):[];
 items.innerHTML=arr.length?arr.map(n=>'<a class="aims-notify-item sev-'+e(n.severity||'info')+'" href="'+e(n.url||'notifications.php')+'"><span class="aims-notify-dot"></span><span><b>'+e(n.title||'Értesítés')+'</b><small>'+e((n.plate?n.plate+' • ':'')+(n.detail||''))+'</small><time>'+e(tm(n.createdAt))+'</time></span></a>').join(''):'<div class="aims-notify-empty">Nincs olvasatlan jelzés.</div>';
 foot.innerHTML='<span>kritikus <b>'+ (+c.critical||0) +'</b></span><span>figyelmeztetés <b>'+ (+c.warning||0) +'</b></span><span class="'+((+q.failed||0)>0?'bad':'')+'">push-hiba <b>'+ (+q.failed||0) +'</b></span>';
 arr.forEach(toast);
}
function schedule(){clearTimeout(notifyTimer);notifyTimer=setTimeout(pollNotify,document.hidden?45000:notifyDelay)}
async function pollNotify(){
 if(notifyBusy){schedule();return}notifyBusy=true;
 const ctrl=new AbortController(),to=setTimeout(()=>ctrl.abort(),7000);
 try{
  const r=await fetch('aims-notification-stream.php',{credentials:'same-origin',cache:'no-store',signal:ctrl.signal,headers:{Accept:'application/json'}});
  if(r.status===401){health.textContent='Az adminisztrátori munkamenet lejárt';return}
  const d=await r.json();if(!r.ok||!d.ok)throw Error(d.error||('HTTP '+r.status));
  notifyDelay=12000;renderNotify(d);nbox?.classList.remove('degraded');
 }catch(err){
  notifyDelay=Math.min(60000,Math.round(notifyDelay*1.7));health.textContent='Kapcsolati hiba • újrapróba '+Math.round(notifyDelay/1000)+' mp';if(systemHealth){systemHealth.textContent='● Kapcsolati hiba';systemHealth.style.color='#ff5e67'}if(systemHealthDetail)systemHealthDetail.textContent='Újrapróba '+Math.round(notifyDelay/1000)+' mp';nbox?.classList.add('degraded');
 }finally{clearTimeout(to);notifyBusy=false;schedule()}
}
document.addEventListener('visibilitychange',()=>{if(!document.hidden){notifyDelay=12000;pollNotify()}else schedule()});
window.addEventListener('online',()=>{notifyDelay=3000;pollNotify()});
window.addEventListener('offline',()=>{health.textContent='Offline • utolsó állapot látható';if(systemHealth){systemHealth.textContent='● Offline';systemHealth.style.color='#ff5e67'}if(systemHealthDetail)systemHealthDetail.textContent='Nincs hálózati kapcsolat';nbox?.classList.add('degraded')});
document.addEventListener('click',ev=>{document.querySelectorAll('.aims-more[open],.aims-notify[open]').forEach(d=>{if(!d.contains(ev.target))d.removeAttribute('open')})});
pollNotify();
})();