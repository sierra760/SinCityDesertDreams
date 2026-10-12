# Bounded Explore Lua bridge

The desktop-only `SCDDExploreLua` GDExtension embeds the official Lua 5.4.9
library. `source-lock.json` pins its archive and every vendored library file.
`lua.c` and `luac.c` (the executables), upstream build files and documentation
are not vendored. Unused OS/IO/package/debug/coroutine/UTF-8 libraries are not
linked. Lua's unmodified sources compile as C++ with exceptions: protected Lua
errors unwind C++ Godot value containers safely, including memory-limit errors.
No user-supplied bytecode is accepted. Godot Objects, Callables, userdata,
functions, pointers, cycles, mixed maps, sparse arrays, invalid UTF-8 and
nonfinite numeric data cannot cross the value boundary.

## Build

Use the exact official godot-cpp revision recorded in `source-lock.json` and
its template_release static libraries. `build_profile.json` enables
RefCounted, OS and Time. Prepare an isolated local checkout of the pinned
revision, regenerate its bindings with this profile and rebuild both macOS
universal and Windows x64 archives before invoking build.py. Older archives
built with RefCounted/OS do not contain Time and must not be reused. Keep the
shared binding checkout and its existing archives read-only. No geometry files change.

```sh
scons -C "$SCDD_GODOT_CPP" platform=macos target=template_release arch=universal macos_deployment_target=12.0 build_profile="$PWD/native/explore-lua/build_profile.json" -j4
scons -C "$SCDD_GODOT_CPP" platform=windows target=template_release arch=x86_64 use_mingw=yes build_profile="$PWD/native/explore-lua/build_profile.json" -j4
python3 native/explore-lua/build.py --godot-cpp "$SCDD_GODOT_CPP" --platform macos --platform windows
```

`--platform` is repeatable. macOS uses Xcode clang and produces an unsigned
universal arm64/x86_64 dylib, deployment target 12.0. Windows uses the existing
MinGW-w64 compiler and produces an unsigned x86_64 DLL with static C++ runtime
and no PE timestamp. No compiler installation is performed. Run the explicit
binding rebuild commands above against the private checkout first; build.py
then uses those matching archives without invoking SCons. Generated bindings,
objects and caches stay private and are not release inputs.
Use `--api-check` for native conformance builds: it defines upstream
`LUA_USE_APICHECK` without changing vendor files, checking actual Lua C stack
contracts even if the physical stack allocation happens to have spare space.
Recursive value copies reserve their temporary slots with `luaL_checkstack`
inside protected calls; stack growth allocation failures follow normal
transactional memory-fault cleanup. The maximum-depth copied-context regression
must pass with this configuration as well as the ordinary build.
Private source prefixes are mapped out of compiled objects. Intermediate objects
and exact invocation records live in `build/` and are not release inputs.

## Lifecycle and timing contract

`start(source, modules, context, seed)` compiles entry and every `.lua` source
in the immutable filename-to-UTF-8-text snapshot, then executes the entry and
retains its handler table. A successful start also returns a copied `handlers`
array of the initial validated names (at most five: on_start, on_tick,
on_event, on_resume, on_stop). The host schedules only that fixed inventory;
adding a handler later does not subscribe it. **It does not call on_start.** The host initializes
only while loading or a suspended Mods panel owns input, then separately
`dispatch("on_start", {}, context, budget)`. Top-level execution receives the
same 20,000 instruction and 1,500 microsecond ceiling. Compilation has source
and memory bounds and occurs outside tick scheduling; its time is not claimed
as instruction-counted execution. `require` uses precompiled closures only.

Native `dispatch(handler, payload, context, budget)` accepts `budget.instructions`
(default 20,000, clamped 0–20,000) and `budget.remaining_usec` (default 1,500,
clamped 0–1,500). The steady-clock deadline starts at native method entry before
input validation/copying. Hooks check at most every 200 instructions (and at
the exact remaining allowance); API entry and successful callback exit also
check it. The GDScript bridge accepts **absolute Godot** `budget.deadline_usec`
from `Time.get_ticks_usec()`, subtracts current time immediately before calling
native, and takes the smaller of that remainder and `remaining_usec`. Native
also retains the absolute deadline and compares it with the same engine Time
singleton, independently of its entry-anchored steady-clock relative cap. This
charges transport and validation time without comparing clock epochs. Native
requires all budget keys to be supported integers. If the
absolute deadline has already expired, the bridge returns `ok: true, deferred:
true` with empty output collections and zero counters, without entering or
closing the VM. Native likewise defers after validated host-side copying if
an absolute deadline expired before protected callback entry and the relative
budget is positive. Native deferral reports actual VM memory/native elapsed;
bridge-only `bytes_used: 0` means no native sample was taken. The host
keeps the callback queued and performs no output/progress commit. Explicit
relative `remaining_usec: 0` still enters the native deadline fault path, even
when an absolute deadline is also supplied. Fresh callback argument tables remain independent. A protected deadline check
immediately after copying prevents expired copying from entering the handler.
Once Lua callback execution begins,
deadline exhaustion remains a fault and the callback is never retried.
Initialization uses relative budgets only, synchronously under entry/panel
ownership; on_start cannot take the absolute pre-entry deferral path.
The host scheduler passes the session's remaining instructions/deadline, sums native instruction
counts, and owns the 100,000-instruction/1.5 ms aggregate tick limit. Successful
callbacks conservatively charge the unfinished hook quantum (at most 200
instructions), so short callbacks cannot evade aggregate accounting. The native
budget never extends a smaller allowance. Native-only tests use relative time.

`dispatch` calls lifecycle handlers with `(api, copied_context, copied_context)`;
`on_event` receives `(api, copied_event, copied_context)`. Authors need only the
first two arguments. Handlers return nil; any other return faults. Normal
`on_stop` exposes only log and progress operations and closes the VM. Fault
cleanup closes directly without invoking on_stop. `close()` is idempotent.
The native bridge allows at most eight live VMs and 8 MiB allocated per VM.

All replies contain `{ok, fault, commands, progress_writes, logs, instructions,
elapsed_usec, bytes_used}`; faults also have `diagnostic`. Faults discard all
three output collections before closing. Source diagnostics name only validated
package-relative chunks (`main.lua` for the entry), never local source paths.
Typical fault codes: `instruction_limit`, `deadline`, `memory_limit`,
`script_error`, `invalid_input`, `invalid_modules`, `invalid_handler`, `closed`,
`vm_limit`. The bridge reports `unavailable` for unsupported/missing libraries,
with no interpreter fallback or parse-time native class dependency.

## Copied context and API

`context.owner` must be a string and `context.generation` an integer, fixed for
that VM. Ordinary context fields are JSON-safe and share one 8 KiB envelope.
`context.progress` is a map <=64 KiB; `context.queries` is a <=64 KiB cache map.
Each input is validated before deep-copying. Depth is at most 8; ordinary
payloads have at most 1,024 nested entries and individual strings at most 4 KiB.
The two larger context envelopes allow 16,384 total entries, retaining the
1,024-member per-container limit. Bounds conservatively include JSON syntax
and numeric space; they may reject a value close to the byte ceiling.

See `api_v1.lua` for every positional binding, named command argument map,
cache lookup, timer/state shape, and lifecycle example contract. No API reads
Godot scene objects or writes Simulation. Owner and generation come from the
host's initial context, regardless of similarly named script options.
Commands are copied and buffered until callback success; the host validates
semantic fields and handles before executing them. Queries with no matching
cached answer queue a request and return pending. State writes form a map of
key-to-value replacements for the host progress adapter to apply only after callback success.
Lua empty tables decode as maps; contiguous 1-based integer tables decode as
arrays. A missing optional argument is omitted from the named args map.

## Verification

`game/tests/test_explore_mod_lua.gd` requires native availability and never skips
conformance. Run through `tools/run_tests.py` in its isolated project. Runtime
acceptance requires both macOS architectures; a Windows cross-build is not
Windows runtime acceptance. An unavailable-runtime acceptance process must
start without the library (a class already loaded in-process stays available).
The plugin bundles only supported desktop binaries and always includes Lua's
license. Third-party notices in game include the same full upstream license.

Native reply accounting includes `invalid_calls` (0–33, saturated, per dispatch)
for argument rejections that return before command buffering. Host semantic
`invalid_argument` completions join a rolling active-second window; the 33rd
invalid call disables the owner. Ordinary unavailable gestures and unreachable
or resource-limited requests do not count as malformed commands.

Host-only numeric timing fields split boundary validation, context copy, Lua
argument copy, payload copy and invocation. Thread CPU uses
`CLOCK_THREAD_CPUTIME_ID` on macOS and `GetThreadTimes` on Windows (which can
report zero for short intervals); -1 denotes unavailable measurement. Wall
clock deadlines remain authoritative, including when the OS deschedules the
thread. Timing is diagnostic, never an admission exemption or fault retry.


## Development tests

From the repository root, verify the source-lock and strict test-runner contracts:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m pytest -p no:cacheprovider tools/tests/test_explore_lua_source_lock.py tools/tests/test_run_tests.py
GODOT="$SCDD_GODOT" python3 tools/run_tests.py test_explore_mod_lua.gd test_explore_mod_scheduler.gd test_explore_mod_routine.gd
```

The runner creates an isolated project and unique user-data directory, imports
the project, and rejects engine, script or resource diagnostics even with a
zero exit status. Use `TEST_LOG_DIR` to retain logs. Native conformance includes
instruction/deadline/memory faults, forbidden operations, module isolation,
copied data, invalid input, transactional output discard and VM cleanup.
The other `test_explore_mod_` suites cover the host integration and examples.

Verify the ordinary and `--api-check` builds, both macOS architectures, and actual
Windows execution. Cross-compilation is build evidence only. Check ordinary
Explore with an unavailable runtime in a fresh process: an already loaded native
class cannot become unavailable by deleting a library during that process.
