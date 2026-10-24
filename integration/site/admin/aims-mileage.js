(()=>{'use strict';
const filter=document.getElementById('kmFilter');
const iso=d=>d.toISOString().slice(0,10);
const budapestToday=()=>{const p=Object.fromEntries(new Intl.DateTimeFormat('en',{timeZone:'Europe/Budapest',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(new Date()).map(x=>[x.type,x.value]));return p.year+'-'+p.month+'-'+p.day};
document.querySelectorAll('[data-range]').forEach(button=>button.addEventListener('click',()=>{
 const now=new Date(budapestToday()+'T12:00:00Z');let from=new Date(now),to=new Date(now);
 if(button.dataset.range==='yesterday'){from.setUTCDate(from.getUTCDate()-1);to=new Date(from)}
 if(button.dataset.range==='three')from.setUTCDate(from.getUTCDate()-2);
 if(button.dataset.range==='month')from.setUTCDate(1);
 if(button.dataset.range==='previous'){to.setUTCDate(0);from=new Date(to);from.setUTCDate(1)}
 filter.elements.from.value=iso(from);filter.elements.to.value=iso(to);filter.requestSubmit();
}));
const home=document.getElementById('kmHomeForm'),lat=document.getElementById('kmLat'),lng=document.getElementById('kmLng'),status=document.getElementById('kmLocationStatus');let map,marker,circle;
function position(a,b){lat.value=Number(a).toFixed(6);lng.value=Number(b).toFixed(6);if(map){if(marker)marker.remove();if(circle)circle.remove();marker=L.circleMarker([a,b],{radius:7,color:'#fff',fillColor:'#27523f',fillOpacity:1,weight:2}).addTo(map);circle=L.circle([a,b],{radius:Number(home.elements.radius_m.value)||200,color:'#27523f'}).addTo(map);map.setView([a,b],Math.max(map.getZoom(),15))}}
document.getElementById('kmUseGps').addEventListener('click',()=>{const v=document.getElementById('kmVehicle').selectedOptions[0];if(!v||!v.dataset.lat||!v.dataset.lng){status.textContent='Ehhez a rendszámhoz még nincs GPS-hely.';return}position(v.dataset.lat,v.dataset.lng);status.textContent='Átvett GPS-hely ideje: '+new Date(v.dataset.time).toLocaleString('hu-HU',{timeZone:'Europe/Budapest'})+'. Ellenőrizd, hogy ez a lakóhely.'});
document.getElementById('kmOpenMap').addEventListener('click',()=>{if(typeof L==='undefined'){status.textContent='A térkép nem tölthető be. A koordináták kézzel is megadhatók.';return}const node=document.getElementById('kmMap');node.hidden=false;if(!map){map=L.map(node).setView([47.5,19],7);L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png',{maxZoom:19,attribution:'© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'}).addTo(map);map.on('click',event=>{position(event.latlng.lat,event.latlng.lng);status.textContent='A térképen kijelölt hely menthető.'})}map.invalidateSize();if(lat.value!==''&&lng.value!=='')position(lat.value,lng.value);status.textContent='Nagyíts a lakóhelyre, majd kattints a pontos helyre.'});
const finance=document.getElementById('kmFinanceForm'),jobs=document.getElementById('kmJob');
jobs.addEventListener('change',()=>{const d=jobs.selectedOptions[0].dataset;finance.elements.planned_km.value=d.km||'';finance.elements.revenue_eur.value=d.revenue||'';finance.elements.service_date.value=d.date||'';finance.elements.flow_id.value=d.flow||''});
document.querySelectorAll('[data-edit-job]').forEach(button=>button.addEventListener('click',()=>{jobs.value=button.dataset.editJob;jobs.dispatchEvent(new Event('change'));document.getElementById('finance').scrollIntoView({behavior:'smooth',block:'start'});finance.elements.planned_km.focus({preventScroll:true})}));
})();
