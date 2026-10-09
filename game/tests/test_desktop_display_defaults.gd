# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Desktop first-launch display contract: Windows/X11 HiDPI derived from DPI,
## restored-window placement, maximized persistence, first-run graphics
## defaults and the terrain tile cache living outside user://.
extends "res://tests/test_case.gd"
const Layout := preload("res://scripts/ui/display_layout.gd")
const Platform := preload("res://scripts/platform/mobile_platform.gd")
const PREFS := "user://test_desktop_display_defaults.cfg"

func test_windows_and_x11_backing_scale_comes_from_dpi() -> void:
	# Godot 4.6 screen_get_scale() is 1.0 on Windows/X11; DPI carries the scale.
	for row in [[96,1.0],[120,1.25],[144,1.5],[168,1.75],[192,2.0],[110,1.25],[72,1.0],[400,3.0]]:
		check_eq(Layout.backing_from_readings("Windows","Windows",1.0,row[0]),row[1],"Windows %d dpi" % row[0])
	check_eq(Layout.backing_from_readings("Linux","X11",1.0,192),2.0,"X11 uses monitor DPI")
	check_eq(Layout.backing_from_readings("Linux","X11",1.0,93),1.0,"ordinary X11 monitor stays 100%")
	check_eq(Layout.backing_from_readings("Windows","Windows",1.0,0),1.0,"missing DPI reading keeps 1.0")

func test_native_scale_platforms_are_unchanged() -> void:
	check_eq(Layout.backing_from_readings("Linux","Wayland",1.0,192),1.0,"Wayland reports its own scale")
	check_eq(Layout.backing_from_readings("Linux","Wayland",2.0,192),2.0)
	check_eq(Layout.backing_from_readings("macOS","macOS",2.0,220),2.0)
	check_eq(Layout.backing_from_readings("macOS","macOS",1.0,192),1.0,"macOS 1x display is not DPI-guessed")
	check_eq(Layout.backing_from_readings("iOS","iOS",3.0,460),3.0)
	check_eq(Layout.backing_from_readings("Windows","Windows",1.5,192),1.5,"a native scale reading wins")
	check_eq(Layout.backing_from_readings("Linux","headless",1.0,96),1.0)
	check_eq(Layout.backing_from_readings("Windows","Windows",NAN,192),2.0,"invalid scale reading is treated as 1.0")

func test_derived_windows_scale_keeps_ui_at_100_percent() -> void:
	var backing := Layout.backing_from_readings("Windows","Windows",1.0,192)
	var metrics: Dictionary = Layout.resolve_scale(Vector2i(2560,1600),backing,0)
	check_eq(metrics["scale"],2.0)
	check_eq(metrics["logical_rect"].size,Vector2(1280,800),"200% Windows display shows 1280×800 points")
	check_eq(metrics["effective_percent"],100.0)
	var layout := Layout.new()
	layout.refresh_with_metrics(Vector2i(2880,1620),Layout.backing_from_readings("Windows","Windows",1.0,144))
	check_eq(layout.metrics["backing_scale"],1.5)
	check_eq(layout.logical_rect().size,Vector2(1920,1080))
	check_eq(layout.windowed_size,Vector2(1920,1080),"windowed size is recorded in points")
	layout.free()

func test_restored_window_is_centered_inside_usable_area() -> void:
	check_eq(Layout.centered_window_rect(Vector2i(1280,800),Rect2i(100,0,1920,1080)),Rect2i(420,140,1280,800))
	check_eq(Layout.centered_window_rect(Vector2i(2560,1600),Rect2i(0,25,1920,1015)),Rect2i(0,25,1920,1015),"oversized restore is clamped to the usable area")
	var secondary := Layout.centered_window_rect(Vector2i(1000,700),Rect2i(-1920,-200,1920,1200))
	check(Rect2i(-1920,-200,1920,1200).encloses(secondary),"a monitor left of the primary keeps the window on screen")
	check_eq(Layout.centered_window_rect(Vector2i(800,600),Rect2i()),Rect2i(0,0,800,600),"no usable reading leaves the size alone")

func test_maximized_drawable_is_not_recorded_as_windowed_size() -> void:
	var layout := Layout.new()
	layout.refresh_with_metrics(Vector2i(2000,1280),2.0)
	check_eq(layout.windowed_size,Vector2(1000,640))
	layout.maximized = true
	layout.refresh_with_metrics(Vector2i(3024,1890),2.0)
	check_eq(layout.windowed_size,Vector2(1000,640),"maximized size never replaces the restore size")
	layout.maximized = false
	layout.refresh_with_metrics(Vector2i(1800,1200),2.0)
	check_eq(layout.windowed_size,Vector2(900,600))
	layout.free()

func test_maximized_preference_round_trips() -> void:
	check_eq(ViewPreferences.sanitize({})["maximized"],false)
	check_eq(ViewPreferences.sanitize({"maximized":"yes"})["maximized"],false)
	check_eq(ViewPreferences.write({"maximized":true,"windowed_size":Vector2(1100,700)},PREFS),OK)
	var loaded := ViewPreferences.read(PREFS)
	check_eq(loaded["maximized"],true)
	check_eq(loaded["windowed_size"],Vector2(1100,700))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))

func test_desktop_first_run_graphics_defaults() -> void:
	var integrated := RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU
	var discrete := RenderingDevice.DEVICE_TYPE_DISCRETE_GPU
	check_eq(Platform.presentation_defaults({"os_name":"macOS","backing_scale":2.0,"video_adapter_type":integrated}),{"render_quality":"high","render_scale":75},"Retina renders at 75%; Apple GPUs keep High")
	check_eq(Platform.presentation_defaults({"os_name":"macOS","backing_scale":1.0,"video_adapter_type":integrated}),{"render_quality":"high","render_scale":100})
	check_eq(Platform.presentation_defaults({"os_name":"Windows","backing_scale":1.5,"video_adapter_type":integrated}),{"render_quality":"balanced","render_scale":100})
	check_eq(Platform.presentation_defaults({"os_name":"Windows","backing_scale":2.0,"video_adapter_type":discrete}),{"render_quality":"high","render_scale":75})
	check_eq(Platform.presentation_defaults({"os_name":"Linux","backing_scale":2.0,"video_adapter_type":integrated}),{"render_quality":"balanced","render_scale":75})
	check_eq(Platform.presentation_defaults({"os_name":"Linux","backing_scale":1.0,"video_adapter_type":discrete}),{"render_quality":"high","render_scale":100})
	check_eq(Platform.presentation_defaults({"os_name":"iOS","backing_scale":1.0,"video_adapter_type":discrete}),{"render_quality":"balanced","render_scale":75},"mobile defaults unchanged")

func test_desktop_defaults_apply_only_to_absent_keys() -> void:
	var environment := {"os_name":"Windows","backing_scale":2.0,"video_adapter_type":RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU}
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var first: Dictionary = Platform.read_view_preferences(PREFS,environment)
	check_eq(first.render_quality,"balanced","first run without a display file")
	check_eq(first.render_scale,75)
	var partial := ConfigFile.new()
	partial.set_value(ViewPreferences.SECTION,"labels",false)
	check_eq(partial.save(PREFS),OK)
	var other: Dictionary = Platform.read_view_preferences(PREFS,environment)
	check_eq(other.render_quality,"balanced","unrelated saved keys still receive defaults")
	check_eq(other.render_scale,75)
	check_eq(other.labels,false)
	check_eq(ViewPreferences.write({"render_quality":"high","render_scale":100},PREFS),OK)
	var explicit: Dictionary = Platform.read_view_preferences(PREFS,environment)
	check_eq(explicit.render_quality,"high","explicit player choice preserved")
	check_eq(explicit.render_scale,100)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))

func test_terrain_tile_cache_lives_in_the_os_cache() -> void:
	var base := TerrainTileCache.cache_base()
	var root := TerrainTileCache.default_root()
	check(not base.is_empty(),"desktop and iOS provide an OS cache directory")
	check(root.begins_with(base + "/"),"default root sits below OS.get_cache_dir()")
	check(not root.begins_with("user://"),"tiles never land in the Files-visible user directory")
	check(not root.begins_with(ProjectSettings.globalize_path("user://")))
	check_eq(root,base.path_join(TerrainTileCache.app_dir_name()).path_join("terrain_tiles_v1"))
	check_eq(TerrainTileCache.root_for("","App"),"user://terrain_tiles_v1","missing OS cache falls back")
	check_eq(TerrainTileCache.root_for(base,".."),"user://terrain_tiles_v1","unsafe app directory falls back")
	var resource := {"source":"worldcover","tile":"N36W117"}
	var span := {"offset":10,"length":4}
	var identity := {"etag":"\"v1\"","size":100}
	var cache := TerrainTileCache.new()
	var published := cache.publish(resource,span,identity,PackedByteArray([1,2,3,4]))
	check(published.ok,"an unconfigured cache publishes to the OS cache root")
	if published.ok:
		check(String(published.body_path).begins_with(root + "/"))
		check(cache.lookup(resource,span,identity).ok)
	check(cache.clear().ok)
	var nested := root.path_join("defaults-test")
	cache.configure(nested,1100)
	check(cache.publish(resource,span,identity,PackedByteArray([1,2,3,4])).ok,"subdirectories of the cache root are accepted")
	check(cache.clear().ok)
	DirAccess.remove_absolute(nested)
	for rejected: String in [base.path_join("SomeOtherApp/terrain_tiles_v1"),root + "/../../SomeOtherApp",root + "/",base,ProjectSettings.globalize_path("user://saves"),"user://saves"]:
		cache.configure(rejected,1100)
		check(not cache.publish(resource,span,identity,PackedByteArray([1,2,3,4])).ok,"root outside the app cache rejected: " + rejected)
		check(not cache.clear().ok)
	cache.configure("user://terrain_tiles_v1/legacy-fixture",1100)
	check(cache.publish(resource,span,identity,PackedByteArray([1,2,3,4])).ok,"legacy user:// fixture roots remain confined and usable")
	check(cache.clear().ok)
	DirAccess.remove_absolute("user://terrain_tiles_v1/legacy-fixture")
	DirAccess.remove_absolute("user://terrain_tiles_v1")
	DirAccess.remove_absolute(root)
	DirAccess.remove_absolute(root.get_base_dir())

func test_x11_physical_dpi_does_not_overscale_ordinary_laptops() -> void:
	# X11 reports EDID DPI, not the desktop's scaling choice.
	check_eq(Layout.backing_from_readings("Linux","X11",1.0,166),1.0,"a 14-inch 1080p laptop (~166 dpi) stays 100%")
	check_eq(Layout.backing_from_readings("Linux","X11",1.0,141,1080),1.0,"a 15.6-inch 1080p laptop stays 100%")
	check_eq(Layout.backing_from_readings("Linux","X11",1.0,192,1200),1.0,"a dense but short screen is not doubled")
	check_eq(Layout.backing_from_readings("Linux","X11",1.0,220,1800),2.0,"a dense, tall screen doubles")
	check_eq(Layout.backing_from_readings("Linux","X11",1.0,163,2160),1.5,"a 27-inch 4K monitor gets 150%")
	check_eq(Layout.backing_from_readings("Linux","X11",1.0,96,2160,2.0),2.0,"GDK_SCALE/QT_SCALE_FACTOR wins")
	check_eq(Layout.backing_from_readings("Linux","X11",1.0,96,1080,2.0),1.5,"the scale always leaves at least 720 points of height")
	check_eq(Layout.backing_from_readings("Linux","X11",1.0,0,0,NAN),1.0,"missing readings keep 100%")
	check_eq(Layout.backing_from_readings("Windows","Windows",1.0,168,1080),1.75,"Windows effective DPI is the player's choice and is kept")

func test_restored_window_frame_fits_and_centers_with_decorations() -> void:
	# Windows draws an 8px border and a 31px caption outside the client area.
	var usable := Rect2i(0,0,1366,728)
	var offset := Vector2i(8,31)
	var extra := Vector2i(16,39)
	var placed := Layout.centered_window_rect(Vector2i(1280,800),usable,offset,extra)
	var frame := Rect2i(placed.position - offset,placed.size + extra)
	check(usable.encloses(frame),"the whole frame, title bar included, starts inside the work area")
	check_eq(frame.position.y,0,"a work-area-tall window's caption sits at the top edge, not above it")
	check_eq(placed.size,Vector2i(1280,689))
	var small := Layout.centered_window_rect(Vector2i(800,600),Rect2i(100,0,1920,1080),offset,extra)
	var small_frame := Rect2i(small.position - offset,small.size + extra)
	check_eq(small_frame.position,Vector2i(100,0) + (Vector2i(1920,1080) - small_frame.size) / 2,"the decorated frame is centered")
	check_eq(Layout.centered_window_rect(Vector2i(1280,800),Rect2i(100,0,1920,1080)),Rect2i(420,140,1280,800),"no decorations: unchanged placement")

func test_minimized_and_fullscreen_window_state_is_remembered() -> void:
	var window := Window.new()
	window.size = Vector2i(1000,640)
	root.add_child(window)
	var layout := Layout.new()
	root.add_child(layout)
	layout.bind(window)
	var restore_size := layout.windowed_size
	layout.mode_override = Window.MODE_MAXIMIZED
	window.size = Vector2i(1800,1100)
	layout.refresh_metrics()
	check(layout.maximized)
	check_eq(layout.windowed_size,restore_size,"a maximized drawable is not the restore size")
	var metrics := layout.metrics.duplicate()
	layout.mode_override = Window.MODE_MINIMIZED
	window.size = Vector2i(160,28)
	layout.refresh_metrics()
	check(layout.maximized,"minimizing keeps the maximized state")
	check(not layout.fullscreen)
	check_eq(layout.windowed_size,restore_size,"a minimized drawable is not the restore size")
	check_eq(layout.metrics,metrics,"minimizing does not reflow the UI")
	check_eq(layout.restore_from_minimized(),Window.MODE_MAXIMIZED,"restoring a minimized window returns it maximized")
	check_eq(layout.restore_from_minimized(),-1,"a visible window is left alone")
	window.size = Vector2i(1800,1100)
	layout.mode_override = Window.MODE_FULLSCREEN
	layout.refresh_metrics()
	check(layout.fullscreen)
	check(layout.maximized,"fullscreen remembers it was entered from a maximized window")
	layout.set_fullscreen(false)
	check_eq(layout.restored_mode(),Window.MODE_MAXIMIZED,"leaving fullscreen returns to maximized, not a small window")
	check_eq(layout.windowed_size,restore_size)
	layout.mode_override = -1
	layout.free()
	window.free()
