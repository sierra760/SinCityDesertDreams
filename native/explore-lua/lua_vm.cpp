// SPDX-License-Identifier: GPL-3.0-or-later
#include "lua_vm.hpp"
#include "vendor/lua/lualib.h"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/time.hpp>
#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <vector>
#ifdef _WIN32
#include <windows.h>
#elif defined(__APPLE__)
#include <mach/mach.h>
#include <pthread.h>
#else
#include <time.h>
#endif
using namespace godot;
namespace {
constexpr size_t MEMORY = 8 * 1024 * 1024;
// One started callback may use this much of its own thread CPU time. Wall time
// lost to preemption is not charged; the backstop below still ends a stall.
constexpr int64_t CALLBACK_CPU_USEC = 1500;
constexpr int64_t WALL_BACKSTOP_USEC = 50000;
int active_vms = 0;
int64_t thread_cpu_usec() {
#ifdef _WIN32
 FILETIME created, exited, kernel, user;
 if(!GetThreadTimes(GetCurrentThread(), &created, &exited, &kernel, &user))return -1;
 ULARGE_INTEGER k,u;k.LowPart=kernel.dwLowDateTime;k.HighPart=kernel.dwHighDateTime;u.LowPart=user.dwLowDateTime;u.HighPart=user.dwHighDateTime;
 return (k.QuadPart+u.QuadPart)/10;
#elif defined(__APPLE__)
 // Rosetta 2 under-reports CLOCK_THREAD_CPUTIME_ID for translated x86_64 code
 // (about 0.5 ms per 20 ms busy); Mach thread accounting is exact on both.
 thread_basic_info_data_t info;mach_msg_type_number_t count=THREAD_BASIC_INFO_COUNT;
 if(thread_info(pthread_mach_thread_np(pthread_self()),THREAD_BASIC_INFO,(thread_info_t)&info,&count)!=KERN_SUCCESS)return -1;
 return int64_t(info.user_time.seconds+info.system_time.seconds)*1000000+info.user_time.microseconds+info.system_time.microseconds;
#else
 timespec t{};if(clock_gettime(CLOCK_THREAD_CPUTIME_ID,&t)!=0)return -1;
 return int64_t(t.tv_sec)*1000000+t.tv_nsec/1000;
#endif
}
// Enforcement needs a precise per-thread clock. Windows GetThreadTimes advances
// in whole scheduler-tick quanta, so a short callback could be charged ~15 ms;
// there it stays diagnostic only and the wall backstop alone bounds time.
int64_t enforced_cpu_usec() {
#ifdef _WIN32
 return -1;
#else
 return thread_cpu_usec();
#endif
}
struct Bounds { size_t bytes = 0, entries = 0, cap = 8192, entry_cap = 1024; std::set<const void *> seen; };
bool utf8(const char *s, size_t n) {
 for (size_t i=0;i<n;) {
  unsigned c=(unsigned char)s[i++]; if(c<128) continue;
  unsigned v=0, count=0, minimum=0;
  if(c>=0xc2 && c<=0xdf){v=c&31;count=1;minimum=128;}
  else if(c>=0xe0 && c<=0xef){v=c&15;count=2;minimum=2048;}
  else if(c>=0xf0 && c<=0xf4){v=c&7;count=3;minimum=65536;} else return false;
  if(i+count>n)return false;
  for(unsigned j=0;j<count;j++){unsigned b=(unsigned char)s[i++];if((b&192)!=128)return false;v=(v<<6)|(b&63);}
  if(v<minimum || v>0x10ffff || (v>=0xd800 && v<=0xdfff))return false;
 }
 return true;
}
bool unicode_ok(const String &s){for(int i=0;i<s.length();i++)if(s[i]>0x10ffff || (s[i]>=0xd800 && s[i]<=0xdfff))return false;return true;}
size_t json_string_bytes(const char*s,size_t n){size_t size=2;for(size_t i=0;i<n;i++){unsigned char c=s[i];size+=c<32?6:(c==34 || c==92?2:1);}return size;}
bool string_ok(const String &s, Bounds &b) {
 if(s.length()>4096)return false;
 for(int i=0;i<s.length();i++)if(s[i]>0x10ffff || (s[i]>=0xd800 && s[i]<=0xdfff))return false;
 auto u=s.utf8(); size_t n=u.length(); if(n>4096 || !utf8(u.get_data(), n))return false;
 b.bytes+=json_string_bytes(u.get_data(),n); return b.bytes<=b.cap;
}
bool valid(const Variant &v, Bounds &b, int depth=0) {
 if(depth>8 || ++b.entries>b.entry_cap)return false;
 b.bytes+=2; if(b.bytes>b.cap)return false;
 switch(v.get_type()){
 case Variant::NIL: return true;
 case Variant::BOOL: b.bytes+=5; break;
 case Variant::INT: case Variant::FLOAT: b.bytes+=24; if(!std::isfinite((double)v))return false; break;
 case Variant::STRING: return string_ok(v,b);
 case Variant::ARRAY:{Array a=v;if(a.size()>1024)return false;for(int i=0;i<a.size();i++)if(!valid(a[i],b,depth+1))return false;break;}
 case Variant::DICTIONARY:{Dictionary d=v;if(d.size()>1024)return false;Array keys=d.keys();for(int i=0;i<keys.size();i++){if(keys[i].get_type()!=Variant::STRING || !string_ok(keys[i],b) || !valid(d[keys[i]],b,depth+1))return false;}break;}
 default:return false;
 }
 return b.bytes<=b.cap;
}
void push(lua_State *L,const Variant &v) {
 // A table copy keeps its parent table/key on the C stack while recursing.
 // Context wrappers and multiple arguments can exceed LUA_MINSTACK even when
 // each validated envelope is depth <=8. Reserve at each recursive step;
 // every caller is inside lua_pcall, so growth/OOM raises a protected error.
 luaL_checkstack(L,3,"copied value stack");
 switch(v.get_type()){
 case Variant::NIL:lua_pushnil(L);break;
 case Variant::BOOL:lua_pushboolean(L,(bool)v);break;
 case Variant::INT:lua_pushinteger(L,(int64_t)v);break;
 case Variant::FLOAT:lua_pushnumber(L,(double)v);break;
 case Variant::STRING:{auto s=String(v).utf8();lua_pushlstring(L,s.get_data(),s.length());break;}
 case Variant::ARRAY:{Array a=v;lua_createtable(L,a.size(),0);for(int i=0;i<a.size();i++){push(L,a[i]);lua_rawseti(L,-2,i+1);}break;}
 case Variant::DICTIONARY:{Dictionary d=v;lua_createtable(L,0,d.size());Array k=d.keys();for(int i=0;i<k.size();i++){push(L,k[i]);push(L,d[k[i]]);lua_rawset(L,-3);}break;}
 default:luaL_error(L,"invalid_data");
 }
}
Variant read(lua_State *L,int idx,Bounds &b,int depth=0) {
 // lua_next temporarily pushes a key/value pair at every nested table.
 // Reserve those temporaries under the same protected callback as push().
 luaL_checkstack(L,3,"copied value stack");
 if(depth>8 || ++b.entries>b.entry_cap || (b.bytes+=2)>b.cap)luaL_error(L,"payload_limit");
 idx=lua_absindex(L,idx);
 switch(lua_type(L,idx)){
 case LUA_TNIL:return Variant();
 case LUA_TBOOLEAN:b.bytes+=5;return (bool)lua_toboolean(L,idx);
 case LUA_TNUMBER:{double n=lua_tonumber(L,idx);if(!std::isfinite(n))luaL_error(L,"invalid_data");b.bytes+=24;if(b.bytes>b.cap)luaL_error(L,"payload_limit");if(lua_isinteger(L,idx))return (int64_t)lua_tointeger(L,idx);return n;}
 case LUA_TSTRING:{size_t n;const char*s=lua_tolstring(L,idx,&n);if(n>4096 || (b.bytes+=json_string_bytes(s,n))>b.cap)luaL_error(L,"payload_limit");if(!utf8(s,n))luaL_error(L,"invalid_utf8");return String::utf8(s,n);}
 case LUA_TTABLE:{
  const void *id=lua_topointer(L,idx);if(!b.seen.insert(id).second)luaL_error(L,"cyclic_data");
  Dictionary map;std::map<int64_t,Variant> array;int count=0;lua_pushnil(L);
  while(lua_next(L,idx)){
   if(++count>1024)luaL_error(L,"payload_limit");
   if(lua_type(L,-2)==LUA_TSTRING){Variant k=read(L,-2,b,depth+1);map[k]=read(L,-1,b,depth+1);}
   else if(lua_isinteger(L,-2)){int64_t key=lua_tointeger(L,-2);if(key<1 || key>1024)luaL_error(L,"invalid_table");array[key]=read(L,-1,b,depth+1);}
   else luaL_error(L,"invalid_table");
   lua_pop(L,1);
  }
  b.seen.erase(id);
  if(!array.empty()){
   if(map.size() || array.rbegin()->first!=(int64_t)array.size())luaL_error(L,"invalid_table");
   Array a;for(auto &kv:array)a.append(kv.second);return a;
  }
  return map;
 }
 default:luaL_error(L,"invalid_data");return Variant();
 }
}
Dictionary reply(bool ok,const char*code){Dictionary d;d["ok"]=ok;d["code"]=code;return d;}
std::string bytes(const String &s){auto a=s.utf8();return std::string(a.get_data(),a.length());}
bool path_ok(const std::string &s){
 if(s.empty() || s.size()>128 || s[0]=='/' || s.find('\\')!=s.npos || s.find(':')!=s.npos)return false;
 size_t p=0;while(p<s.size()){size_t e=s.find('/',p);std::string part=s.substr(p,e==s.npos?s.size()-p:e-p);if(part.empty() || part=="." || part=="..")return false;if(e==s.npos)break;p=e+1;if(p==s.size())return false;}
 for(unsigned char c:s)if(c<32 || c>126)return false;return true;
}
struct Method { const char *name; const char *fields[4]; int min,max; bool query; };
const Method methods[]={
 {"world.player",{},0,0,true},{"world.nearby",{"options"},0,1,true},
 {"world.find_landmark",{"kind","options"},1,2,true},{"world.route",{"from","destination","options"},2,3,true},
 {"actor.spawn",{"kind","options"},2,2,false},{"actor.inspect",{"id"},1,1,true},
 {"actor.navigate",{"id","destination","options"},2,3,false},{"actor.wait",{"id","duration"},2,2,false},
 {"actor.wave",{"id"},1,1,false},{"actor.remove",{"id"},1,1,false},
 {"interaction.register",{"key","options"},2,2,false},{"interaction.unregister",{"key"},1,1,false},
 {"dialogue.show",{"key","speaker","text","choices"},4,4,false},{"dialogue.dismiss",{"key"},1,1,false},
 {"marker.set",{"key","options"},2,2,false},{"marker.remove",{"key"},1,1,false},
 {"objective.set",{"key","text","status"},3,3,false},{"objective.remove",{"key"},1,1,false},
 {"environment.set",{"channel","preset","parameters"},3,3,false},{"environment.clear",{},0,0,false},
 {"timer.after",{"key","delay"},2,2,false},{"timer.cancel",{"key"},1,1,false},
 {"state.get",{"key","default"},1,2,false},{"state.set",{"key","value"},2,2,false},
 {"utility.random",{},0,0,false},{"utility.log",{"message"},1,1,false}
};
}
void SCDDExploreLua::_bind_methods(){
 ClassDB::bind_method(D_METHOD("start","source","modules","context","seed"),&SCDDExploreLua::start);
 ClassDB::bind_method(D_METHOD("dispatch","handler","payload","context","budget"),&SCDDExploreLua::dispatch);
 ClassDB::bind_method(D_METHOD("close"),&SCDDExploreLua::close);
}
SCDDExploreLua *SCDDExploreLua::self(lua_State *L){return *static_cast<SCDDExploreLua **>(lua_getextraspace(L));}
void *SCDDExploreLua::allocate(void *ud,void *ptr,size_t old,size_t n){
 auto*s=static_cast<SCDDExploreLua*>(ud);if(!ptr)old=0;
 if(!n){std::free(ptr);s->memory-=old;return nullptr;}
 if(n>MEMORY || s->memory-old>MEMORY-n){s->memory_fault=true;return nullptr;}
 void*p=realloc(ptr,n);if(p)s->memory=s->memory-old+n;else s->memory_fault=true;return p;
}
void SCDDExploreLua::hook(lua_State *L,lua_Debug*){
 auto*s=self(L);s->instructions+=s->hook_interval;
 if(s->instructions>=s->allowance){s->fault="instruction_limit";luaL_error(L,"instruction_limit");}
 s->check_deadline();
 s->hook_interval=std::min(200,s->allowance-s->instructions);lua_sethook(L,hook,LUA_MASKCOUNT,s->hook_interval);
}
bool SCDDExploreLua::absolute_deadline_expired() const {
 if(!has_absolute_deadline)return false;
 // This is the engine Time singleton used by GDScript, not steady_clock's epoch.
 return absolute_deadline_usec<=0 || Time::get_singleton()->get_ticks_usec()>=static_cast<uint64_t>(absolute_deadline_usec);
}
void SCDDExploreLua::restart_clock(){begun=std::chrono::steady_clock::now();cpu_begun=enforced_cpu_usec();}
// The absolute host deadline only admits a callback; once entered it is judged
// by its own CPU budget and the wall backstop, never by shared-window wall time.
const char *SCDDExploreLua::time_fault() const {
 if(cpu_budget_usec<=0)return "deadline: callback budget is zero";
 if(std::chrono::steady_clock::now()-begun>=std::chrono::microseconds(WALL_BACKSTOP_USEC))return "deadline: wall-time backstop exhausted";
 if(cpu_begun<0)return nullptr;
 const int64_t cpu=enforced_cpu_usec();
 return cpu>=0 && cpu-cpu_begun>=cpu_budget_usec ? "deadline: thread CPU budget exhausted" : nullptr;
}
void SCDDExploreLua::check_deadline(){if(const char*why=time_fault()){fault="deadline";luaL_error(vm,"%s",why);}}
void SCDDExploreLua::begin(const Dictionary &budget){
 commands.clear();writes.clear();logs.clear();fault="";instructions=0;invalid_calls=0;context_copy_usec=0;lua_copy_usec=0;memory_fault=false;
 allowance=std::clamp((int64_t)budget.get("instructions",20000),(int64_t)0,(int64_t)20000);
 restart_clock();cpu_budget_usec=std::clamp((int64_t)budget.get("remaining_usec",CALLBACK_CPU_USEC),(int64_t)0,CALLBACK_CPU_USEC);
 has_absolute_deadline=budget.has("deadline_usec");
 absolute_deadline_usec=has_absolute_deadline ? int64_t(budget["deadline_usec"]) : 0;
 hook_interval=std::max(1,std::min(200,allowance));if(vm)lua_sethook(vm,hook,LUA_MASKCOUNT,hook_interval);
}
void SCDDExploreLua::close(){if(vm){lua_close(vm);vm=nullptr;--active_vms;}memory=0;handlers=api=LUA_NOREF;handler_names.clear();compiled.clear();cached.clear();loading.clear();context.clear();payload.clear();modules.clear();source="";}
Dictionary SCDDExploreLua::fail(const String &code,const String &detail){
 Dictionary r;r["ok"]=false;r["fault"]=code;r["diagnostic"]=detail;r["commands"]=Array();r["progress_writes"]=Dictionary();r["logs"]=Array();r["instructions"]=instructions;r["invalid_calls"]=invalid_calls;r["active_vms"]=active_vms;
 r["elapsed_usec"]=std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-begun).count();r["bytes_used"]=(int64_t)memory;close();return r;
}
Dictionary SCDDExploreLua::finish(int status){
 if(status==LUA_OK && memory_fault)return fail("memory_limit");
 if(status!=LUA_OK){
  String detail="Lua callback failed";if(lua_type(vm,-1)==LUA_TSTRING){size_t n;const char*s=lua_tolstring(vm,-1,&n);if(utf8(s,n)){size_t cut=std::min(n,(size_t)4096);while(cut && !utf8(s,cut))--cut;detail=String::utf8(s,cut);}}
  String code=fault.is_empty()?(status==LUA_ERRMEM || memory_fault ? String("memory_limit"):String("script_error")):fault;
  return fail(code,detail);
 }
 // Charge the unfinished hook quantum conservatively; short callbacks must
 // not appear free to the aggregate tick scheduler. Never exceed allowance.
 instructions=std::min(allowance,instructions+hook_interval);
 Dictionary r;r["ok"]=true;r["fault"]="";r["commands"]=commands.duplicate(true);r["progress_writes"]=writes.duplicate(true);r["logs"]=logs.duplicate(true);r["instructions"]=instructions;r["invalid_calls"]=invalid_calls;r["active_vms"]=active_vms;
 r["elapsed_usec"]=std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-begun).count();r["bytes_used"]=(int64_t)memory;lua_settop(vm,0);
 if(const char*why=time_fault())return fail("deadline",why);return r;
}
bool SCDDExploreLua::copy_context(const Dictionary &input){
 // Host context has separate bounded progress and cached observation envelopes.
 if(input.size()>32)return false;
 Dictionary c=input.duplicate();c.erase("progress");c.erase("queries");Bounds b;if(!valid(c,b))return false;
 Variant p=input.get("progress",Dictionary());Bounds pb;pb.cap=65536;pb.entry_cap=16384;if(p.get_type()!=Variant::DICTIONARY || !valid(p,pb))return false;
 Variant q=input.get("queries",Dictionary());Bounds qb;qb.cap=65536;qb.entry_cap=16384;if(q.get_type()!=Variant::DICTIONARY || !valid(q,qb))return false;
 if(input.get("owner",Variant()).get_type()!=Variant::STRING || input.get("generation",Variant()).get_type()!=Variant::INT)return false;
 const auto copying=std::chrono::steady_clock::now();
 context=input.duplicate(true);context_copy_usec=std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-copying).count();return true;
}
int SCDDExploreLua::safe_tostring(lua_State *L){
 int t=lua_type(L,1);if(t!=LUA_TSTRING && t!=LUA_TNUMBER && t!=LUA_TBOOLEAN && t!=LUA_TNIL)return luaL_error(L,"invalid_data");
 Bounds b;read(L,1,b);luaL_tolstring(L,1,nullptr);return 1;
}
int SCDDExploreLua::bounded_string(lua_State *L){
 // Original C function is private in upvalue; all inputs and outputs bounded.
 int n=lua_gettop(L);Bounds b;for(int i=1;i<=n;i++){int t=lua_type(L,i);if(t!=LUA_TSTRING && t!=LUA_TNUMBER)return luaL_error(L,"invalid_argument");read(L,i,b);}
 lua_pushvalue(L,lua_upvalueindex(1));lua_insert(L,1);lua_call(L,n,LUA_MULTRET);
 Bounds out;for(int i=1;i<=lua_gettop(L);i++)read(L,i,out);return lua_gettop(L);
}
int SCDDExploreLua::bounded_table(lua_State *L){
 int n=lua_gettop(L);Bounds b;for(int i=1;i<=n;i++)read(L,i,b);
 lua_pushvalue(L,lua_upvalueindex(1));lua_insert(L,1);lua_call(L,n,LUA_MULTRET);
 Bounds out;for(int i=1;i<=lua_gettop(L);i++)read(L,i,out);return lua_gettop(L);
}
void SCDDExploreLua::make_api(){
 lua_newtable(vm);
 for(size_t i=0;i<sizeof(methods)/sizeof(methods[0]);i++){
  std::string name=methods[i].name;auto dot=name.find('.');std::string area=name.substr(0,dot),method=name.substr(dot+1);
  lua_getfield(vm,-1,area.c_str());if(lua_isnil(vm,-1)){lua_pop(vm,1);lua_newtable(vm);lua_pushvalue(vm,-1);lua_setfield(vm,-3,area.c_str());}
  lua_pushinteger(vm,i);lua_pushcclosure(vm,binding,1);lua_setfield(vm,-2,method.c_str());lua_pop(vm,1);
 }
 api=luaL_ref(vm,LUA_REGISTRYINDEX);
}
int SCDDExploreLua::initialize(lua_State *L){
 auto*s=self(L);
 luaL_requiref(L,"_G",luaopen_base,1);lua_pop(L,1);
 const char*remove[]={"collectgarbage","dofile","loadfile","load","pcall","xpcall","getmetatable","setmetatable","rawset","rawget","rawequal","rawlen","print","warn",nullptr};
 for(auto p=remove;*p;p++){lua_pushnil(L);lua_setglobal(L,*p);}
 lua_pushcfunction(L,safe_tostring);lua_setglobal(L,"tostring");
 lua_getglobal(L,"tonumber");lua_pushcclosure(L,bounded_string,1);lua_setglobal(L,"tonumber");
 luaL_requiref(L,"math",luaopen_math,0);lua_newtable(L);
 const char*maths[]={"abs","ceil","floor","min","max","sqrt","sin","cos","tan","acos","asin","atan","exp","log","deg","rad","fmod","modf","tointeger","type","ult","pi",nullptr};
 for(auto p=maths;*p;p++){lua_getfield(L,-2,*p);lua_setfield(L,-2,*p);}lua_setglobal(L,"math");lua_pop(L,1);
 luaL_requiref(L,"string",luaopen_string,0);lua_newtable(L);
 const char*strings[]={"byte","char","len","lower","upper","reverse","sub",nullptr};
 for(auto p=strings;*p;p++){lua_getfield(L,-2,*p);lua_pushcclosure(L,bounded_string,1);lua_setfield(L,-2,*p);}
 // luaopen_string installs a metatable pointing at its full library. Replace
 // that __index as well; otherwise ("x"):rep / :dump escape the allowlist.
 lua_pushliteral(L,"");lua_getmetatable(L,-1);lua_pushvalue(L,-3);lua_setfield(L,-2,"__index");lua_pop(L,2);
 lua_setglobal(L,"string");lua_pop(L,1);
 luaL_requiref(L,"table",luaopen_table,0);lua_newtable(L);
 const char*tables[]={"insert","remove","concat",nullptr};
 for(auto p=tables;*p;p++){lua_getfield(L,-2,*p);lua_pushcclosure(L,bounded_table,1);lua_setfield(L,-2,*p);}lua_setglobal(L,"table");lua_pop(L,1);
 lua_pushcfunction(L,require_module);lua_setglobal(L,"require");s->make_api();
 // Source compilation happens once, before executing any script. No filesystem.
 Array keys=s->modules.keys();for(int i=0;i<keys.size();i++){
  std::string path=bytes(keys[i]);if(path.size()<4 || path.substr(path.size()-4)!=".lua")continue;
  auto text=String(s->modules[keys[i]]).utf8();std::string chunk="@"+path;
  int status=luaL_loadbufferx(L,text.get_data(),text.length(),chunk.c_str(),"t");if(status!=LUA_OK)return lua_error(L);
  s->compiled[path]=luaL_ref(L,LUA_REGISTRYINDEX);
 }
 auto text=s->source.utf8();if(luaL_loadbufferx(L,text.get_data(),text.length(),"@main.lua","t")!=LUA_OK)return lua_error(L);
 // Compilation is memory bounded, not instruction/deadline metered; entry is.
 s->restart_clock();s->check_deadline();
 lua_call(L,0,1);
 if(!lua_istable(L,-1))return luaL_error(L,"entry must return a handler table");
 lua_pushnil(L);while(lua_next(L,-2)){
  if(lua_type(L,-2)!=LUA_TSTRING || !lua_isfunction(L,-1))return luaL_error(L,"invalid handler table");
  size_t n;const char *k=lua_tolstring(L,-2,&n);std::string name(k,n);if(name!="on_start" && name!="on_tick" && name!="on_event" && name!="on_resume" && name!="on_stop")return luaL_error(L,"unknown handler");s->handler_names.append(String(k));lua_pop(L,1);
 }
 s->handlers=luaL_ref(L,LUA_REGISTRYINDEX);s->check_deadline();return 0;
}
int SCDDExploreLua::require_module(lua_State *L){
 auto*s=self(L);s->check_deadline();if(lua_type(L,1)!=LUA_TSTRING)return luaL_error(L,"invalid module name");
 size_t n;const char*raw=lua_tolstring(L,1,&n);if(n>128)return luaL_error(L,"invalid module name");std::string name(raw,n);
 if(name.size()<4 || name.substr(name.size()-4)!=".lua"){std::replace(name.begin(),name.end(),'.','/');name+=".lua";}
 if(!path_ok(name))return luaL_error(L,"invalid module name");
 auto c=s->cached.find(name);if(c!=s->cached.end()){lua_rawgeti(L,LUA_REGISTRYINDEX,c->second);return 1;}
 auto m=s->compiled.find(name);if(m==s->compiled.end())return luaL_error(L,"module unavailable: %s",name.c_str());
 if(!s->loading.insert(name).second)return luaL_error(L,"module cycle: %s",name.c_str());
 lua_rawgeti(L,LUA_REGISTRYINDEX,m->second);lua_call(L,0,1);if(lua_isnil(L,-1)){lua_pop(L,1);lua_pushboolean(L,true);}
 lua_pushvalue(L,-1);s->cached[name]=luaL_ref(L,LUA_REGISTRYINDEX);s->loading.erase(name);return 1;
}
int SCDDExploreLua::invoke(lua_State *L){
 auto*s=self(L);s->check_deadline();if(s->allowance<=0){s->fault="instruction_limit";return luaL_error(L,"instruction_limit");}
 lua_rawgeti(L,LUA_REGISTRYINDEX,s->handlers);auto h=s->handler.utf8();lua_getfield(L,-1,h.get_data());lua_remove(L,-2);
 if(lua_isnil(L,-1)){lua_pop(L,1);return 0;}
 lua_rawgeti(L,LUA_REGISTRYINDEX,s->api);
 const auto copying=std::chrono::steady_clock::now();
 push(L,s->handler=="on_event"?s->payload:s->context);push(L,s->context);
 s->lua_copy_usec=std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-copying).count();
 // Both independent snapshots are complete; do not enter a handler after expiry.
 s->check_deadline();
 lua_call(L,3,1);if(!lua_isnil(L,-1))return luaL_error(L,"handlers must return no value");lua_pop(L,1);s->check_deadline();return 0;
}
Dictionary SCDDExploreLua::start(const String &entry,const Dictionary &sources,const Dictionary &input,int64_t seed){
 close();begin(Dictionary());serial=0;stopping=false;random_state=(uint64_t)seed;if(!random_state)random_state=1;
 if(entry.length()>131072 || !unicode_ok(entry) || entry.utf8().length()>131072 || !copy_context(input))return fail("invalid_input");
 if(sources.size()>32)return fail("invalid_modules");Array keys=sources.keys();size_t total=0;
 for(int i=0;i<keys.size();i++){
  if(keys[i].get_type()!=Variant::STRING || String(keys[i]).length()>128 || !unicode_ok(keys[i]) || sources[keys[i]].get_type()!=Variant::STRING || String(sources[keys[i]]).length()>131072 || !unicode_ok(sources[keys[i]]) || !path_ok(bytes(keys[i])))return fail("invalid_modules");
  auto text=String(sources[keys[i]]).utf8();if(text.length()>131072 || (total+=text.length())>1048576)return fail("invalid_modules");
 }
 owner=input["owner"];generation=input["generation"];modules=sources.duplicate(true);source=entry;
 if(active_vms>=8)return fail("vm_limit");
 vm=lua_newstate(allocate,this);if(!vm)return fail("memory_limit");++active_vms;*static_cast<SCDDExploreLua **>(lua_getextraspace(vm))=this;
 lua_sethook(vm,hook,LUA_MASKCOUNT,hook_interval);lua_pushcfunction(vm,initialize);int status=lua_pcall(vm,0,0,0);modules.clear();source="";Dictionary result=finish(status);if((bool)result["ok"])result["handlers"]=handler_names.duplicate();return result;
}
Dictionary SCDDExploreLua::dispatch(const String &name,const Dictionary &event,const Dictionary &input,const Dictionary &budget){
 const auto entered=std::chrono::steady_clock::now();
 const auto cpu_entered=thread_cpu_usec();
 Bounds budget_bounds;
 if(budget.size()>3 || !valid(budget,budget_bounds) ||
    (budget.has("instructions") && budget["instructions"].get_type()!=Variant::INT) ||
    (budget.has("remaining_usec") && budget["remaining_usec"].get_type()!=Variant::INT) ||
    (budget.has("deadline_usec") && budget["deadline_usec"].get_type()!=Variant::INT)){
  begin(Dictionary());return fail("invalid_input");
 }
 Array budget_keys=budget.keys();
 for(int i=0;i<budget_keys.size();i++){
  String key=budget_keys[i];
  if(key!="instructions" && key!="remaining_usec" && key!="deadline_usec"){begin(Dictionary());return fail("invalid_input");}
 }
 begin(budget);begun=entered;if(cpu_begun>=0)cpu_begun=cpu_entered;if(!vm)return fail("closed");
 if(name!="on_start" && name!="on_tick" && name!="on_event" && name!="on_resume" && name!="on_stop")return fail("invalid_handler");
 const auto validation_started=std::chrono::steady_clock::now();
 Bounds b;if(!valid(event,b) || !copy_context(input) || String(input["owner"])!=owner || (int64_t)input["generation"]!=generation)return fail("invalid_input");
 const auto validated=std::chrono::steady_clock::now();
 handler=name;payload=event.duplicate(true);stopping=name=="on_stop";
 const auto copied=std::chrono::steady_clock::now();
 // Validate all inputs first. No Lua callback has executed: retain queued work
 // if the absolute host window expired during transport or host-side copying.
 // An explicitly exhausted relative budget still takes the terminal path.
 if((int64_t)budget.get("remaining_usec",1500)>0 && absolute_deadline_expired()){
  Dictionary deferred;deferred["ok"]=true;deferred["deferred"]=true;deferred["fault"]="";
  deferred["commands"]=Array();deferred["progress_writes"]=Dictionary();deferred["logs"]=Array();
  deferred["instructions"]=0;deferred["invalid_calls"]=0;deferred["active_vms"]=active_vms;
  deferred["elapsed_usec"]=std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-entered).count();deferred["bytes_used"]=(int64_t)memory;
  return deferred;
 }
 lua_pushcfunction(vm,invoke);int status=lua_pcall(vm,0,0,0);
 const auto invoked=std::chrono::steady_clock::now();
 Dictionary result=finish(status);
 Dictionary timing;
 timing["validation_usec"]=std::max(int64_t(0),int64_t(std::chrono::duration_cast<std::chrono::microseconds>(validated-validation_started).count())-context_copy_usec);
 timing["context_copy_usec"]=context_copy_usec;
 timing["lua_copy_usec"]=lua_copy_usec;
 timing["payload_copy_usec"]=std::chrono::duration_cast<std::chrono::microseconds>(copied-validated).count();
 timing["invocation_usec"]=std::max(int64_t(0),int64_t(std::chrono::duration_cast<std::chrono::microseconds>(invoked-copied).count())-lua_copy_usec);
 const auto cpu_end=thread_cpu_usec();timing["thread_cpu_usec"]=cpu_entered<0 || cpu_end<0 ? int64_t(-1):cpu_end-cpu_entered;
 result["timing"]=timing;
 if(stopping)close();return result;
}
int SCDDExploreLua::binding(lua_State *L){
 auto*s=self(L);s->check_deadline();const Method&m=methods[lua_tointeger(L,lua_upvalueindex(1))];std::string name=m.name;
 int n=lua_gettop(L);if(n<m.min || n>m.max){s->invalid_calls=std::min(33,s->invalid_calls+1);push(L,reply(false,"invalid_argument"));return 1;}
 Bounds b;Array positional;Dictionary args;for(int i=1;i<=n;i++){Variant v=read(L,i,b);positional.append(v);args[m.fields[i-1]]=v;}
 Bounds argument_bounds;if(!valid(args,argument_bounds))return luaL_error(L,"payload_limit");
 if(s->stopping && name!="utility.log" && name!="state.set" && name!="state.get"){push(L,reply(false,"unavailable"));return 1;}
 if(name=="utility.random"){
  s->random_state^=s->random_state>>12;s->random_state^=s->random_state<<25;s->random_state^=s->random_state>>27;
  lua_pushnumber(L,((s->random_state*2685821657736338717ULL)>>11)*(1.0/9007199254740992.0));return 1;
 }
 if(name=="utility.log"){
  if(positional[0].get_type()!=Variant::STRING){s->invalid_calls=std::min(33,s->invalid_calls+1);push(L,reply(false,"invalid_argument"));return 1;}
  if(s->logs.size()>=32){push(L,reply(false,"quota_exceeded"));return 1;}
  s->logs.append(positional[0]);push(L,reply(true,"ok"));return 1;
 }
 if(name=="state.get" || name=="state.set"){
  if(positional[0].get_type()!=Variant::STRING || String(positional[0]).is_empty()){s->invalid_calls=std::min(33,s->invalid_calls+1);push(L,reply(false,"invalid_argument"));return 1;}
  String key=positional[0];Dictionary progress=s->context.get("progress",Dictionary());
  if(name=="state.get"){push(L,s->writes.get(key,progress.get(key,n==2?positional[1]:Variant())));return 1;}
  Dictionary candidate=progress.duplicate(true);Array keys=s->writes.keys();for(int i=0;i<keys.size();i++)candidate[keys[i]]=s->writes[keys[i]];candidate[key]=positional[1];
  Bounds pb;pb.cap=65536;pb.entry_cap=16384;if(!valid(candidate,pb) || s->writes.size()>=32 && !s->writes.has(key)){push(L,reply(false,"quota_exceeded"));return 1;}
  s->writes[key]=positional[1];push(L,reply(true,"ok"));return 1;
 }
 if(name=="timer.after"){
  if(positional[0].get_type()!=Variant::STRING || (positional[1].get_type()!=Variant::INT && positional[1].get_type()!=Variant::FLOAT) || (double)positional[1]<0.1 || (double)positional[1]>86400){s->invalid_calls=std::min(33,s->invalid_calls+1);push(L,reply(false,"invalid_argument"));return 1;}
 }
 if(name=="dialogue.show"){
  if(positional[0].get_type()!=Variant::STRING || positional[1].get_type()!=Variant::STRING || positional[2].get_type()!=Variant::STRING || String(positional[2]).utf8().length()>2048 || (positional[3].get_type()!=Variant::ARRAY && positional[3].get_type()!=Variant::DICTIONARY)){s->invalid_calls=std::min(33,s->invalid_calls+1);push(L,reply(false,"invalid_argument"));return 1;}
  if(positional[3].get_type()==Variant::ARRAY && Array(positional[3]).size()>8 || positional[3].get_type()==Variant::DICTIONARY && Dictionary(positional[3]).size()>0){s->invalid_calls=std::min(33,s->invalid_calls+1);push(L,reply(false,"invalid_argument"));return 1;}
 }
 if(m.query){
  Dictionary queries=s->context.get("queries",Dictionary());Variant cache=queries.get(m.name,Array());
  if(cache.get_type()==Variant::ARRAY){Array entries=cache;for(int i=0;i<std::min((int)entries.size(),64);i++){
   if(entries[i].get_type()!=Variant::DICTIONARY)continue;Dictionary e=entries[i];if(e.get("args",Variant())==Variant(positional)){
    Variant result=e.get("result",Variant());Bounds rb;if(result.get_type()!=Variant::DICTIONARY || !valid(result,rb))return luaL_error(L,"invalid_query_cache");
    Dictionary d=result;Variant data=d.get("data",Variant());if(data.get_type()==Variant::ARRAY && Array(data).size()>64)return luaL_error(L,"query_result_limit");push(L,result);return 1;
   }
  }}
 }
 if(s->commands.size()>=32){push(L,reply(false,"quota_exceeded"));return 1;}
 int64_t id=++s->serial;Dictionary command;command["request_id"]=id;command["kind"]=m.name;command["args"]=args;command["owner"]=s->owner;command["generation"]=s->generation;s->commands.append(command);
 Dictionary result=reply(true,"pending");result["request_id"]=id;push(L,result);return 1;
}
