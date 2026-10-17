// SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
// SPDX-License-Identifier: GPL-3.0-or-later
import test from 'node:test';
import assert from 'node:assert/strict';
import worker, { PlaceSearchBudget } from './worker.mjs';
class Storage {
  data = new Map(); queue = Promise.resolve(); alarm = null;
  async get(k) { return structuredClone(this.data.get(k)); }
  async put(k,v) { this.data.set(k,structuredClone(v)); }
  async getAlarm() { return this.alarm; }
  async setAlarm(v) { this.alarm=v; }
  transaction(fn) { const next=this.queue.then(()=>fn(this));this.queue=next.catch(()=>{});return next; }
}
function setup(cap='2500') {
  const storage=new Storage();const obj=new PlaceSearchBudget({storage},{GEOAPIFY_API_KEY:'fixture-only-key',DAILY_LIMIT:cap});
  let time=Date.UTC(2026,9,14);obj.clock=()=>time;
  const calls=[];obj.upstream=async (url,options)=>{calls.push({url,options});return Response.json({features:[{type:'Feature',geometry:{type:'Point',coordinates:[-115.14,36.17]},properties:{formatted:'Las Vegas, Nevada',secret:'must-not-leak'}}]});};
  return {obj,storage,calls,advance:ms=>time+=ms};
}
const query=(q='Las Vegas')=>new Request('https://places.example.org/v1/places?q='+encodeURIComponent(q)+'&lang=en');
test('concurrent rolling budget is shared and persistent',async()=>{
 const f=setup('3');const responses=await Promise.all(Array.from({length:20},(_,i)=>f.obj.fetch(query('City '+i))));
 assert.equal(responses.filter(r=>r.status===200).length,3);assert.equal(f.calls.length,3);
 const restarted=new PlaceSearchBudget({storage:f.storage},{GEOAPIFY_API_KEY:'fixture-only-key',DAILY_LIMIT:'3'});restarted.clock=f.obj.clock;restarted.upstream=f.obj.upstream;
 assert.equal((await restarted.fetch(query('Other place'))).status,429);
 f.advance(86400000);assert.equal((await restarted.fetch(query('Next day'))).status,429);
 f.advance(3600000);assert.equal((await restarted.fetch(query('After window'))).status,200);
});
test('burst limit is global and cache hits do not use provider quota',async()=>{
 const f=setup();const responses=await Promise.all(Array.from({length:10},(_,i)=>f.obj.fetch(query('Place '+i))));
 assert.equal(f.calls.length,4);assert.equal(responses.filter(r=>r.status===429).length,6);
 assert.equal((await f.obj.fetch(query('Place 0'))).status,200);assert.equal(f.calls.length,4);
 f.advance(1001);assert.equal((await f.obj.fetch(query('New place'))).status,200);
});
test('same in-flight query coalesces; cache expiry clears retained suggestions',async()=>{
 const f=setup();await Promise.all(Array.from({length:20},()=>f.obj.fetch(query())));assert.equal(f.calls.length,1);
 assert.equal(f.obj.cache.size,1);f.advance(900001);await f.obj.alarm();assert.equal(f.obj.cache.size,0);
 await f.obj.fetch(query());assert.equal(f.calls.length,2);
});
test('only fixed upstream and clean bounded GeoJSON leave the proxy',async()=>{
 const f=setup();const response=await f.obj.fetch(query());const body=await response.json();
 assert.equal(body.features.length,1);assert.equal(body.features[0].properties.formatted,'Las Vegas, Nevada');
 assert.equal(body.features[0].properties.secret,undefined);
 assert.equal(new URL(f.calls[0].url).hostname,'api.geoapify.com');assert.equal(f.calls[0].options.redirect,'manual');
 assert.equal(f.calls[0].options.headers['X-Forwarded-For'],undefined);
 assert.equal(response.headers.get('Cache-Control'),'no-store');
});
test('bad methods/query, unconfigured key and failed provider expose no secret',async()=>{
 const f=setup();assert.equal((await f.obj.fetch(query('La'))).status,400);assert.equal(f.calls.length,0);
 assert.equal((await f.obj.fetch(new Request('https://x/v1/places?q=Vegas',{method:'POST'}))).status,405);
 f.obj.upstream=async()=>new Response('fixture-only-key',{status:302});
 const r=await f.obj.fetch(query());assert.equal(r.status,503);assert.ok(!(await r.text()).includes('fixture-only-key'));
 const disabled=new PlaceSearchBudget({storage:new Storage()},{});assert.equal((await disabled.fetch(query())).status,503);
});
test('public config is key-free; routes do not consume search quota',async()=>{
 const env={GEOAPIFY_API_KEY:'fixture-only-key'};const r=await worker.fetch(new Request('https://places.example.org/map-config.json'),env);
 const text=await r.text();assert.ok(!text.includes('fixture-only-key'));const cfg=JSON.parse(text);
 assert.equal(cfg.search.autocomplete,true);assert.equal(cfg.search.url,'https://places.example.org/v1/places?q={query}&lang={lang}');
 const off=await worker.fetch(new Request('https://places.example.org/map-config.json'),{});assert.equal((await off.json()).search.enabled,false);
 assert.equal((await worker.fetch(new Request('https://places.example.org/unknown'),env)).status,404);
});

test('crossing midnight cannot double the provider free quota',async()=>{
 const f=setup('1');f.advance(86399000);assert.equal((await f.obj.fetch(query('Before midnight'))).status,200);
 f.advance(2000);assert.equal((await f.obj.fetch(query('After midnight'))).status,429);
});
test('production fetch retains its required global receiver',async()=>{
 const saved=globalThis.fetch;
 globalThis.fetch=async function() {
   if(this!==globalThis) throw new TypeError('Illegal fetch receiver');
   return Response.json({features:[]});
 };
 try {
   const obj=new PlaceSearchBudget({storage:new Storage()},{GEOAPIFY_API_KEY:'fixture-only-key'});
   const response=await obj.fetch(query());assert.equal(response.status,200);
 } finally {globalThis.fetch=saved;}
});
