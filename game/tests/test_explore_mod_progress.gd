# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/test_case.gd"
func test_invalid_record_identity_is_transactional() -> void:
	var progress := ExploreModProgress.new()
	check(progress.commit("known",1,"1",{"accepted":true}).ok)
	var before := progress.snapshot()
	check(not progress.commit("",1,"1",{}).ok,"empty owner rejected")
	check(not progress.commit("other",0,"1",{}).ok,"invalid state version rejected")
	check_eq(progress.snapshot(),before)
func test_mismatch_reset_and_copy() -> void:
	var progress := ExploreModProgress.new()
	var data := {"phase":["accepted"]}
	check(progress.commit("unknown",1,"1",data).ok)
	data.phase.append("changed")
	check_eq(progress.get_state("unknown",1).data.phase,["accepted"])
	check_eq(progress.get_state("unknown",2).code,"state_version_mismatch")
	check(not progress.commit("unknown",2,"2",{}).ok)
	progress.reset("unknown")
	check_eq(progress.snapshot(),{})
func test_bad_writes_keep_prior_committed_state() -> void:
	var progress := ExploreModProgress.new()
	check(progress.commit("safe",1,"1",{"phase":"accepted"}).ok)
	var before := progress.snapshot()
	var cycle := {}
	cycle["cycle"] = cycle
	var deep: Dictionary = {"v":1}
	for i in 9: deep = {"v":deep}
	for invalid in [{"v":NAN},{"v":INF},cycle,deep,{"v":Vector3.ZERO},{"v":"x".repeat(4097)}]:
		check(not progress.commit("safe",1,"1",invalid).ok)
		check_eq(progress.snapshot(),before)
	cycle.clear()
func test_caps_and_restore_roundtrip() -> void:
	var progress := ExploreModProgress.new()
	var large := {}
	for i in 15: large[str(i)] = "x".repeat(4096)
	check(progress.commit("a",1,"1",large).ok)
	var before := progress.snapshot()
	check(not progress.commit("a",1,"1",{"extra":"x".repeat(4096)}).ok)
	check_eq(progress.snapshot(),before)
	for i in 7: check(progress.commit("p"+str(i),1,"1",large).ok)
	before = progress.snapshot()
	check(not progress.commit("overflow",1,"1",large).ok)
	check_eq(progress.snapshot(),before)
	var restored := ExploreModProgress.new()
	check(restored.restore(JSON.parse_string(JSON.stringify(before))).ok)
	check_eq(restored.snapshot(),before)
	progress.restore({})
	for i in 64: check(progress.commit("p"+str(i),1,"1",{}).ok)
	check(not progress.commit("overflow",1,"1",{}).ok)
func test_data_depth_roundtrip_and_malformed_restore() -> void:
	var progress := ExploreModProgress.new()
	var data := {"leaf":true}
	for i in 7: data = {"child":data}
	check(progress.commit("deep",1,"1",data).ok)
	var copy := ExploreModProgress.new()
	check(copy.restore(progress.snapshot()).ok,"canonical envelope does not reduce data depth")
	check_eq(copy.snapshot(),progress.snapshot())
	for bad in [null,[],{"format_version":2,"mods":{}},{"format_version":1,"mods":{"x":{"state_version":1.5,"pack_version":"1","data":{}}}}]:
		check(not copy.restore(bad).ok)
		check_eq(copy.snapshot(),{})
func test_state_mismatch_stays_inert_until_explicit_reset() -> void:
	var progress := ExploreModProgress.new()
	check(progress.commit("desert_delivery",2,"2.0.0",{"accepted":true}).ok)
	var before := progress.snapshot()
	var runtime := ExploreModRuntime.new()
	var pack := ExploreModPack.read("res://explore_mods/desert_delivery")
	runtime.bind([pack],progress,1)
	check(not runtime.has_owner("desert_delivery"))
	check_eq(runtime.diagnostics[0].reason,"state_version_mismatch")
	check_eq(progress.snapshot(),before)
	runtime.stop("test")
	progress.reset("desert_delivery")
	check_eq(progress.get_state("desert_delivery",1).data,{})

func test_state_version_range_matches_manifest_types() -> void:
	var record: Dictionary={"state_version":9223372036854775807,"pack_version":"1.0.0","data":{}}
	check(ExploreModProgress._valid_record(record),"actual intmax is representable without float conversion")
	var progress:=ExploreModProgress.new()
	check(progress.restore({"format_version":1,"mods":{"largest":record}}).ok)
	check(progress.get_state("largest",9223372036854775807).ok)
	for number in ["9223372036854775808","1e30"]:
		record.state_version=JSON.parse_string(number)
		check(not ExploreModProgress._valid_record(record),"out-of-range integral JSON float rejected")
	record.state_version=JSON.parse_string("9223372036854774784")
	check(ExploreModProgress._valid_record(record),"representable upper JSON float remains valid")
