# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_case.gd"
## A current inventory must inspect each publication without repeatedly cloning
## the entire library on the foreground thread. Real journal/payload IO remains.
const Fake = preload("res://tests/helpers/fake_apple_cloud.gd")

class CountingStore extends CloudSaveStore:
	var materialized_rows := 0
	func slots() -> Array[Dictionary]:
		var rows := super.slots()
		materialized_rows += rows.size()
		return rows

var _roots: Array[String] = []

func _library(count: int) -> Dictionary:
	var root := "user://cloud-inventory-bounds/%d-%d" % [Time.get_ticks_usec(), _roots.size()]
	_roots.append(root)
	var path := root.path_join("city.sc2d")
	check_eq(SaveFormat.save(path, flat_city()), OK)
	var store := CountingStore.new(root.path_join("store"))
	check_eq(store.open_library("account-a"), OK)
	var remotes: Array[Dictionary] = []
	for i in count:
		var remote := {"slot_id": "slot-%d" % i, "commit_id": "commit-%d" % i,
			"change_tag": "tag-%d" % i, "system_fields": PackedByteArray([1]),
			"continuation_sha256": FileAccess.get_sha256(path), "manual_sha256": "",
			"tombstone": false, "metadata": {"name": "Library city %d" % i}}
		check_eq(store.publish_remote(remote, {"continuation": path}), OK)
		remotes.append(remote)
	return {"store": store, "remotes": remotes}

func _ready(store: CloudSaveStore, fake: RefCounted) -> CloudSaveCoordinator:
	var service := CloudSaveCoordinator.new(store, fake)
	service.jitter = func() -> float: return 0.0
	service.set_enabled(true)
	service.advance(0)
	fake.finish(fake.last("account"), {"owner": "account-a"})
	service.advance(0)
	fake.finish(fake.last("prepare_zone"))
	service.advance(0)
	return service

func test_unchanged_inventory_never_materializes_the_whole_library_per_record() -> void:
	var fixture := _library(48)
	var store: CountingStore = fixture.store
	var before := store.slots()
	store.materialized_rows = 0
	var fake := Fake.new()
	var service := _ready(store, fake)
	fake.finish(fake.last("changes"), {"records": fixture.remotes, "deleted_ids": [], "token": PackedByteArray([9]), "more": false})
	var start := Time.get_ticks_usec()
	service.advance(1)
	print("INVENTORY 48 current records us=", Time.get_ticks_usec() - start, " materialized_rows=", store.materialized_rows)
	check_eq(store.materialized_rows, 0, "current inventory uses per-slot facts rather than repeated full-library snapshots")
	check_eq(fake.count("download"), 0, "unchanged publications need no download")
	check_eq(store.change_token(), PackedByteArray([9]), "the whole inventory was processed")
	check_eq(store.slots(), before, "publication metadata and payload identities stay intact")
	service.shutdown()

func test_changed_and_missing_publications_still_download() -> void:
	for existing in [true, false]:
		var fixture := _library(1 if existing else 0)
		var store: CountingStore = fixture.store
		var remote: Dictionary
		if existing:
			remote = fixture.remotes[0].duplicate(true)
			remote.commit_id = "new-commit"
			remote.change_tag = "new-tag"
		else:
			remote = {"slot_id": "new-slot", "commit_id": "new-commit", "change_tag": "new-tag",
				"system_fields": PackedByteArray([1]), "continuation_sha256": "a".repeat(64),
				"manual_sha256": "", "tombstone": false, "metadata": {"name": "New city"}}
		var fake := Fake.new()
		var service := _ready(store, fake)
		fake.finish(fake.last("changes"), {"records": [remote], "deleted_ids": [], "token": PackedByteArray([10]), "more": false})
		service.advance(1)
		check_eq(fake.count("download"), 1, "changed and new publications are downloaded")
		check_eq(fake.last("download").args.remote, remote)
		check_eq(store.change_token(), PackedByteArray(), "download must complete before the inventory token commits")
		service.shutdown()

func after_all() -> void:
	for path in _roots: _remove_tree(path)

func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null: return
	for name in dir.get_directories(): _remove_tree(path.path_join(name))
	for name in dir.get_files(): DirAccess.remove_absolute(path.path_join(name))
	DirAccess.remove_absolute(path)
