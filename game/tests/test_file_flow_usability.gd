# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/exploration/async_test_case.gd"

const MainScene := preload("res://scenes/main.tscn")
var host: GameHost
var cleanup_paths: Array[String] = []

func before_each() -> void:
	host = MainScene.instantiate()
	host.preferences_path = "user://file-flow-usability.cfg"
	root.add_child(host)

func after_each() -> void:
	await _wait_for_loading()
	host.free()
	for path in cleanup_paths: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	cleanup_paths.clear()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://file-flow-usability.cfg"))
	await process_frame

func _wait_for_loading() -> void:
	for frame in 40:
		if not host.loading_screen.visible: return
		RenderingServer.force_draw(false)
		await process_frame
	check(false,"loading completes")

# Guards against: Regenerate on untouched generated land asking to save it.
func test_regenerate_untouched_land_needs_no_prompt() -> void:
	var first := host.start_new_city({"name":"Fresh land","seed":4321})
	check_eq(host.stage,GameHost.Stage.EDITING)
	for frame in 3: await process_frame
	check(host.files.has_unsaved_changes(),"a never-saved map still counts as unsaved for New/Load/Quit")
	host.files.request_city_action(&"regenerate")
	check(not host.notice_dialog.is_open(),"untouched generated land regenerates without a prompt")
	await _wait_for_loading()
	check(host.sim.city != first,"new land replaced the old")
	check(not host.notice_dialog.is_open())
	# Regenerated land is again a fresh baseline.
	var second := host.sim.city
	host.files.request_city_action(&"regenerate")
	check(not host.notice_dialog.is_open(),"regenerated land is also untouched")
	await _wait_for_loading()
	check(host.sim.city != second)
	# A real edit brings the question back, with its reason.
	check(host.terrain_editor.raise(20,20).ok)
	host.files.request_city_action(&"regenerate")
	check(host.notice_dialog.is_open(),"edited land asks before regenerating")
	check(host.notice_dialog.body_label.text.contains("before generating new land"))
	host.escape()
	check(not host.notice_dialog.is_open())
	# Other actions keep their prompt for never-saved land, now naming the action.
	host.files.request_city_action(&"new")
	check(host.notice_dialog.is_open())
	check(host.notice_dialog.body_label.text.contains("before starting a new city"))
	check_eq((host.notice_dialog.choice_buttons[1] as Button).text,"Don't Save")
	host.escape()

# Guards against: accented and non-Latin save names being silently stripped.
func test_save_names_keep_international_letters() -> void:
	check_eq(SaveDialog.clean_name("Ciudad Juárez"),"Ciudad Juárez")
	check_eq(SaveDialog.clean_name("東京 2050"),"東京 2050")
	check_eq(SaveDialog.clean_name("Zürich-Ost (Neu)"),"Zürich-Ost (Neu)")
	check_eq(SaveDialog.clean_name("a/b\\c:d*e?f\"g<h>i|j"),"abcdefghij")
	check_eq(SaveDialog.clean_name("  ..Hidden town.  "),"Hidden town")
	check_eq(SaveDialog.clean_name("Tab\tName\u0007"),"TabName")
	check_eq(SaveDialog.clean_name("Round Trip: 2?"),"Round Trip 2")
	check_eq(SaveDialog.clean_name("Mesa.sc2d"),"Mesa")
	check_eq(SaveDialog.clean_name("CON"),"CON city")
	check_eq(SaveDialog.clean_name("lpt1.old"),"lpt1 city.old")
	check_eq(SaveDialog.clean_name("Console"),"Console","only exact device names are changed")
	check_eq(SaveDialog.clean_name("/:*?"),"")
	host.begin_city(flat_city(),{},11,null)
	var path := host.files.save_city_as("Café Ñandú")
	cleanup_paths.append(path)
	check_eq(path.get_file(),"Café Ñandú.sc2d")
	check(FileAccess.file_exists(path))
	check(SaveFormat.load(path).ok)

# Guards against: founding or regenerating resetting choices made while shaping.
func test_found_keeps_disaster_and_auto_budget_choices() -> void:
	host.start_new_city({"name":"Control","seed":777})
	check(host.found_city())
	var control_rng := host.sim.rng.state()
	host.start_new_city({"name":"Chosen","seed":777})
	host.sim.stats.disasters_enabled = false
	host.sim.stats.auto_budget = true
	host.regenerate(777)
	check(not host.sim.stats.disasters_enabled,"regenerate keeps Disasters off")
	check(host.sim.stats.auto_budget,"regenerate keeps Auto budget on")
	check(host.found_city())
	check(not host.sim.stats.disasters_enabled,"founding keeps Disasters off")
	check(host.sim.stats.auto_budget,"founding keeps Auto budget on")
	check_eq(host.sim.rng.state(),control_rng,"carried choices consume no random numbers")

# Guards against: the default "Mayor" credit shown as if it were a name.
func test_default_mayor_credit_is_omitted() -> void:
	var dialog := LoadDialog.new()
	root.add_child(dialog)
	dialog.open([{"name":"Plain","path":"user://saves/plain.sc2d","mayor":"Mayor","saved_at":1760000000},
		{"name":"Named","path":"user://saves/named.sc2d","mayor":"Ana","saved_at":1760000000}] as Array[Dictionary])
	check(not dialog.details_label.text.contains("Mayor:"),dialog.details_label.text)
	check(not dialog.details_label.text.contains("UTC"),"saved time is local, not UTC")
	dialog.select(1)
	check(dialog.details_label.text.contains("Mayor: Ana"))
	dialog.free()
	var plain := CityShare._success("user://x.sc2d","Plain","Mayor")
	check(not String(plain.message).contains("a city by"),plain.message)
	var named := CityShare._success("user://x.sc2d","Named","Ana")
	check(String(named.message).contains("a city by Ana"))

# Guards against: internal paths and codes in load errors.
func test_load_errors_name_the_file_in_plain_words() -> void:
	host.begin_city(flat_city(),{},5,null)
	var junk := "user://file-flow-junk.sc2d"
	var newer := "user://file-flow-newer.sc2d"
	cleanup_paths.append_array([junk,newer])
	var file := FileAccess.open(junk,FileAccess.WRITE)
	# Valid JSON (a malformed document logs an engine parse error), but not a city.
	file.store_string(JSON.stringify({"format":"spreadsheet","version":1}))
	file.close()
	file = FileAccess.open(newer,FileAccess.WRITE)
	file.store_string(JSON.stringify({"format":"sc2d","version":SaveFormat.VERSION+1,"stage":"play","city":{}}))
	file.close()
	check(not host.load_city(junk))
	check(host.notice_dialog.body_label.text.contains("file-flow-junk.sc2d"))
	check(host.notice_dialog.body_label.text.contains("isn't a Sin City - Desert Dreams city"))
	check(not host.notice_dialog.body_label.text.contains("user://"))
	host.notice_dialog.dismiss()
	check(not host.load_city(newer))
	check(host.notice_dialog.body_label.text.contains("newer version"))
	host.notice_dialog.dismiss()

# Guards against: a started New City reusing the last name/seed, and word seeds
# shown as their hash.
func test_new_city_entries_clear_after_start_only() -> void:
	var dialog := host.new_city_dialog
	host.open_new_city_dialog()
	dialog.name_edit.text = "Kept on cancel"
	dialog.seed_edit.text = "mesa"
	dialog.generate_preview()
	check(dialog.preview_label.text.contains("Seed mesa"),dialog.preview_label.text)
	dialog.close()
	host.open_new_city_dialog()
	check_eq(dialog.name_edit.text,"Kept on cancel")
	check_eq(dialog.seed_edit.text,"mesa")
	dialog.start()
	await _wait_for_loading()
	check_eq(host.sim.city.name,"Kept on cancel")
	check_eq(dialog.name_edit.text,"")
	check_eq(dialog.seed_edit.text,"")
	host.files.request_city_action(&"new")
	if host.notice_dialog.is_open(): host.notice_dialog.dismiss(&"discard")
	check(dialog.is_open())
	check(not dialog.name_edit.text.is_empty(),"a fresh name is rolled")
	check(not dialog.seed_edit.text.is_empty(),"a fresh seed is rolled")
	dialog.close()

func _key(code: Key, command := false) -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = code
	key.physical_keycode = code
	key.pressed = true
	if command:
		if OS.get_name() == "macOS": key.meta_pressed = true
		else: key.ctrl_pressed = true
	return key

func _edit(field: LineEdit) -> void:
	field.grab_focus()
	if field.has_method("edit"): field.call("edit")

# Guards against: a focused text field swallowing the first Escape, leaving
# Save As, New City and prompt notices open.
func test_first_escape_closes_dialogs_with_a_focused_text_field() -> void:
	host.begin_city(flat_city(),{},11,null)
	host.files.open_save_dialog()
	_edit(host.save_dialog.name_edit)
	root.push_input(_key(KEY_ESCAPE))
	await process_frame
	check(not host.save_dialog.is_open(),"one Escape closes Save As")
	check_eq(host.modal_depth,0)
	host.open_new_city_dialog()
	_edit(host.new_city_dialog.name_edit)
	root.push_input(_key(KEY_ESCAPE))
	await process_frame
	check(not host.new_city_dialog.is_open(),"one Escape closes New City")
	var answers: Array[StringName] = []
	host.notices.queue("Place Sign","Text?",[["OK",&"submit"],["Cancel",&"cancel"]],func(choice: StringName) -> void: answers.append(choice),true)
	_edit(host.notice_dialog.line_edit)
	root.push_input(_key(KEY_ESCAPE))
	await process_frame
	check(not host.notice_dialog.is_open(),"one Escape closes a prompt notice")
	check_eq(answers,[&"cancel"] as Array[StringName],"the prompt's cancel reaches its handler")
	check_eq(host.modal_depth,0)

# Guards against: Escape in the chooser's Data Sources closing the whole chooser
# and cancelling its download.
func test_escape_in_data_sources_closes_only_the_credits() -> void:
	host.open_new_city_dialog()
	var chooser := host.new_city_dialog.terrain_dialog
	chooser.visible = true
	chooser.sources_dialog.open()
	var revision: int = chooser._revision
	host.escape()
	check(not chooser.sources_dialog.visible,"the credits close")
	check(chooser.visible,"the chooser stays open")
	check_eq(chooser._revision,revision,"no work is cancelled")
	host.escape()
	check(not chooser.visible,"the next Escape closes the chooser")
	host.new_city_dialog.close()

# Guards against: a notice that arrives by itself being accepted by Space or
# Enter meant for the city, including the irreversible military base offer.
func test_unrequested_notices_do_not_focus_a_choice() -> void:
	host.begin_city(flat_city(),{},11,null)
	host.notices.raise(&"reward_offered",{"key":String(RewardParams.MILITARY_KEY),"site":[10,10,8,8]})
	check(host.notice_dialog.is_open())
	check_eq((host.notice_dialog.choice_buttons[0] as Button).text,"Decline","declining is the default choice")
	var focused := root.gui_get_focus_owner()
	check(not focused is BaseButton,"no choice button holds keyboard focus")
	var space := _key(KEY_SPACE)
	root.push_input(space)
	await process_frame
	check(host.notice_dialog.is_open(),"Space does not answer the offer")
	check(not host.sim.stats.rewards_built.get(RewardParams.MILITARY_KEY,false),"no base was built")
	# Enter right as the offer appears was meant for something else.
	root.push_input(_key(KEY_ENTER))
	await process_frame
	check(host.notice_dialog.is_open(),"an Enter as the offer opens does not answer it")
	# A held Enter (key repeat) never answers, however long the offer is up.
	await create_timer(0.4).timeout
	var held := _key(KEY_ENTER)
	held.echo = true
	root.push_input(held)
	await process_frame
	check(host.notice_dialog.is_open(),"a repeating Enter does not answer the offer")
	check(not host.sim.stats.rewards_built.get(RewardParams.MILITARY_KEY,false),"still no base")
	host.notice_dialog.dismiss()
	check(not host.sim.stats.rewards_built.get(RewardParams.MILITARY_KEY,false))
	# A notice the player asked for keeps its first choice focused.
	host.files.request_city_action(&"new")
	check(host.notice_dialog.is_open())
	check(root.gui_get_focus_owner() == host.notice_dialog.choice_buttons[0],"requested notices focus their default")
	host.escape()

# Guards against: a tap or Enter that lands just as an unrequested notice
# appears answering it; after a moment the choices work normally.
func test_unrequested_notice_choices_wait_a_moment() -> void:
	var notice := host.notice_dialog
	var answers: Array[StringName] = []
	var record := func(choice: StringName) -> void: answers.append(choice)
	notice.closed.connect(record)
	notice.show_notice("Offer","Body",[["Decline",&"decline"],["Accept",&"accept"]],false,"",&"",false)
	check(notice.in_grace_period(),"a fresh unrequested notice is guarded")
	(notice.choice_buttons[1] as Button).pressed.emit()
	check(notice.is_open(),"a press as the notice opens is ignored")
	await create_timer(0.4).timeout
	check(not notice.in_grace_period())
	root.push_input(_key(KEY_ENTER))
	await process_frame
	check(not notice.is_open(),"after a moment Enter takes the first, safe choice")
	check_eq(answers,[&"decline"] as Array[StringName])
	notice.show_notice("Offer","Body",[["Decline",&"decline"],["Accept",&"accept"]],false,"",&"",false)
	await create_timer(0.4).timeout
	(notice.choice_buttons[1] as Button).pressed.emit()
	check(not notice.is_open(),"after a moment a deliberate press answers")
	check_eq(answers,[&"decline",&"accept"] as Array[StringName])
	# A notice the player asked for answers at once.
	notice.show_notice("Asked","Body",[["Yes",&"yes"],["No",&"no"]])
	check(not notice.in_grace_period())
	(notice.choice_buttons[0] as Button).pressed.emit()
	check(not notice.is_open(),"requested notices are not delayed")
	notice.closed.disconnect(record)

# Guards against: leaving untouched generated land asking to save it.
func test_untouched_generated_land_leaves_without_a_prompt() -> void:
	host.start_new_city({"name":"Plain land","seed":99})
	host.files.request_city_action(&"load")
	check(not host.notice_dialog.is_open(),"no save prompt for land the player never touched")
	check_eq(host.notices.pending(),0)
	await _wait_for_loading()
	check(host.load_dialog.is_open(),"Load opens straight away")
	host.load_dialog.close()

# Guards against: a loaded save running at its saved speed while Help and the
# import/included flows promise paused cities.
func test_loaded_city_opens_paused_and_p_resumes_its_speed() -> void:
	host.begin_city(flat_city(),{},11,null)
	host.sim.set_speed(GameClock.Speed.FAST)
	var path := host.files.save_city_as("file-flow-paused")
	cleanup_paths.append(path)
	host.sim.set_speed(GameClock.Speed.SLOW)
	check(host.load_city(path))
	check_eq(host.sim.speed,GameClock.Speed.PAUSED,"a loaded city opens paused")
	check_eq(host.status_bar.message_label.text,"Loaded %s. %s" % [host.sim.city.name,CitySession.PAUSED_HINT])
	host._unhandled_key_input(_key(KEY_P))
	check_eq(host.sim.speed,GameClock.Speed.FAST,"P resumes the saved speed")

# Guards against: Cmd+Q being silently deferred behind a dialog.
func test_quit_closes_simple_dialogs_and_explains_blocking_ones() -> void:
	host.begin_city(flat_city(),{},11,null)
	host.files.open_save_dialog()
	host.files.quit_game()
	check(not host.save_dialog.is_open(),"Save As closes as Cancel would")
	check(host.notice_dialog.is_open(),"the close continues to the save question")
	check_eq(host.notice_dialog.title_label.text,"Save Your City?")
	host.notice_dialog.dismiss(&"cancel")
	check_eq(host.modal_depth,0)
	# A city-level window blocks with an explanation instead of silence.
	host.notices.show("Budget","A city notice.")
	host.files.quit_game()
	check(host.notice_dialog.is_open(),"a city notice is not closed for the player")
	check(host.files._quit_waiting)
	check_eq(host.status_bar.message_label.text,CityFileFlow.QUIT_WAITING_MESSAGE,"the player learns why the close waits")
	# Starting another city instead of cancelling drops the waiting close.
	host.begin_city(flat_city(),{},12,null)
	check(not host.files._quit_waiting,"a new city clears the deferred close")
	for frame in 3: await process_frame
	check(not host.notice_dialog.is_open(),"no surprise save question afterwards")

# Guards against: Browse → Cancel dropping the player out of Load City.
func test_cancelled_browse_returns_to_the_load_list() -> void:
	host.files.open_load_dialog()
	host.files.open_native_load_dialog()
	check(not host.load_dialog.is_open())
	host.files.native_load_dialog.hide()
	host.files.native_load_dialog.canceled.emit()
	await _wait_for_loading()
	check(host.load_dialog.is_open(),"Cancel returns to the Load list")
	check_eq(host.modal_depth,1)
	host.load_dialog.close()
	check_eq(host.modal_depth,0)

# Guards against: Save As with the open file's own name asking to replace it.
func test_save_as_with_the_open_name_saves_without_asking() -> void:
	host.begin_city(flat_city(),{},11,null)
	var path := host.files.save_city_as("file-flow-same")
	cleanup_paths.append(path)
	host.files.request_save_as("file-flow-same")
	check(not host.notice_dialog.is_open(),"no replace question for the open file")
	check_eq(host.notices.pending(),0)
	var other := host.files.save_city_as("file-flow-other")
	cleanup_paths.append(other)
	host.files.request_save_as("file-flow-same")
	check(host.notice_dialog.is_open(),"replacing a different save still asks")
	check_eq(host.notice_dialog.title_label.text,"Replace Saved City?")
	host.notice_dialog.dismiss(&"cancel")

# Guards against: changing only the name, difficulty or year regenerating the map.
func test_metadata_changes_keep_the_previewed_land() -> void:
	var dialog := host.new_city_dialog
	host.open_new_city_dialog()
	dialog.seed_edit.text = "4242"
	var city := dialog.generate_preview()
	var emitted: Array = []
	dialog.started.connect(func(_p: Dictionary, c: City) -> void: emitted.append(c))
	dialog.name_edit.text = "Renamed Flats"
	dialog.name_edit.text_changed.emit(dialog.name_edit.text)
	check(not dialog.preview_label.text.contains("settings changed"),"a new name needs no new preview")
	check(dialog.preview_label.text.contains("Renamed Flats"))
	dialog.difficulty_button.select(2)
	dialog.difficulty_button.item_selected.emit(2)
	dialog.start()
	check_eq(emitted.size(),1)
	if not emitted.is_empty():
		check(emitted[0] == city,"Shape City keeps the previewed land")
		check_eq((emitted[0] as City).name,"Renamed Flats")
		check_eq((emitted[0] as City).difficulty,2)
		check_eq((emitted[0] as City).funds,int(City.STARTING_FUNDS[2]))
	await _wait_for_loading()

# Guards against: the New City preview running under the body scrollbar.
func test_new_city_preview_clears_the_scrollbar() -> void:
	host.open_new_city_dialog()
	for frame in 6: await process_frame
	var dialog := host.new_city_dialog
	var chrome: Dictionary = dialog.panel.get_meta("window_chrome")
	var scroll := chrome.body_scroll as ScrollContainer
	var visible_right := scroll.get_global_rect().end.x - (scroll.get_v_scroll_bar().size.x if scroll.get_v_scroll_bar().visible else 0.0)
	check(dialog.preview_rect.get_global_rect().end.x <= visible_right + 0.5,"the preview stays clear of the scrollbar")
	check(not scroll.get_h_scroll_bar().visible,"the form needs no sideways scrolling")
	dialog.close()

# Guards against: macOS fullscreen depending on F11, which the OS keeps.
func test_mac_fullscreen_chord() -> void:
	var chord := InputEventKey.new()
	chord.keycode = KEY_F
	chord.pressed = true
	chord.ctrl_pressed = true
	chord.meta_pressed = true
	check_eq(host._is_mac_fullscreen_chord(chord), OS.get_name() == "macOS", "Ctrl+Cmd+F is the fullscreen chord on macOS only")
	chord.ctrl_pressed = false
	check(not host._is_mac_fullscreen_chord(chord), "Cmd+F alone is left alone")
