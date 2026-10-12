// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>
#include <chrono>
#include <map>
#include <set>
#include <string>
#include "vendor/lua/lua.h"
#include "vendor/lua/lauxlib.h"

namespace godot {
class SCDDExploreLua : public RefCounted {
 GDCLASS(SCDDExploreLua, RefCounted)
 lua_State *vm = nullptr;
 size_t memory = 0;
 bool memory_fault = false, stopping = false;
 int handlers = LUA_NOREF, api = LUA_NOREF;
 Array handler_names;
 int invalid_calls = 0;
 int64_t context_copy_usec = 0, lua_copy_usec = 0;
 int instructions = 0, allowance = 20000, hook_interval = 200;
 uint64_t random_state = 1, serial = 0;
 std::chrono::steady_clock::time_point begun, deadline;
 bool has_absolute_deadline = false;
 int64_t absolute_deadline_usec = 0;
 std::map<std::string, int> compiled, cached;
 std::set<std::string> loading;
 Dictionary context, payload, writes;
 Array commands, logs;
 String owner, fault;
 int64_t generation = 0;
 String source, handler;
 Dictionary modules;
 static void *allocate(void *, void *, size_t, size_t);
 static void hook(lua_State *, lua_Debug *);
 static SCDDExploreLua *self(lua_State *);
 static int initialize(lua_State *);
 static int invoke(lua_State *);
 static int require_module(lua_State *);
 static int binding(lua_State *);
 static int bounded_string(lua_State *);
 static int bounded_table(lua_State *);
 static int safe_tostring(lua_State *);
 void make_api();
 void begin(const Dictionary &budget);
 Dictionary finish(int status);
 Dictionary fail(const String &code, const String &detail = "");
 bool copy_context(const Dictionary &input);
 bool absolute_deadline_expired() const;
 bool deadline_expired() const;
 void check_deadline();
protected:
 static void _bind_methods();
public:
 Dictionary start(const String &source, const Dictionary &modules, const Dictionary &context, int64_t seed);
 Dictionary dispatch(const String &handler, const Dictionary &payload, const Dictionary &context, const Dictionary &budget);
 void close();
 ~SCDDExploreLua() override { close(); }
};
}
