// SPDX-License-Identifier: GPL-3.0-or-later
#include "lua_vm.hpp"
#include <godot_cpp/godot.hpp>
#include <godot_cpp/core/class_db.hpp>
using namespace godot;
static void initialize(ModuleInitializationLevel level){if(level==MODULE_INITIALIZATION_LEVEL_SCENE)ClassDB::register_class<SCDDExploreLua>();}
static void uninitialize(ModuleInitializationLevel){}
extern "C" GDExtensionBool GDE_EXPORT scdd_explore_lua_init(GDExtensionInterfaceGetProcAddress get_proc_address,GDExtensionClassLibraryPtr library,GDExtensionInitialization *initialization){
 GDExtensionBinding::InitObject init(get_proc_address,library,initialization);init.register_initializer(initialize);init.register_terminator(uninitialize);init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);return init.init();
}
