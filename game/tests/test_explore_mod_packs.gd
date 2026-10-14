extends "res://tests/test_case.gd"
const Pack = preload("res://scripts/exploration/mods/explore_mod_pack.gd")
const Manifest = preload("res://scripts/exploration/mods/explore_mod_manifest.gd")
var serial := Time.get_ticks_usec()
func fixture(entry: String = "main.lua", size: int = 1) -> String:
	serial += 1
	var path := "user://pack-test-%d" % serial
	DirAccess.make_dir_recursive_absolute(path)
	var manifest := {"id":"test.pack", "name":"Test", "version":"1.0.0", "api_version":1, "state_version":1, "entry":entry, "priority":0}
	var f := FileAccess.open(path + "/manifest.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest))
	f.close()
	f = FileAccess.open(path + "/main.lua", FileAccess.WRITE)
	f.store_string(" ".repeat(size))
	f.close()
	return path
func test_pack_limits_and_namespace() -> void:
	check(not Pack.read(fixture("../main.lua")).ok)
	check(not Pack.read(fixture("main.lua", 131073)).ok)
	check(Pack.read(fixture("main.lua", 131072)).ok)
	for entry in ["/main.lua", "a/../main.lua", "a\\main.lua", "main.txt"]:
		check(not Pack.read(fixture(entry)).ok)
func test_duplicate_ids_and_case_aliases() -> void:
	var a := Pack.read(fixture())
	var b := Pack.read(fixture())
	var resolved := Manifest.resolve_candidates([a, b])
	check_eq(resolved.size(), 2)
	for item in resolved:
		check(not item.ok)
		check_eq(item.code, "duplicate_id")
	var m: Dictionary = a.manifest.duplicate(true)
	m.id = "Test.pack"
	check(not Manifest.validate(m).ok)
	m.id = "test.pack"
	m.api_version = 2
	check(not Manifest.validate(m).ok)

func archive(entries: Array, mode: int = 0, claimed_size: int = -1) -> String:
	serial += 1
	var path := "user://pack-archive-%d.scddmod" % serial
	var zip := ZIPPacker.new()
	zip.open(path)
	for entry in entries:
		zip.start_file(entry[0])
		zip.write_file(String(entry[1]).to_utf8_buffer())
		zip.close_file()
	zip.close()
	if mode != 0 or claimed_size >= 0:
		var bytes := FileAccess.get_file_as_bytes(path)
		for i in range(bytes.size() - 46):
			if bytes.decode_u32(i) == 0x02014b50:
				if mode != 0:
					bytes.encode_u32(i + 38, mode << 16)
				if claimed_size >= 0:
					bytes.encode_u32(i + 24, claimed_size)
				break
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_buffer(bytes)
		f.close()
	return path

func reject_archive(path: String, expected_code: String) -> void:
	serial += 1
	var destination := "user://rejected-pack-%d" % serial
	check(not DirAccess.dir_exists_absolute(destination))
	var result := Pack.import_zip(path, destination)
	check(not result.ok)
	check_eq(result.code, expected_code)
	check(not DirAccess.dir_exists_absolute(destination), "no installed output")
	check(not FileAccess.file_exists(destination), "no file output")
	var parent := DirAccess.open(destination.get_base_dir())
	for name in parent.get_directories():
		check(not name.begins_with(destination.get_file() + ".staging-"), "no staging output")

func test_hostile_archives_at_absent_destinations() -> void:
	var manifest := FileAccess.get_file_as_string(fixture() + "/manifest.json")
	var good := [["manifest.json", manifest], ["main.lua", "return {}"]]
	reject_archive(archive(good, 0xa1ff), "archive_path")
	reject_archive(archive(good, 0, 1048577), "file_size")
	for name in ["../main.lua", "/main.lua", "a/../main.lua", "bad.txt"]:
		reject_archive(archive([["manifest.json", manifest], [name, ""]]), "archive_path")
	reject_archive(archive(good + [["MAIN.lua", ""]]), "archive_path")
	reject_archive(archive(good + [["main.lua", ""]]), "archive_path")
	var many := good.duplicate()
	for i in 31:
		many.append(["file%d.lua" % i, ""])
	reject_archive(archive(many), "files")
	var unknown: Dictionary = JSON.parse_string(manifest)
	unknown.api_version = 2
	reject_archive(archive([["manifest.json", JSON.stringify(unknown)], ["main.lua", ""]]), "api_version")

func test_valid_archive_preserves_installed_folder() -> void:
	var installed := fixture()
	var before := FileAccess.get_file_as_bytes(installed + "/manifest.json")
	var good := [["manifest.json", before.get_string_from_utf8()], ["main.lua", "return {}"]]
	var result := Pack.import_zip(archive(good), installed)
	check_eq(result.code, "destination_exists")
	check_eq(FileAccess.get_file_as_bytes(installed + "/manifest.json"), before)
	serial += 1
	var destination := "user://new-pack-%d" % serial
	result = Pack.import_zip(archive(good), destination)
	check(result.ok, "valid install")
	check_eq(Pack.read(destination).content_hash, result.content_hash)
	check(result.is_read_only())
	check(result.sources.is_read_only())
	check(result.manifest.is_read_only())

func test_nested_archive_keeps_the_full_file_quota_with_implicit_directories() -> void:
	var manifest := FileAccess.get_file_as_string(fixture()+"/manifest.json")
	var entries := [["manifest.json",manifest],["main.lua","return {}"]]
	for index in 30: entries.append(["modules/file%d.lua" % index,"return %d" % index])
	serial+=1
	var destination := "user://nested-pack-%d" % serial
	var result := Pack.import_zip(archive(entries),destination)
	check(result.ok,"Godot's implicit ZIP directories do not consume the 32-file quota")
	if not result.ok: return
	check_eq(result.sources.size(),31,"only Lua files enter the immutable snapshot")
	check_eq(FileAccess.get_file_as_string(destination+"/modules/file29.lua"),"return 29")
	check_eq(Pack.read(destination).content_hash,result.content_hash,"nested ZIP and directory snapshots agree")

func test_directory_entries_cannot_bypass_archive_validation() -> void:
	var manifest := FileAccess.get_file_as_string(fixture()+"/manifest.json")
	var good := [["manifest.json",manifest],["main.lua","return {}"]]
	for name in ["../outside/","a/../outside/","/outside/"]:
		reject_archive(archive(good+[[name,""]]),"archive_path")
	reject_archive(archive(good+[["modules/","payload"]]),"archive_path")
	reject_archive(archive(good+[["main.lua/",""]]),"archive_path")
	reject_archive(archive(good+[["lib/a.lua","return {}"],["LIB/b.lua","return {}"]]),"archive_path")

func test_prefixed_directory_rejected_before_decoder() -> void:
	var manifest := FileAccess.get_file_as_string(fixture() + "/manifest.json")
	var path := archive([["manifest.json", manifest], ["main.lua", " ".repeat(262144)]])
	var bytes := FileAccess.get_file_as_bytes(path)
	var end := bytes.size() - 22
	var raw_offset := int(bytes.decode_u32(end + 16))
	var directory_size := int(bytes.decode_u32(end + 12))
	var fake := bytes.slice(raw_offset, end)
	var offset := 0
	for i in 2:
		var length := fake.decode_u16(offset + 28)
		var name := fake.slice(offset + 46, offset + 46 + length).get_string_from_utf8()
		if name == "main.lua":
			check_eq(fake.decode_u32(offset + 24), 262144)
			fake.encode_u32(offset + 24, 1)
		offset += 46 + length + fake.decode_u16(offset + 30) + fake.decode_u16(offset + 32)
	var prefix := PackedByteArray()
	prefix.resize(raw_offset)
	prefix.append_array(fake)
	prefix.append_array(bytes)
	check(prefix.size() < 4096, "bounded compressed parser differential fixture")
	var prefixed_end := prefix.size() - 22
	check_eq(prefix.decode_u32(prefixed_end + 16), raw_offset)
	check(prefixed_end - (raw_offset + directory_size) > 0, "decoder would apply prefix adjustment")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(prefix)
	f.close()
	reject_archive(path, "archive_directory")

func test_encoding_rejects_without_diagnostics() -> void:
	for bytes in [PackedByteArray([0]), PackedByteArray([0xc0, 0x80]), PackedByteArray([0xed, 0xa0, 0x80]), PackedByteArray([0xf4, 0x90, 0x80, 0x80]), PackedByteArray([0xe2, 0x82])]:
		var path := fixture()
		var f := FileAccess.open(path + "/main.lua", FileAccess.WRITE)
		f.store_buffer(bytes)
		f.close()
		check_eq(Pack.read(path).code, "source_encoding")

func test_folder_totals_and_snapshot() -> void:
	var path := fixture()
	var snapshot := Pack.read(path)
	var f := FileAccess.open(path + "/main.lua", FileAccess.WRITE)
	f.store_string("changed")
	f.close()
	check_eq(snapshot.sources["main.lua"], " ")
	check(Pack.read(path).content_hash != snapshot.content_hash)
	for i in 7:
		f = FileAccess.open(path + "/extra%d.lua" % i, FileAccess.WRITE)
		f.store_string(" ".repeat(131072))
		f.close()
	check(Pack.read(path).ok)
	f = FileAccess.open(path + "/overflow.lua", FileAccess.WRITE)
	f.store_string(" ".repeat(131072))
	f.close()
	check(not Pack.read(path).ok)
	path = fixture()
	for i in 31:
		f = FileAccess.open(path + "/extra%d.json" % i, FileAccess.WRITE)
		f.store_string("{}")
		f.close()
	check(not Pack.read(path).ok)

func test_state_version_rejects_unrepresentable_json_numbers() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fixture()+"/manifest.json"))
	manifest.state_version = 7.0
	check_eq(Manifest.validate(manifest).manifest.state_version,7,"ordinary integral JSON number stays valid")
	manifest.state_version = 9223372036854775807
	check_eq(Manifest.validate(manifest).manifest.state_version,9223372036854775807,"actual host intmax retains its exact identity")
	manifest.state_version = JSON.parse_string("9223372036854774784")
	check(Manifest.validate(manifest).ok,"largest representable float below signed limit stays valid")
	for number in ["9223372036854775808","9223372036854775807","1e30","-1","0","1.5"]:
		manifest.state_version = JSON.parse_string(number)
		check(not Manifest.validate(manifest).ok,"unusable JSON version rejected: "+number)
		var path:=fixture()
		var file:=FileAccess.open(path+"/manifest.json",FileAccess.WRITE)
		file.store_string(JSON.stringify(manifest)); file.close()
		check(not Pack.read(path).ok,"pack admission rejects unusable JSON version")
