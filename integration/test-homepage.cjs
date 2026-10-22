const {webkit}=require('playwright');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const {pathToFileURL}=require('node:url');
const path=require('node:path');
(async()=>{
 const browser=await webkit.launch();const checks=[];
 for(const scenario of [
  {name:'desktop',width:1440,height:1000},
  {name:'iphone',width:390,height:844},
  {name:'canvas-error',width:390,height:844,canvasError:true},
  {name:'stalled-intro',width:390,height:844,stalled:true}
 ]){
  const context=await browser.newContext({viewport:{width:scenario.width,height:scenario.height},isMobile:scenario.width<1000,hasTouch:scenario.width<1000,reducedMotion:scenario.stalled?'no-preference':'reduce'});
  const page=await context.newPage();const errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  if(scenario.canvasError)await page.addInitScript(()=>{HTMLCanvasElement.prototype.getContext=function(){throw new Error('TEST_CANVAS_UNAVAILABLE')}});
  if(scenario.stalled)await page.addInitScript(()=>{window.requestAnimationFrame=function(){return 0}});
  await page.goto(pathToFileURL(path.resolve('homepage-fixture/index.html')).href,{waitUntil:'domcontentloaded'});
  await page.waitForFunction(()=>!document.body.classList.contains('locked')&&document.querySelector('#genesisV29').classList.contains('is-done'),null,{timeout:14000,polling:100});
  assert.equal(await page.locator('.hero h1').isVisible(),true,scenario.name+' hero is not visible');
  assert.equal(await page.locator('#headerAppDownloadV57').getAttribute('href'),'flow/app/');
  const blocking=await page.evaluate(()=>{const e=document.querySelector('#genesisV29'),s=getComputedStyle(e);return s.display!=='none'&&s.visibility!=='hidden'&&s.pointerEvents!=='none'&&s.opacity!=='0'});
  assert.equal(blocking,false,scenario.name+' intro still blocks the page');
  const unexpected=errors.filter(message=>!message.includes('TEST_CANVAS_UNAVAILABLE'));
  assert.deepEqual(unexpected,[],scenario.name+': '+unexpected.join('\n'));
  checks.push({scenario:scenario.name,heroVisible:true,downloadLink:'flow/app/',introBlocking:false,unexpectedErrors:unexpected});
  await context.close();
 }
 fs.mkdirSync('website-checks',{recursive:true});fs.writeFileSync('website-checks/homepage-results.json',JSON.stringify(checks,null,2));console.log(JSON.stringify(checks));
 await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
