# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.
extends "res://tests/test_case.gd"
const RESOURCE = {"source":"worldcover","tile":"N36W117"}
const SPAN = {"offset":10,"length":4}
const IDENTITY = {"etag":"\"v1\"","size":100}
const ROOT = "user://terrain_tiles_v1/cache-test"
var cache: TerrainTileCache
func before_each() -> void:
 cache=TerrainTileCache.new()
 cache.configure(ROOT,1100)
 cache.clear()
func after_each() -> void: cache.clear()
func write_bytes(path: String, body: PackedByteArray) -> void:
 var file := FileAccess.open(path,FileAccess.WRITE)
 check(file!=null,"fixture file writable")
 if file!=null: file.store_buffer(body)
func test_atomic_cache_hash_identity_eviction() -> void:
 var first := cache.publish(RESOURCE,SPAN,IDENTITY,PackedByteArray([1,2,3,4]))
 check(first.ok,"validated body is published")
 var hit := cache.lookup(RESOURCE,SPAN,IDENTITY)
 check(hit.ok)
 if hit.ok: check_eq(hit.body,PackedByteArray([1,2,3,4]))
 check(not cache.lookup(RESOURCE,SPAN,{"etag":"\"v2\"","size":100}).ok)
 if first.ok:
  write_bytes(first.body_path,PackedByteArray([9,9,9,9]))
  check(not cache.lookup(RESOURCE,SPAN,IDENTITY).ok,"content hash catches corruption")
  cache.publish(RESOURCE,SPAN,IDENTITY,PackedByteArray([1,2,3,4]))
  DirAccess.remove_absolute(first.index_path)
  check(not cache.lookup(RESOURCE,SPAN,IDENTITY).ok,"torn body without published index is unavailable")
 cache.clear()
 var lru_body := PackedByteArray()
 lru_body.resize(128)
 lru_body.fill(80)
 var lru_identity := {"etag":"\"v1\"","size":1000}
 var hot := {"offset":128,"length":128}
 var cold := {"offset":256,"length":128}
 var fresh := {"offset":384,"length":128}
 check(cache.publish(RESOURCE,hot,lru_identity,lru_body).ok)
 check(cache.publish(RESOURCE,cold,lru_identity,lru_body).ok)
 check(cache.lookup(RESOURCE,hot,lru_identity).ok)
 check(cache.publish(RESOURCE,fresh,lru_identity,lru_body).ok)
 check(cache.lookup(RESOURCE,hot,lru_identity).ok,"recent access survives eviction")
 check(not cache.lookup(RESOURCE,cold,lru_identity).ok,"oldest entry evicted")
 check(cache.lookup(RESOURCE,fresh,lru_identity).ok)

func test_clear_touches_only_owned_cache() -> void:
 DirAccess.make_dir_recursive_absolute(ROOT)
 var unrelated := ROOT+"/unrelated.sc2d"
 write_bytes(unrelated,PackedByteArray([5,6,7]))
 cache.publish(RESOURCE,SPAN,IDENTITY,PackedByteArray([1,2,3,4]))
 check(cache.clear().ok)
 check(FileAccess.file_exists(unrelated))
 check_eq(FileAccess.get_file_as_bytes(unrelated),PackedByteArray([5,6,7]))
 check(not cache.lookup(RESOURCE,SPAN,IDENTITY).ok)
 DirAccess.remove_absolute(unrelated)
 cache.configure("user://terrain_tiles_v1/../saves")
 check(not cache.clear().ok,"traversal rejected")
 cache.configure("user://saves")
 check(not cache.publish(RESOURCE,SPAN,IDENTITY,PackedByteArray([1,2,3,4])).ok)
func test_metadata_ranges_and_body_caps() -> void:
 check(not cache.publish(RESOURCE,SPAN,IDENTITY,PackedByteArray([1,2,3])).ok)
 check(not cache.publish({"source":"worldcover","tile":"N36W117","url":"evil"},SPAN,IDENTITY,PackedByteArray([1,2,3,4])).ok)
 check(not cache.publish(RESOURCE,SPAN,{"etag":"bad\r\nheader","size":100},PackedByteArray([1,2,3,4])).ok)
 check(not cache.publish(RESOURCE,{"offset":99,"length":4},IDENTITY,PackedByteArray([1,2,3,4])).ok)
 var first := cache.publish(RESOURCE,SPAN,IDENTITY,PackedByteArray([1,2,3,4]))
 if first.ok:
  write_bytes(first.index_path,"{}".to_utf8_buffer())
  check(not cache.lookup(RESOURCE,SPAN,IDENTITY).ok,"malformed metadata rejected")

func test_orphaned_and_torn_entries_do_not_escape_disk_budget() -> void:
 var first := cache.publish(RESOURCE,SPAN,IDENTITY,PackedByteArray([1,2,3,4]))
 check(first.ok)
 if not first.ok: return
 DirAccess.remove_absolute(first.index_path)
 var temporary: String = first.body_path+".tmp"
 write_bytes(temporary,PackedByteArray([9,9,9,9]))
 cache.publish(RESOURCE,{"offset":20,"length":4},IDENTITY,PackedByteArray([5,6,7,8]))
 cache.publish(RESOURCE,{"offset":30,"length":4},IDENTITY,PackedByteArray([9,10,11,12]))
 check(not FileAccess.file_exists(first.body_path),"orphaned body is recovered before publication")
 check(not FileAccess.file_exists(temporary),"torn owned staging file is recovered")
func test_symlink_roots_and_entry_paths_are_rejected() -> void:
 DirAccess.make_dir_recursive_absolute(ROOT)
 var unrelated := ROOT+"/unrelated.sc2d"
 write_bytes(unrelated,PackedByteArray([5,6,7]))
 var first := cache.publish(RESOURCE,SPAN,IDENTITY,PackedByteArray([1,2,3,4]))
 check(first.ok)
 if not first.ok: return
 DirAccess.remove_absolute(first.body_path)
 var directory := DirAccess.open(ROOT)
 check_eq(directory.create_link(ProjectSettings.globalize_path(unrelated),first.body_path.get_file()),OK)
 check(not cache.lookup(RESOURCE,SPAN,IDENTITY).ok)
 check(not cache.publish(RESOURCE,SPAN,IDENTITY,PackedByteArray([1,2,3,4])).ok)
 check(not cache.clear().ok)
 check_eq(FileAccess.get_file_as_bytes(unrelated),PackedByteArray([5,6,7]))
 DirAccess.remove_absolute(first.body_path)
 cache.clear()
 check_eq(directory.create_link(ProjectSettings.globalize_path(ROOT),"nested-link"),OK)
 cache.configure(ROOT+"/nested-link")
 check(not cache.clear().ok,"symlink descendant never scans its target")
 check(not cache.publish(RESOURCE,SPAN,IDENTITY,PackedByteArray([1,2,3,4])).ok)
 DirAccess.remove_absolute(ROOT+"/nested-link")
 DirAccess.remove_absolute(unrelated)
 cache.configure(ROOT,1100)

func owned_disk_bytes() -> int:
 var directory := DirAccess.open(ROOT)
 if directory==null: return 0
 var total := 0
 for name in directory.get_files():
  if not name.begins_with("terrain-v1-"): continue
  var file := FileAccess.open(ROOT.path_join(name),FileAccess.READ)
  if file!=null: total+=file.get_length()
 return total
func test_metadata_and_temporary_publication_headroom_use_disk_budget() -> void:
 var body := PackedByteArray()
 body.resize(128)
 body.fill(80)
 var identity := {"etag":"\"v1\"","size":1000}
 var span := {"offset":128,"length":128}
 cache.configure(ROOT,300)
 check(not cache.publish(RESOURCE,span,identity,body).ok,"body plus commit marker exceeds disk budget")
 check_eq(owned_disk_bytes(),0,"failed reservation writes no publication files")
 cache.configure(ROOT,520)
 check(cache.publish(RESOURCE,span,identity,body).ok)
 var replacement := body.duplicate()
 replacement.fill(60)
 check(not cache.publish(RESOURCE,span,identity,replacement).ok,"replacement must reserve temporary marker space before overwriting body")
 check(owned_disk_bytes()<=520)
 cache.configure(ROOT,1100)
 var retained := cache.lookup(RESOURCE,span,identity)
 check(retained.ok)
 if retained.ok: check_eq(retained.body,body,"failed reservation retains previous committed entry")

func seed_persisted_access(publication: Dictionary, access: String) -> void:
 var metadata: Variant = JSON.parse_string(FileAccess.get_file_as_string(publication.index_path))
 check(metadata is Dictionary,"fixture commit metadata is valid")
 if not metadata is Dictionary: return
 metadata.access=access
 write_bytes(publication.index_path,JSON.stringify(metadata).to_utf8_buffer())
func test_reopened_and_reconfigured_cache_hits_advance_past_all_persisted_access() -> void:
 var body := PackedByteArray()
 body.resize(128)
 body.fill(80)
 var identity := {"etag":"\"v1\"","size":1000}
 var hit_a := {"offset":128,"length":128}
 var untouched_b := {"offset":256,"length":128}
 var new_c := {"offset":384,"length":128}
 for mode in ["reopened","root_changed"]:
  var fixture_root: String = ROOT if mode=="reopened" else ROOT+"/reopened-root"
  cache.configure(fixture_root,1100)
  cache.clear()
  var a := cache.publish(RESOURCE,hit_a,identity,body)
  var b := cache.publish(RESOURCE,untouched_b,identity,body)
  check(a.ok and b.ok,"two entries published before simulated restart")
  if not a.ok or not b.ok: continue
  # Persisted logical times exceed the new process's monotonic clock.
  var previous_session := 1000000000 if mode=="reopened" else 2000000000
  seed_persisted_access(a,str(previous_session+1))
  seed_persisted_access(b,str(previous_session+102))
  if mode=="reopened":
   cache=TerrainTileCache.new()
  else:
   cache.configure(ROOT,1100)
  cache.configure(fixture_root,1100)
  check(cache.lookup(RESOURCE,hit_a,identity).ok,"A hit after restart/root change")
  check(cache.publish(RESOURCE,new_c,identity,body).ok,"C publication under disk pressure")
  check(cache.lookup(RESOURCE,hit_a,identity).ok,"just-used A survives "+mode)
  check(not cache.lookup(RESOURCE,untouched_b,identity).ok,"untouched B evicted after "+mode)
  check(cache.lookup(RESOURCE,new_c,identity).ok,"new C survives "+mode)
  cache.clear()
 cache.configure(ROOT,1100)
# Platform data directories can live below symlinked system paths (iOS /var,
# Android /data/user/0). Only segments from user:// downward are examined.
func test_symlink_walk_starts_at_user_data_directory() -> void:
 var real := ROOT+"/real-data"
 DirAccess.make_dir_recursive_absolute(real+"/terrain_tiles_v1")
 var directory := DirAccess.open(ROOT)
 check_eq(directory.create_link(ProjectSettings.globalize_path(real),"linked-data"),OK)
 var linked_base := ProjectSettings.globalize_path(ROOT+"/linked-data")
 check(TerrainTileCache.symlink_free_below(linked_base,"terrain_tiles_v1"),"symlinked ancestors of the data directory are accepted")
 check(not TerrainTileCache.symlink_free_below(ProjectSettings.globalize_path("user://"),ROOT.trim_prefix("user://")+"/linked-data/terrain_tiles_v1"),"symlinks inside the cache path are rejected")
 check(not TerrainTileCache.symlink_free_below(ProjectSettings.globalize_path(ROOT),"linked-data"),"a symlinked final segment is rejected")
 DirAccess.remove_absolute(ROOT+"/linked-data")
 DirAccess.remove_absolute(real+"/terrain_tiles_v1")
 DirAccess.remove_absolute(real)
 check(cache.publish(RESOURCE,SPAN,IDENTITY,PackedByteArray([1,2,3,4])).ok,"ordinary root still publishes")
# The in-memory index must track disk exactly through hits, replacements,
# eviction and external tampering, preserving least-recent-access eviction.
func test_in_memory_index_tracks_disk_under_pressure() -> void:
 var identity := {"etag":"\"v1\"","size":100000}
 var body := PackedByteArray()
 body.resize(64)
 body.fill(7)
 cache.configure(ROOT,2000)
 var spans: Array[Dictionary] = []
 for i in 12: spans.append({"offset":i*64,"length":64})
 for i in 12:
  check(cache.publish(RESOURCE,spans[i],identity,body).ok,"publication %d"%i)
  if i>=1: check(cache.lookup(RESOURCE,spans[0],identity).ok,"hot entry keeps hitting")
  check_eq(cache._total,owned_disk_bytes(),"tracked bytes equal disk after step %d"%i)
  check(owned_disk_bytes()<=2000)
 check(cache.lookup(RESOURCE,spans[0],identity).ok,"most recently accessed survives every eviction")
 check(cache.lookup(RESOURCE,spans[11],identity).ok,"newest survives")
 check(not cache.lookup(RESOURCE,spans[1],identity).ok,"oldest untouched entry evicted")
 var replacement := body.duplicate()
 replacement.fill(9)
 check(cache.publish(RESOURCE,spans[11],identity,replacement).ok)
 check_eq(cache._total,owned_disk_bytes(),"replacement keeps tracked bytes")
 var hit := cache.lookup(RESOURCE,spans[11],identity)
 if hit.ok: check_eq(hit.body,replacement)
 # External removal of a committed marker is reconciled on the next publication.
 var stray := cache.publish(RESOURCE,{"offset":5000,"length":64},identity,body)
 check(stray.ok)
 if stray.ok: DirAccess.remove_absolute(stray.index_path)
 check(cache.publish(RESOURCE,{"offset":6000,"length":64},identity,body).ok)
 if stray.ok: check(not FileAccess.file_exists(stray.body_path),"orphaned body recovered")
 check_eq(cache._total,owned_disk_bytes(),"reconciled after external change")
 cache.configure(ROOT,1100)
