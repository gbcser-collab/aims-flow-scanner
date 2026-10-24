const {webkit}=require('playwright');const assert=require('node:assert/strict');const path=require('node:path');const fs=require('node:fs');const http=require('node:http');
(async()=>{
const root=path.resolve('mileage-fixture');
const server=http.createServer((req,res)=>{
 const name=new URL(req.url,'http://localhost').pathname;
 if(name.endsWith('aims-notification-stream.php')){res.writeHead(204);res.end();return}
 if(name.endsWith('.php')){res.writeHead(200,{'Content-Type':'application/json'});res.end(JSON.stringify({ok:true,notifications:[],vehicles:[]}));return}
 const file=path.resolve(root,'.'+(name==='/'?'/index.html':name));
 if(!file.startsWith(root+path.sep)||!fs.existsSync(file)||!fs.statSync(file).isFile()){res.writeHead(404);res.end();return}
 res.writeHead(200,{'Content-Type':({'.html':'text/html','.css':'text/css','.js':'text/javascript','.png':'image/png'})[path.extname(file)]||'application/octet-stream'});fs.createReadStream(file).pipe(res);
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const browser=await webkit.launch();const results=[];
for(const width of [390,820,1440]){
 const context=await browser.newContext({viewport:{width,height:1000},isMobile:width<900,hasTouch:width<900});
 const page=await context.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.route('https://tile.openstreetmap.org/**',route=>route.fulfill({status:200,contentType:'image/png',body:Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jg7cAAAAASUVORK5CYII=','base64')}));
 await page.goto('http://127.0.0.1:'+server.address().port+'/',{waitUntil:'load'});
 assert.equal(await page.locator('h1').innerText(),'Kilométer és árrés');
 await page.locator('#kmJob').selectOption({label:'TEST043 · RENDER-44'});
 assert.equal(await page.locator('#kmFinanceForm [name=planned_km]').inputValue(),'125.5');
 assert.equal(await page.locator('#kmFinanceForm [name=revenue_eur]').inputValue(),'250.00');
 await page.locator('#kmVehicle').selectOption({label:'TEST043'});await page.locator('#kmUseGps').click();
 assert.equal(await page.locator('#kmLat').inputValue(),'47.000000');
 assert.equal(await page.locator('#kmLng').inputValue(),'19.001000');
 await page.locator('#kmOpenMap').click();assert.equal(await page.locator('#kmMap').isVisible(),true);
 await page.locator('#kmMap').click({position:{x:120,y:160}});assert.ok(await page.locator('#kmLat').inputValue());
 await page.evaluate(()=>{document.getElementById('kmFilter').addEventListener('submit',e=>{e.preventDefault();window.rangeSubmitted=true})});
 await page.locator('[data-range=three]').click();
 const range=await page.evaluate(()=>({from:document.querySelector('#kmFilter [name=from]').value,to:document.querySelector('#kmFilter [name=to]').value,submitted:window.rangeSubmitted}));
 assert.equal(range.submitted,true);assert.equal((Date.parse(range.to)-Date.parse(range.from))/86400000,2);
 const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>window.innerWidth+2);assert.equal(overflow,false,'page overflow '+width);
 assert.deepEqual(errors,[]);fs.mkdirSync('website-checks',{recursive:true});await page.screenshot({path:'website-checks/mileage-'+width+'.png',fullPage:true});
 results.push({width,formPrefill:true,mapSelection:true,threeDayFilter:true,horizontalOverflow:false,errors});await context.close();
}
fs.writeFileSync('website-checks/mileage-results.json',JSON.stringify(results,null,2));console.log(JSON.stringify(results));await browser.close();await new Promise(resolve=>server.close(resolve));
})().catch(e=>{console.error(e);process.exit(1)});
