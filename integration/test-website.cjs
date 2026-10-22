const {webkit}=require('playwright');
const assert=require('node:assert/strict');
const fs=require('node:fs');
(async()=>{
 const browser=await webkit.launch();fs.mkdirSync('website-checks',{recursive:true});
 const results=[];
 for(const size of [{width:375,height:812},{width:390,height:844},{width:844,height:390},{width:820,height:1180},{width:1440,height:1000}]){
  const context=await browser.newContext({viewport:size,isMobile:size.width<1000,hasTouch:size.width<1000,reducedMotion:'reduce'});
  const page=await context.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.goto('http://127.0.0.1:8088/flow/app/',{waitUntil:'networkidle'});
  assert.equal(await page.locator('h1').count(),1);
  assert.equal(await page.locator('a[download]').getAttribute('href'),'downloads/AIMS-FLOW-v1.9.10-PILOT-build40.apk');
  assert.ok(await page.locator('a[href="../../admin/index.php"]').count()>0);
  const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1);
  assert.equal(overflow,false,`horizontal overflow ${size.width}`);
  await page.locator('summary').nth(1).click();assert.equal(await page.locator('details').nth(1).getAttribute('open'),'');
  assert.equal(errors.length,0,errors.join('\n'));
  await page.screenshot({path:`website-checks/flow-app-${size.width}x${size.height}.png`,fullPage:true});
  results.push({...size,engine:'WebKit',horizontalOverflow:overflow,jsErrors:errors});
  await context.close();
 }
 fs.writeFileSync('website-checks/results.json',JSON.stringify(results,null,2));console.log(JSON.stringify(results));
 await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
