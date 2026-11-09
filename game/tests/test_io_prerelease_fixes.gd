# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## File and cloud-library robustness: a moved store root, unreadable remote
## records, one damaged payload, wrong-typed or oversized shared files, and
## abandoned staging folders.
extends "res://tests/test_case.gd"
const Fake = preload("res://tests/helpers/fake_apple_cloud.gd")

var _roots: Array[String] = []
var _serial := 0

func _root() -> String:
	var path := "user://io-fix-tests/%d-%d" % [Time.get_ticks_usec(), _roots.size()]
	_roots.append(path)
	DirAccess.make_dir_recursive_absolute(path)
	return path

func _city(root: String, title: String = "City") -> String:
	_serial += 1
	var path := root.path_join("%s-%d.sc2d" % [title, _serial])
	var city := flat_city()
	city.name = title
	check_eq(SaveFormat.save(path, city), OK)
	return path

func after_all() -> void:
	for root in _roots: _remove_tree(root)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://io-fix-tests"))

func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null: return
	dir.include_hidden = true
	for child in dir.get_directories(): _remove_tree(path.path_join(child))
	for child in dir.get_files(): DirAccess.remove_absolute(path.path_join(child))
	DirAccess.remove_absolute(path)

func _copy_tree(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to)
	var dir := DirAccess.open(from)
	for child in dir.get_directories(): _copy_tree(from.path_join(child), to.path_join(child))
	for child in dir.get_files(): check_eq(DirAccess.copy_absolute(from.path_join(child), to.path_join(child)), OK)

func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


# ── A journal still opens after its store root moves ─────────────────────

func test_library_opens_after_the_store_root_moves() -> void:
	var root := _root()
	var before := ProjectSettings.globalize_path(root.path_join("old-container/store"))
	var store := CloudSaveStore.new(before)
	check_eq(store.open_library("account-a"), OK)
	var id := store.create_slot()
	check(not store.stage(id, _city(root, "Moved")).is_empty())
	var digest: String = store.slots()[0].continuation_sha256
	var after := ProjectSettings.globalize_path(root.path_join("new-container/store"))
	_copy_tree(before, after)
	_remove_tree(before)
	var moved := CloudSaveStore.new(after)
	check_eq(moved.open_library("account-a"), OK, "the journal written under the old root opens")
	check_eq(moved.slots().size(), 1)
	if moved.slots().size() != 1: return
	var row := moved.slots()[0]
	check_eq(row.slot_id, id)
	check(String(row.path).begins_with(after + "/"), "the payload is read under the new root")
	check(moved.payload_intact(row.continuation))
	check_eq(row.continuation_sha256, digest)
	var loaded := SaveFormat.load(row.path)
	check(loaded.ok)
	check_eq(moved.pending().size(), 1, "queued work moved with it")
	# The moved library keeps working and stays readable.
	check(not moved.stage(id, _city(root, "Moved again")).is_empty())
	var again := CloudSaveStore.new(after)
	check_eq(again.open_library("account-a"), OK)
	check_eq(again.slots().size(), 1)

func test_moved_root_still_verifies_payload_bytes() -> void:
	var root := _root()
	var before := ProjectSettings.globalize_path(root.path_join("a/store"))
	var store := CloudSaveStore.new(before)
	check_eq(store.open_library("account-a"), OK)
	var id := store.create_slot()
	var work := store.stage(id, _city(root, "Alpha"))
	var after := ProjectSettings.globalize_path(root.path_join("b/store"))
	_copy_tree(before, after)
	var payload: String = String(work.continuation.path).replace(before, after)
	var changed := FileAccess.get_file_as_string(payload).replace("Alpha", "Bravo")
	_write(payload, changed)
	var moved := CloudSaveStore.new(after)
	check_eq(moved.open_library("account-a"), OK)
	check_eq(moved.slots().size(), 0, "altered bytes are never offered from the new root")

func test_recovery_file_is_recognised_under_a_moved_user_folder() -> void:
	var current := "/new/Containers/B/Documents/recovery/suspended.sc2d"
	check(CloudSaveStore._same_recovery_file(current, current))
	check(CloudSaveStore._same_recovery_file("/old/Containers/A/Documents/recovery/suspended.sc2d", current))
	check(not CloudSaveStore._same_recovery_file("/old/Containers/A/Documents/saves/suspended.sc2d", current))
	check(not CloudSaveStore._same_recovery_file("/old/Containers/A/Documents/recovery/other.sc2d", current))


# ── One damaged payload sets aside only its slot ─────────────────────────

func test_missing_payload_sets_aside_only_its_slot() -> void:
	var root := _root()
	var store := CloudSaveStore.new(root.path_join("store"))
	check_eq(store.open_library("account-a"), OK)
	var lost := store.create_slot()
	var lost_work := store.stage(lost, _city(root, "Lost"))
	var kept := store.create_slot()
	var kept_work := store.stage(kept, _city(root, "Kept"))
	check_eq(store.commit_change_token(PackedByteArray([7])), OK)
	check_eq(DirAccess.remove_absolute(lost_work.continuation.path), OK)
	var reopened := CloudSaveStore.new(root.path_join("store"))
	check_eq(reopened.open_library("account-a"), OK, "one missing file does not close the library")
	var ids: Array = []
	for row in reopened.slots(): ids.append(row.slot_id)
	check_eq(ids, [kept])
	check_eq(reopened.quarantined_slots(), [lost] as Array[String])
	check(reopened.payload_intact(kept_work.continuation))
	check_eq(reopened.change_token(), PackedByteArray(), "the next inventory lists every record, so a server copy returns")
	check_eq(reopened.pending().size(), 1, "the damaged slot's work is not sent")
	# The repaired library is durable and still accepts a download of that slot.
	var third := CloudSaveStore.new(root.path_join("store"))
	check_eq(third.open_library("account-a"), OK)
	check_eq(third.slots().size(), 1)
	var source := _city(root, "Server copy")
	var remote := {"slot_id": lost, "commit_id": "remote-commit", "change_tag": "tag-1",
		"system_fields": PackedByteArray([1]), "continuation_sha256": FileAccess.get_sha256(source),
		"manual_sha256": "", "tombstone": false, "metadata": {"name": "Server copy"}}
	check_eq(third.publish_remote(remote, {"continuation": source}), OK)
	check_eq(third.slots().size(), 2)

func test_altered_payload_is_set_aside_and_never_deleted() -> void:
	var root := _root()
	var store := CloudSaveStore.new(root.path_join("store"))
	check_eq(store.open_library("account-a"), OK)
	var id := store.create_slot()
	var manual := _city(root, "Named")
	var work := store.stage(id, _city(root, "Alpha"), manual)
	var other := store.create_slot()
	check(not store.stage(other, _city(root, "Other")).is_empty())
	_write(work.continuation.path, FileAccess.get_file_as_string(work.continuation.path).replace("Alpha", "Bravo"))
	var reopened := CloudSaveStore.new(root.path_join("store"))
	check_eq(reopened.open_library("account-a"), OK)
	check_eq(reopened.slots().size(), 1)
	check_eq(reopened.slots()[0].slot_id, other)
	check(FileAccess.file_exists(work.continuation.path), "the altered file is left in place")
	check(FileAccess.file_exists(work.manual.path), "the slot's intact payload is kept")
	check(not reopened.stage(other, _city(root, "Other again")).is_empty())
	check(FileAccess.file_exists(work.manual.path), "later publications do not prune it")


# ── An unreadable remote record cannot block the page ────────────────────

func _remote(path: String, id: String, tag: String = "tag-1") -> Dictionary:
	return {"slot_id": id, "commit_id": "commit-" + id, "change_tag": tag,
		"system_fields": PackedByteArray([1]), "continuation_sha256": FileAccess.get_sha256(path),
		"manual_sha256": "", "tombstone": false, "metadata": {"name": "Remote"}}

func _ready_service(store: CloudSaveStore, fake: RefCounted) -> CloudSaveCoordinator:
	var service := CloudSaveCoordinator.new(store, fake)
	service.jitter = func() -> float: return 0.0
	service.set_enabled(true)
	service.advance(0)
	fake.finish(fake.last("account"), {"owner": "account-a"})
	service.advance(0)
	fake.finish(fake.last("prepare_zone"))
	service.advance(0)
	return service

func test_record_from_a_newer_version_is_skipped_without_download() -> void:
	var root := _root()
	var store := CloudSaveStore.new(root.path_join("store"))
	check_eq(store.open_library("account-a"), OK)
	var fake := Fake.new()
	var service := _ready_service(store, fake)
	var good := _city(root, "Good")
	var future := _remote(_city(root, "Future"), "future-slot")
	future.metadata["application_save_version"] = SaveFormat.VERSION + 1
	fake.finish(fake.last("changes"), {"records": [future, _remote(good, "good-slot")], "deleted_ids": [], "token": PackedByteArray([9]), "more": false})
	service.advance(1)
	check_eq(fake.count("download"), 1)
	check_eq(fake.last("download").args.remote.slot_id, "good-slot", "the newer record is not downloaded")
	fake.finish(fake.last("download"), {"downloaded": {"continuation": good}})
	service.advance(2)
	service.advance(3)
	check_eq(store.change_token(), PackedByteArray([9]), "the cursor commits past the skipped record")
	check_eq(store.slots().size(), 1)
	check_eq(service.status().state, "unreadable")
	check_eq(service.status().error, "")
	service.shutdown()

func test_invalid_download_is_set_aside_after_bounded_tries() -> void:
	var root := _root()
	var store := CloudSaveStore.new(root.path_join("store"))
	check_eq(store.open_library("account-a"), OK)
	var existing := _city(root, "Existing")
	var old := _remote(existing, "bad-slot", "tag-0")
	check_eq(store.publish_remote(old, {"continuation": existing}), OK)
	var kept_bytes := FileAccess.get_file_as_bytes(store.slots()[0].path)
	var fake := Fake.new()
	var service := _ready_service(store, fake)
	var good := _city(root, "Good")
	var bad := _remote(_city(root, "Bad"), "bad-slot")
	var corrupt := root.path_join("corrupt.sc2d")
	_write(corrupt, "not a city")
	fake.finish(fake.last("changes"), {"records": [bad, _remote(good, "good-slot")], "deleted_ids": [], "token": PackedByteArray([9]), "more": false})
	var now := 1
	service.advance(now)
	for attempt in 6:
		var request := fake.last("download")
		if request.args.remote.slot_id != "bad-slot": break
		fake.finish(request, {"downloaded": {"continuation": corrupt}})
		now += 1
		service.advance(now)
		now += 120000
		service.advance(now)
	check_eq(fake.count("download"), CloudSaveCoordinator.INVALID_DOWNLOAD_ATTEMPTS + 1, "the same bytes are not fetched forever")
	check_eq(fake.last("download").args.remote.slot_id, "good-slot", "the rest of the page continues")
	fake.finish(fake.last("download"), {"downloaded": {"continuation": good}})
	service.advance(now + 1)
	service.advance(now + 2)
	check_eq(store.change_token(), PackedByteArray([9]))
	check_eq(service.status().state, "unreadable")
	# Nothing was removed or replaced because of the unreadable record.
	var rows := {}
	for row in store.slots(): rows[row.slot_id] = row
	check_eq(rows.size(), 2)
	check_eq(rows["bad-slot"].commit_id, old.commit_id)
	check_eq(rows["bad-slot"].baseline_tag, "tag-0")
	check_eq(FileAccess.get_file_as_bytes(rows["bad-slot"].path), kept_bytes)
	# The same revision is not fetched again; a changed one is.
	var downloads := fake.count("download")
	service.refresh(&"visible")
	service.advance(now + 200000)
	fake.finish(fake.last("changes"), {"records": [bad], "deleted_ids": [], "token": PackedByteArray([10]), "more": false})
	service.advance(now + 200001)
	check_eq(fake.count("download"), downloads)
	check_eq(store.change_token(), PackedByteArray([10]))
	var fixed := _remote(good, "bad-slot", "tag-2")
	service.refresh(&"visible")
	service.advance(now + 400000)
	fake.finish(fake.last("changes"), {"records": [fixed], "deleted_ids": [], "token": PackedByteArray([11]), "more": false})
	service.advance(now + 400001)
	check_eq(fake.count("download"), downloads + 1, "a changed record is tried again")
	fake.finish(fake.last("download"), {"downloaded": {"continuation": good}})
	service.advance(now + 400002)
	service.advance(now + 400003)
	check_eq(service.status().state, "synced")
	service.shutdown()


# ── Wrong-typed fields fail as an ordinary unreadable file ───────────────

func _document(root: String) -> Dictionary:
	var city := flat_city()
	city.signs[Vector2i(3, 3)] = "Sign"
	city.facilities[Vector2i(5, 5)] = {"key": &"plant", "age": 1}
	var path := root.path_join("source.sc2d")
	check_eq(SaveFormat.save(path, city), OK)
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func _load_changed(root: String, base: Dictionary, section: String, field: String, value: Variant) -> Dictionary:
	var doc := base.duplicate(true)
	if section.is_empty(): doc[field] = value
	else: doc[section][field] = value
	_serial += 1
	var path := root.path_join("typed-%d.sc2d" % _serial)
	_write(path, JSON.stringify(doc))
	return {"path": path, "loaded": SaveFormat.load(path)}

func test_wrong_typed_fields_fail_with_a_message() -> void:
	var root := _root()
	var base := _document(root)
	check(SaveFormat.load(_load_changed(root, base, "", "format", "sc2d").path).ok, "the unchanged document loads")
	var cases := [["", "format", 5], ["", "format", ["sc2d"]], ["", "version", []], ["", "version", "two"], ["", "version", {}],
		["city", "name", 5], ["city", "mayor", []], ["city", "founded_year", []], ["city", "founded_year", "1900"],
		["city", "day", []], ["city", "funds", {}], ["city", "difficulty", "hard"], ["city", "rotation", []],
		["city", "sea_level", {}], ["city", "status", "ok"], ["city", "terrain_vertices", 7],
		["city", "terrain_model", 7], ["city", "layers", 4], ["city", "facilities", {"5,5": {"key": 5}}]]
	for case: Array in cases:
		var result: Dictionary = _load_changed(root, base, case[0], case[1], case[2]).loaded
		var label := "%s.%s = %s" % [case[0], case[1], case[2]]
		check(not result.ok, label + " is refused")
		check(result.city == null, label + " yields no city")
		check(result.error in [SaveFormat.MESSAGE_NOT_A_CITY, SaveFormat.MESSAGE_DAMAGED], label + " has the ordinary message")
	for layer: String in ["terrain", "altitude", "building", "zone"]:
		var doc := base.duplicate(true)
		doc.city.layers[layer] = 12
		var path := root.path_join("layer-%s.sc2d" % layer)
		_write(path, JSON.stringify(doc))
		var result := SaveFormat.load(path)
		check(not result.ok and result.error == SaveFormat.MESSAGE_DAMAGED, "layer %s as a number is damage" % layer)
	# A sign that is not text is dropped; the city still loads.
	var signs: Dictionary = _load_changed(root, base, "city", "signs", {"3,3": 5, "4,4": "Kept"}).loaded
	check(signs.ok)
	if signs.ok:
		check(not signs.city.signs.has(Vector2i(3, 3)))
		check_eq(signs.city.signs.get(Vector2i(4, 4)), "Kept")

func test_wrong_typed_header_is_not_listed() -> void:
	var root := _root()
	var base := _document(root)
	check(not SaveFormat.read_header(_load_changed(root, base, "", "format", "sc2d").path).is_empty())
	for case: Array in [["", "format", 5], ["header", "name", 5], ["header", "saved_at", []], ["header", "population", "many"],
			["header", "year", {}], ["header", "day", []], ["header", "funds", "rich"], ["header", "stage", 3]]:
		var path: String = _load_changed(root, base, case[0], case[1], case[2]).path
		check_eq(SaveFormat.read_header(path), {}, "%s.%s = %s is not a save header" % [case[0], case[1], case[2]])
	# A header with a mayor of the wrong type keeps the neutral credit.
	var mayor: String = _load_changed(root, base, "header", "mayor", 9).path
	check_eq(SaveFormat.read_header(mayor).get("mayor", ""), "Mayor")


# ── Size limits ──────────────────────────────────────────────────────────

func test_oversized_documents_are_refused_before_reading() -> void:
	var root := _root()
	var path := root.path_join("huge.sc2d")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(_document(root)))
	file.seek(SaveFormat.MAX_DOCUMENT_BYTES)
	file.store_8(32)
	file.close()
	var result := SaveFormat.load(path)
	check(not result.ok)
	check_eq(result.error, SaveFormat.MESSAGE_NOT_A_CITY)
	check_eq(result.get("detail", ""), "File is larger than any city save.")
	check_eq(SaveFormat.read_header(path), {})
	check(FileAccess.get_file_as_bytes("res://assets/cities/Juniper Basin.sc2d").size() * 100 < SaveFormat.MAX_DOCUMENT_BYTES)

func _chunk(tag: String, data: PackedByteArray) -> PackedByteArray:
	var out := tag.to_ascii_buffer()
	for shift in [24, 16, 8, 0]: out.append((data.size() >> shift) & 0xFF)
	out.append_array(data)
	return out

func test_classic_file_limits() -> void:
	var root := _root()
	var real := FileAccess.get_file_as_bytes("res://assets/cities/Salton Shores.sc2")
	check(Sc2Import.load_bytes(real).ok)
	# Run-length pairs that would unpack far past the layer they claim to fill.
	var pairs := PackedByteArray()
	pairs.resize(200000)
	for index in range(0, pairs.size(), 2): pairs[index] = 255
	var bomb := "FORM".to_ascii_buffer()
	bomb.append_array(PackedByteArray([0, 0, 0, 0]))
	bomb.append_array("SCDH".to_ascii_buffer())
	# Any tile-sized layer will do; take its tag from the importer's own table.
	var layer_tag := ""
	for tag: String in Sc2Import.CHUNK_SIZES:
		if int(Sc2Import.CHUNK_SIZES[tag]) == Sc2Import.TILES: layer_tag = tag;break
	check(not layer_tag.is_empty())
	bomb.append_array(_chunk(layer_tag, pairs))
	var parsed := Sc2Import.parse_container(bomb)
	check(not parsed.ok, "a chunk that unpacks past its layer is refused")
	check(not parsed.chunks.has(layer_tag))
	check(not Sc2Import.load_bytes(bomb).ok)
	check(Sc2Import.rle_decode(pairs, Sc2Import.TILES).size() <= Sc2Import.TILES + 128, "unpacking stops at the limit")
	check_eq(Sc2Import.rle_decode(pairs).size(), 100000 * 128, "unlimited decoding is unchanged")
	# A real city padded past the file limit is refused before it is read.
	var padding := PackedByteArray()
	padding.resize(Sc2Import.MAX_FILE_BYTES)
	var padded := real.duplicate()
	padded.append_array(_chunk("JUNK", padding))
	var path := root.path_join("padded.sc2")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(padded)
	file.close()
	var result := Sc2Import.load(path)
	check(not result.ok)
	check_eq(result.error, "This file isn't a classic city (.sc2) file.")
	var largest := 0
	for name in DirAccess.get_files_at("res://assets/cities"):
		if name.get_extension() == "sc2": largest = maxi(largest, FileAccess.get_file_as_bytes("res://assets/cities".path_join(name)).size())
	check(largest > 0 and largest * 20 < Sc2Import.MAX_FILE_BYTES)


# ── Abandoned staging folders ────────────────────────────────────────────

func _staging(parent: String, process: int, files: Array) -> String:
	_serial += 1
	var folder := parent.path_join("%s%d-%d-0" % [SaveFormat.STAGING_PREFIX, process, 900000 + _serial])
	DirAccess.make_dir_recursive_absolute(folder)
	for name: String in files: _write(folder.path_join(name), "kept-city.sc2d" if name == SaveFormat.STAGING_TARGET else "document bytes")
	return folder

func test_abandoned_staging_folders_are_removed_from_the_saves_folder() -> void:
	var saves := ProjectSettings.globalize_path(SaveFormat.default_dir())
	DirAccess.make_dir_recursive_absolute(saves)
	var other := OS.get_process_id() + 1
	var abandoned := _staging(saves, other, ["document", SaveFormat.STAGING_TARGET])
	var empty := _staging(saves, other, [])
	var own := _staging(saves, OS.get_process_id(), ["document", SaveFormat.STAGING_TARGET])
	var foreign := saves.path_join(SaveFormat.STAGING_PREFIX + "not-ours")
	DirAccess.make_dir_recursive_absolute(foreign)
	_write(foreign.path_join("document"), "someone else's")
	# The destination exists, so this previous city cannot be put back.
	_write(saves.path_join("kept-city.sc2d"), "current city")
	var holding := _staging(saves, other, ["document", SaveFormat.STAGING_TARGET, "previous.sc2d"])
	var elsewhere_root := ProjectSettings.globalize_path(_root())
	var elsewhere := _staging(elsewhere_root, other, ["document", SaveFormat.STAGING_TARGET])
	# A fresh folder may belong to another running copy of the game.
	check_eq(SaveFormat.recover_interrupted_saves(SaveFormat.default_dir()), 0)
	check(DirAccess.dir_exists_absolute(abandoned), "a recent folder is left alone")
	check_eq(SaveFormat.recover_interrupted_saves(SaveFormat.default_dir(), 0), 0)
	check_eq(SaveFormat.recover_interrupted_saves(elsewhere_root, 0), 0)
	check(not DirAccess.dir_exists_absolute(abandoned), "an abandoned document is removed")
	check(not DirAccess.dir_exists_absolute(empty), "an abandoned empty folder is removed")
	check(FileAccess.file_exists(own.path_join("document")), "this process's own staging is never touched")
	check(FileAccess.file_exists(foreign.path_join("document")), "a folder this code did not name is never touched")
	check(FileAccess.file_exists(holding.path_join("previous.sc2d")), "a previous city is always kept")
	check(not FileAccess.file_exists(holding.path_join("document")), "its unpublished document is dropped")
	check_eq(FileAccess.get_file_as_string(saves.path_join("kept-city.sc2d")), "current city")
	check(FileAccess.file_exists(elsewhere.path_join("document")), "other folders are not swept")
	for folder: String in [own, foreign, holding, elsewhere]: _remove_tree(folder)
	DirAccess.remove_absolute(saves.path_join("kept-city.sc2d"))
