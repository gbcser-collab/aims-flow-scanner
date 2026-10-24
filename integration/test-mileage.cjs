const {webkit}=require('playwright');const assert=require('node:assert/strict');const path=require('node:path');const {pathToFileURL}=require('node:url');const fs=require('node:fs');
(async()=>{const browser=await webkit.launch();const results=[];
for(const width of [390,820,1440]){
 const context=await browser.newContext({viewport:{width,height:1000},isMobile:width<900,hasTouch:width<900});
 const page=await context.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.route('https://tile.openstreetmap.org/**',route=>route.fulfill({status:200,contentType:'image/png',body:Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jg7cAAAAASUVORK5CYII=','base64')}));
 await page.goto(pathToFileURL(path.resolve('mileage-fixture/index.html')).href,{waitUntil:'load'});
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
fs.writeFileSync('website-checks/mileage-results.json',JSON.stringify(results,null,2));console.log(JSON.stringify(results));await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
