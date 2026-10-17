// SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
// SPDX-License-Identifier: GPL-3.0-or-later
const TTL = 900000, MAX_CACHE = 128, MAX_BODY = 262144;
const attribution = 'Powered by Geoapify · © OpenStreetMap contributors';
function json(value,status=200,extra={}) {
  return Response.json(value,{status,headers:{'Cache-Control':'no-store','Access-Control-Allow-Origin':'*',...extra}});
}
function error(code,message,status,retry=0) {
  return json({error:{code,message}},status,retry?{'Retry-After':String(retry)}:{});
}
function input(request) {
  if(request.method!=='GET') return {failure:error('method_not_allowed','Use GET.',405)};
  const url=new URL(request.url);
  for(const key of url.searchParams.keys()) if(!['q','lang'].includes(key)) return {failure:error('invalid_query','Unsupported query parameter.',400)};
  if(url.searchParams.getAll('q').length!==1 || url.searchParams.getAll('lang').length>1) return {failure:error('invalid_query','Provide one place query.',400)};
  const text=(url.searchParams.get('q')||'').trim().replace(/\s+/gu,' ');
  const lang=url.searchParams.get('lang')||'en';
  if(text.length<3 || text.length>200 || /[\u0000-\u001f\u007f]/u.test(text) || !/^[a-z]{2}(?:-[A-Za-z]{2})?$/u.test(lang)) return {failure:error('invalid_query','Use 3–200 characters and a supported language code.',400)};
  return {text,lang,key:JSON.stringify([text.toLowerCase(),lang.toLowerCase()])};
}
async function boundedJSON(response) {
  if(!response.body) throw new Error('No response body');
  const reader=response.body.getReader(), chunks=[];let count=0;
  try {
    while(true) {
      const {done,value}=await reader.read();if(done) break;
      count+=value.byteLength;if(count>MAX_BODY) {await reader.cancel();throw new Error('Oversized response');}
      chunks.push(value);
    }
  } finally {reader.releaseLock();}
  const bytes=new Uint8Array(count);let offset=0;
  for(const chunk of chunks) {bytes.set(chunk,offset);offset+=chunk.byteLength;}
  return JSON.parse(new TextDecoder().decode(bytes));
}
function cleanResults(value) {
  if(!value || !Array.isArray(value.features)) throw new Error('Invalid provider answer');
  const features=[];
  for(const feature of value.features) {
    const xy=feature?.geometry?.coordinates,props=feature?.properties;
    const name=props?.formatted || props?.name;
    if(feature?.geometry?.type!=='Point' || !Array.isArray(xy) || !Number.isFinite(xy[0]) || !Number.isFinite(xy[1]) || Math.abs(xy[0])>180 || Math.abs(xy[1])>90 || typeof name!=='string' || !name.trim()) continue;
    features.push({type:'Feature',geometry:{type:'Point',coordinates:xy.slice(0,2)},properties:{formatted:name.trim().slice(0,240)}});
    if(features.length===5) break;
  }
  return {type:'FeatureCollection',features};
}
export class PlaceSearchBudget {
  constructor(ctx,env) {this.ctx=ctx;this.env=env;this.cache=new Map();this.pending=new Map();this.clock=Date.now;this.upstream=fetch.bind(globalThis);}
  purge() {const now=this.clock();for(const [k,v] of this.cache) if(v.expires<=now) this.cache.delete(k);}
  async alarm() {
    this.purge();if(this.cache.size) await this.ctx.storage.setAlarm(Math.min(...[...this.cache.values()].map(v=>v.expires)));
  }
  async reserve() {
    const now=this.clock(), hour=Math.floor(now/3600000)*3600000;
    const configured=Number(this.env.DAILY_LIMIT||2500);
    const cap=Number.isFinite(configured)?Math.max(1,Math.min(3000,Math.floor(configured))):2500;
    return this.ctx.storage.transaction(async txn=>{
      const budget=await txn.get('budget') || {buckets:[],recent:[]};
      // Include the entire oldest hour: conservatively cap every rolling 24h,
      // independent of the provider's unknown daily-reset timezone.
      budget.buckets=budget.buckets.filter(b=>b.hour>=hour-86400000);
      const used=budget.buckets.reduce((total,b)=>total+b.used,0);
      if(used>=cap) return error('daily_limit','Search capacity reached. Enter coordinates or try later.',429,Math.max(1,Math.ceil((Math.min(...budget.buckets.map(b=>b.hour))+90000000-now)/1000)));
      budget.recent=budget.recent.filter(t=>t>now-1000);
      if(budget.recent.length>=4) return error('rate_limit','Search is busy. Try again shortly.',429,1);
      let current=budget.buckets.find(b=>b.hour===hour);
      if(!current) {current={hour,used:0};budget.buckets.push(current);}
      current.used+=1;budget.recent.push(now);await txn.put('budget',budget);return null;
    });
  }

  async lookup(parameters) {
    const limited=await this.reserve();if(limited) return limited;
    const url=new URL('https://api.geoapify.com/v1/geocode/autocomplete');
    url.searchParams.set('text',parameters.text);url.searchParams.set('lang',parameters.lang);url.searchParams.set('limit','5');url.searchParams.set('apiKey',this.env.GEOAPIFY_API_KEY);
    let response;
    try {
      // Never forward incoming IP/headers or follow a redirect with the key.
      const answer=await this.upstream(url.toString(),{redirect:'manual',headers:{Accept:'application/json'},signal:AbortSignal.timeout(8000)});
      if(answer.status!==200) return error('provider_unavailable','Place search is temporarily unavailable.',503,30);
      response=cleanResults(await boundedJSON(answer));
      const expires=this.clock()+TTL;
      this.cache.set(parameters.key,{expires,value:response});
      while(this.cache.size>MAX_CACHE) this.cache.delete(this.cache.keys().next().value);
      const alarm=await this.ctx.storage.getAlarm();if(alarm===null || alarm>expires) await this.ctx.storage.setAlarm(expires);
    } catch {return error('provider_unavailable','Place search is temporarily unavailable.',503,30);}
    return json(response);
  }
  async fetch(request) {
    const p=input(request);if(p.failure) return p.failure;
    if(!this.env.GEOAPIFY_API_KEY) return error('not_configured','Place search is not configured.',503,60);
    this.purge();const cached=this.cache.get(p.key);if(cached) return json(cached.value);
    if(this.pending.has(p.key)) return (await this.pending.get(p.key)).clone();
    const operation=this.lookup(p);this.pending.set(p.key,operation);
    try {return (await operation).clone();} catch {return error('storage_unavailable','Place search is temporarily unavailable.',503,30);} finally {this.pending.delete(p.key);}
  }
}
export default {
  async fetch(request,env) {
    const url=new URL(request.url);
    if(request.method!=='GET') return error('method_not_allowed','Use GET.',405);
    if(url.pathname==='/map-config.json') {
      return json({schema:1,tiles:{enabled:true,url:'https://tile.openstreetmap.org/{z}/{x}/{y}.png',hidpi_url:'',max_zoom:19,max_active:4,attribution:'© OpenStreetMap contributors'},search:{enabled:!!env.GEOAPIFY_API_KEY,url:url.origin+'/v1/places?q={query}&lang={lang}',format:'geojson',min_interval_ms:1000,autocomplete:true,debounce_ms:550,min_chars:3,attribution,attribution_url:'https://www.geoapify.com/'}});
    }
    if(url.pathname!=='/v1/places') return error('not_found','Unknown endpoint.',404);
    const p=input(request);if(p.failure) return p.failure;
    try {return await env.SEARCH_BUDGET.get(env.SEARCH_BUDGET.idFromName('sincity-global-v1')).fetch(request);} catch {return error('service_unavailable','Place search is temporarily unavailable.',503,30);}
  }
};
