# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Shared original illustration set for table views and the Explore floor.
## Presentation only: symbol IDs, ranks, suits and game rules retain their owners.
class_name ResortArtwork
extends RefCounted

const ROOT := "res://assets/desert-dreams-casino-art/"
const SETS := {&"com_corner_store": "despicables", &"arcology_comstock": "comstock", &"arcology_junction": "junction",
	&"arcology_boulder": "boulder", &"arcology_orbit": "orbit"}
const ASSETS := ["symbol-s1", "symbol-s2", "symbol-s3", "symbol-s4", "symbol-s5", "symbol-B",
	"court-jack", "court-queen", "court-king", "card-back", "mural-history", "mural-industry",
	"mural-heritage", "cabinet-reels", "payout-s1", "payout-s2", "payout-s3", "payout-s4", "payout-s5", "payout-B"]
static var _cache: Dictionary = {}
static var _catalog: Dictionary = {}
static var _centered: Dictionary = {}

static func texture(key: StringName, asset: String) -> Texture2D:
	if not SETS.has(key) or asset not in ASSETS:
		return null
	var path := ROOT + String(SETS[key]) + "/" + asset + ".png"
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path] as Texture2D

static func symbol(key: StringName, id: String) -> Texture2D:
	return texture(key, "symbol-" + id)

static func payout(key: StringName, id: String) -> Texture2D:
	return centered(key,"payout-"+id)

## Pixel bounds of the actual subject, measured during asset packaging.
## Frames and card art use these bounds instead of uneven atlas-cell padding.
static func region(key: StringName, asset: String) -> Rect2:
	var image := texture(key,asset)
	if image == null: return Rect2()
	if _catalog.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROOT+"catalog.json"))
		if parsed is Dictionary: _catalog = parsed
	var entry: Dictionary = _catalog.get("sets",{}).get(SETS.get(key,""),{}).get("assets",{}).get(asset,{})
	var bounds: Array = entry.get("content_region",[0,0,image.get_width(),image.get_height()])
	return Rect2(bounds[0],bounds[1],bounds[2],bounds[3])

static func centered(key: StringName, asset: String) -> Texture2D:
	var id := String(key)+"/"+asset
	if not _centered.has(id):
		var source := texture(key,asset)
		if source == null: return null
		var atlas := AtlasTexture.new()
		atlas.atlas = source
		atlas.region = region(key,asset)
		atlas.filter_clip = true
		_centered[id] = atlas
	return _centered[id] as Texture2D

static func court(key: StringName, rank: int) -> Texture2D:
	match rank:
		11: return centered(key, "court-jack")
		12: return centered(key, "court-queen")
		13: return centered(key, "court-king")
	return null
