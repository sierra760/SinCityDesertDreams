#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Build pinned Lua as C++ so protected Lua errors unwind host C++ values safely.
No native source modifications, Lua dynamic loaders, interpreters or compiler tools.
The existing pinned binding checkout is read-only unless --scons is requested.
"""
import argparse, hashlib, json, pathlib, shutil, subprocess
p=argparse.ArgumentParser()
p.add_argument('--godot-cpp',type=pathlib.Path,required=True)
p.add_argument('--platform',action='append',choices=['macos','windows'])
p.add_argument('--scons')
p.add_argument('--api-check',action='store_true',help='Enable upstream Lua C API assertions for conformance testing')
p.add_argument('--build-dir',type=pathlib.Path,help='Intermediate objects and command record; default native/explore-lua/build')
a=p.parse_args()
root=pathlib.Path(__file__).resolve().parent
cpp=a.godot_cpp.resolve()
lock=json.loads((root/'source-lock.json').read_text())
assert subprocess.check_output(['git','-C',str(cpp),'rev-parse','HEAD'],text=True).strip()==lock['godot_cpp']['revision'], 'Wrong godot-cpp revision'
vendor=root/'vendor/lua'
expected=lock['lua']['files']
assert {p.name for p in vendor.iterdir()} == set(expected), 'Unexpected/missing Lua source file'
for name, digest in expected.items():
 assert hashlib.sha256((vendor/name).read_bytes()).hexdigest()==digest, f'Lua source hash mismatch: {name}'
out=root.parents[1]/'game/addons/scdd_explore_lua/bin';out.mkdir(parents=True,exist_ok=True)
build=(a.build_dir or root/'build').resolve();build.mkdir(parents=True,exist_ok=True)
includes=['-I'+str(cpp/x) for x in ['include','gen/include','gdextension']]
api_flags=['-DLUA_USE_APICHECK'] if a.api_check else []
prefix=[f'-ffile-prefix-map={root.parents[1]}=.',f'-ffile-prefix-map={cpp}=godot-cpp']
sources=[root/'lua_vm.cpp',root/'register_types.cpp',*sorted((root/'vendor/lua').glob('*.c'))]
# Disabled libraries are never opened; omit even their code from the binary.
sources=[s for s in sources if s.name not in ['linit.c','liolib.c','loslib.c','loadlib.c','ldblib.c','lcorolib.c','lutf8lib.c']]
commands=[]
for platform in a.platform or ['macos','windows']:
 arch='universal' if platform=='macos' else 'x86_64'
 lib=cpp/'bin'/f'libgodot-cpp.{platform}.template_release.{arch}.a'
 if not lib.exists():
  if not a.scons: raise SystemExit(f'Missing {lib}; pass --scons to build bindings')
  cmd=[a.scons,'-C',str(cpp),f'platform={platform}','target=template_release',f'arch={arch}',f'build_profile={root / "build_profile.json"}','-j4']
  cmd+=['macos_deployment_target=12.0'] if platform=='macos' else ['use_mingw=yes']
  subprocess.run(cmd,check=True)
 if platform=='macos':
  sdk=subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True).strip()
  compiler=['xcrun','--sdk','macosx','clang++']
  flags=['-arch','arm64','-arch','x86_64','-isysroot',sdk,'-mmacosx-version-min=12.0']
  target=out/'libSCDDExploreLua.dylib'
  link=['-dynamiclib','-Wl,-install_name,@rpath/libSCDDExploreLua.dylib']
 else:
  compiler=[shutil.which('x86_64-w64-mingw32-g++') or 'x86_64-w64-mingw32-g++'];flags=[]
  target=out/'SCDDExploreLua.windows.x86_64.dll'
  link=['-shared','-static','-static-libgcc','-static-libstdc++','-s','-Wl,--no-insert-timestamp']
 objects=[]
 for src in sources:
  obj=build/f'{platform}-{src.stem}.o'
  cmd=[*compiler,'-x','c++','-std=c++17','-O2','-fvisibility=hidden','-fexceptions',*api_flags,*flags,*prefix,*includes,'-c',str(src),'-o',str(obj)]
  subprocess.run(cmd,check=True);commands.append(cmd);objects.append(obj)
 cmd=[*compiler,*flags,*link,*map(str,objects),str(lib),'-o',str(target)]
 subprocess.run(cmd,check=True);commands.append(cmd)
 print(f'Built unsigned {target.name}: sha256={hashlib.sha256(target.read_bytes()).hexdigest()}')
(build/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
