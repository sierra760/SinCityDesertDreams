# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/exploration/async_test_case.gd"
const Fixture := preload("res://tests/helpers/host_fixture.gd")
var host: GameHost
func before_each() -> void:
	host = Fixture.make_host(self,"app-review-readiness")
func after_each() -> void:
	host.free()
	await process_frame
func test_ios_has_no_unavailable_mods_routes() -> void:
	root.size=Vector2i(390,844)
	host.display_layout.refresh_with_mobile_metrics(root.size,1.0,Rect2i(0,59,390,751),0,"iOS")
	await Fixture.settle(self,8)
	host.explore_hud.show_session(true)
	host.explore_hud.set_suspended(true)
	var options := host.window_manager.open("options")
	await Fixture.settle(self,6)
	for owner: Node in [host.explore_hud,options]:
		for button: Button in owner.find_children("*","Button",true,false):
			if button.text=="Explore Mods": check(not button.visible,"unsupported Mods is hidden on iOS")
	options.close()
	host.open_explore_mods()
	check(not host.window_manager.is_open("explore_mods"),"host cannot open the unsupported source-import panel")
func test_touch_guide_names_current_betting_and_virtual_funds() -> void:
	var rows := ""
	for row: Array in HelpWindow.ROWS:
		if row.size()>1 and (row.size()<3 or row[2]=="touch"): rows+=str(row[1])+"\n"
	check(rows.contains("denomination") and rows.contains("+"),"phone betting instructions name the chooser and plus")
	check(rows.contains("Menu → Inspect"),"portrait Inspect is discoverable")
	check(rows.contains("virtual") and rows.contains("real money"),"casino funds are clearly simulated")
	check(not rows.contains("MARKER is real debt"),"city debt is not a real financial product")

func test_privacy_is_reachable_before_city_and_during_editing() -> void:
	check(host.title_screen.has_signal("privacy_requested"),"title exposes privacy independently of city state")
	check(host.menu_bar.has_action(&"privacy"),"gameplay menu exposes privacy")
	check(WindowManager.SCRIPTS.has("privacy"),"policy uses the shared window manager")
	check(WindowManager.EDITING_WINDOWS.has("privacy"),"policy stays available before founding")
	if not WindowManager.SCRIPTS.has("privacy") or not host.title_screen.has_signal("privacy_requested"): return
	host.in_game = false
	host._show_title()
	host.title_screen.emit_signal("privacy_requested")
	check(host.window_manager.is_open("privacy"),"title signal actually opens policy")
	check(host.window_manager.windows.privacy.get_parent() == host.modal_layer,"title policy draws above the title layer")
	host.window_manager.windows.privacy.close()
	host.session.begin_editing(flat_city(),{})
	host._on_menu_action(&"privacy",null)
	check(host.window_manager.is_open("privacy"),"gameplay action actually opens policy in editing stage")

func test_policy_is_bundled_in_every_export() -> void:
	check(FileAccess.file_exists("res://legal/PRIVACY.txt"),"policy text works offline")
	var cfg := ConfigFile.new()
	check_eq(cfg.load("res://export_presets.cfg"),OK)
	for section: String in cfg.get_sections():
		if cfg.get_value(section,"platform","").is_empty(): continue
		check(str(cfg.get_value(section,"include_filter","")).split(",").count("legal/PRIVACY.txt")==1,"every export carries policy text once")
	for section: String in cfg.get_sections():
		if cfg.get_value(section,"platform","")=="iOS": check_eq(cfg.get_value(section+".options","entitlements/game_center",true),false,"unused Game Center is removed")

func test_public_search_does_not_escape_ios_guard() -> void:
	var search := TerrainPlaceSearch.new()
	root.add_child(search)
	check("platform_name" in search,"search exposes a testable runtime platform boundary")
	if not "platform_name" in search:
		search.free()
		return
	search.set("platform_name","iOS")
	check(not search.enabled(),"built-in public Nominatim stays off on iOS")
	var provider := TerrainMapConfig.DEFAULT.search.duplicate(true)
	provider.url="https://nominatim.openstreetmap.org:443/search?q={query}"
	search.configure_provider(provider)
	check(not search.enabled(),"cached and published public endpoints cannot bypass restriction")
	provider.url="https://approved.example.org/search?q={query}"
	search.configure_provider(provider)
	check(search.enabled(),"a configured alternative provider remains switchable")
	search.set("platform_name","macOS")
	search.configure_provider(TerrainMapConfig.DEFAULT.search)
	check(search.enabled(),"existing desktop search behavior remains available")
	search.free()

func test_policy_fits_rotations_and_failed_browser_open() -> void:
	var previous: Variant = ProjectSettings.get_setting(PrivacyWindow.URL_SETTING,null)
	ProjectSettings.set_setting(PrivacyWindow.URL_SETTING,"https://privacy.example.org/policy")
	var policy := host.window_manager.open("privacy") as PrivacyWindow
	var visited: Array[String] = []
	policy.url_opener=func(url: String) -> int:
		visited.append(url)
		return ERR_CANT_OPEN
	policy.open_online_policy()
	check_eq(visited,["https://privacy.example.org/policy"] as Array[String])
	check(policy.visible and policy.status.text.contains("could not open"),"failed browser launch preserves offline reading")
	for dimensions: Vector2i in [Vector2i(390,844),Vector2i(844,390),Vector2i(320,568),Vector2i(1024,768)]:
		root.size=dimensions
		host.display_layout.refresh_with_mobile_metrics(dimensions,1.0,Rect2i(Vector2i.ZERO,dimensions),0,"iOS")
		await Fixture.settle(self,8)
		var bounds := host.display_layout.logical_rect()
		check(bounds.grow(.1).encloses(policy.panel.get_global_rect()),"policy fits usable display")
		check(bounds.grow(.1).encloses(policy.done_button.get_global_rect()),"Done stays reachable")
		check(policy.done_button.size.y>=44,"Done retains touch target")
	policy.policy_scroll.scroll_vertical=200
	policy.close()
	policy.open()
	check_eq(policy.policy_scroll.scroll_vertical,0,"reopening starts at the policy heading")
	ProjectSettings.set_setting(PrivacyWindow.URL_SETTING,"file:///private/data")
	policy.refresh()
	check(not policy.online_button.visible,"unsafe or unconfigured online addresses stay hidden")
	ProjectSettings.set_setting(PrivacyWindow.URL_SETTING,previous)

func test_mods_supported_desktop_predicate() -> void:
	check(ExploreLuaBridge.supported_environment("macOS",false),"macOS native Lua remains available")
	check(ExploreLuaBridge.supported_environment("Windows",true),"Windows x64 Lua remains available")
	check(not ExploreLuaBridge.supported_environment("Windows",false),"Windows arm has no unavailable import UI")
	check(not ExploreLuaBridge.supported_environment("iOS",false),"iOS has no native Lua")
	host.display_layout.refresh_with_mobile_metrics(Vector2i(1280,800),1.0,Rect2i(0,0,1280,800),0,"macOS")
	var panel := host.window_manager.open("explore_mods")
	check(panel is ExploreModsPanel,"supported desktop retains Mods window")
	panel.close()

class RedirectProbe extends TerrainBasemap.NativeBackend:
	var redirect_limit_seen := -1
	func start(_url: String, _headers: PackedStringArray) -> int:
		if "max_redirects" in self: redirect_limit_seen = int(get("max_redirects"))
		return ERR_CANT_OPEN

func test_ios_search_cannot_redirect_to_public_provider() -> void:
	var backend := RedirectProbe.new()
	var search := TerrainPlaceSearch.new()
	root.add_child(search)
	search.platform_name="iOS"
	var provider := TerrainMapConfig.DEFAULT.search.duplicate(true)
	provider.url="https://approved.example.org/search?q={query}"
	search.configure_provider(provider)
	search.request_factory=func() -> Node: return backend
	search.search("Henderson")
	check_eq(backend.redirect_limit_seen,0,"iOS search backend never follows an unvalidated redirect")
	search.free()
