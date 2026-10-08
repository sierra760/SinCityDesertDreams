# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## SHA-256 hashes of deterministic outputs from the monthly simulation scans,
## network geometry and the 3D view's growth refresh, so later changes cannot
## alter them unnoticed. A mismatch prints the current hash. When an output
## changes on purpose, run the affected tests with PRINT_GOLDENS=1 and paste
## the printed lines here.
extends RefCounted

const HASHES := {
	"monthly_scan/economy": "6c85443e6fcd43742a82e1627efe7f69e0309761f6ede461357f520c49c09447",
	"monthly_scan/population": "3bca5708cc7c7cc428850f76b522c157735e47a41ccc5bbebd43c63ca931dc87",
	"monthly_scan/budget": "747d4a4edc9df901ac59f6f18b695695ef13278baa55ba6c23db2fad34373f29",
	"monthly_scan/disaster": "80d7cd24231c76965019bbf34ee7024fadc2b9f221e19be0f5c20b547c902284",
	"network_physics/mixed_far_city": "8dc223b8b9567fd125d42a342dc238fdb27cfb0e13b2779a53a89b0aa7fc56e3",
	"resolve/curved_floor_walls_boxes": "2ddd1309c5d607b68c0050bfa6ba7cc5b2a9e3ed81e336f216dc32cf9f4717df",
	"resolve/multigroup": "8d894ae1211036592b2cc9637958a48e3935ec70380765f158fb64734b6b2f52",
	"partition/dense_grid": "da9ff483f68b2f3ff86c9c1ac0bd7ca7d090303095c1544b641a744f0093d93b",
	"partition/overlaps_holes_acute": "131765925ee088ea783e61c1a8d42e276fcfd99e10fa64e084c7b361b739effc",
	"deck_boundaries/microscopic_junctions": "46f5ad9a6fa8d10247522d7bae4d31bbbc268ae6c140eaa34b5501f5e349fe77",
	"deck_boundaries/rotated_acute_tips": "3b36b13c366af77c8225ade6a1d2f4e4259b99fa32b9e3bf403a6c8b91d4f176",
	"deck_boundaries/dense_curve": "77b2a8a09ee62cb6533e7c09cad232db95bd4624b13b5c275637885319adaefe",
	"deck_boundaries/broad_flat": "f3c65db71ab8e4173fcf9f954bd07d512a01b2c250fdcd6adfe98e5946e4cc90",
	"deck_boundaries/contributors": "830a2fe14039246826559c1f6651dbbda6b228b14acc4b9e45356502b7ac762d",
	"curved_surface/construction": "c78078585ce2dba423b08953265ba103caa64aaad517bcd37240ccd6ce12e930",
	"ramp/29_3": "40fb39669b7c950ba88815365ab0c64c852833576aef3f4c4bfb1d6601ca8c97",
	"ramp/32_3": "8717faa2604d9d041b9fd1e0141e0f232ba3d852ff8ee6783ecd61e6e9f13b0c",
	"ramp/29_5": "9ef584f4d638b898150e452697ad2f3e8010cb7b98a54771a5ae27599f810bc1",
	"ramp/32_5": "4f4bd1c98a4128a284fb07522770a385b38b4d72519a5ff4ad4e1ce7aebaa139",
	"ramp/29_10": "8ea7c001e8f32c578fa790a7e7e14193f806395fdbcd3ac136f811183507f2f0",
	"ramp/32_10": "9bdceca9945ff0605d75cbd49638526814d8cd1e70e9e4a7674d313eb22043c6",
	"ramp/29_12": "1d4d257e9c2ecdb3ed89daff67b2bee3d8ecd4b720809c1337bd68ee03a53a72",
	"ramp/32_12": "f335d93179c3ca983b7a589f59353a00e4ea029cb8eab8d5efc3c06c7789e534",
	"world_quad/random_quads": "e2539e14c565442ce3230c3a363c869041b4bffebd576a8db4c09929d3ca8afb",
	"growth_lots/La Presa": "787805850c5596dcdb28cec716100ef6db75d9b3389c5a4e2c03d3b4d9816535",
	"growth_lots/Foothills Ranch": "6634647a1719ad56914214b42ea55aafd0079eb898a458790dc83bbb4f9793ac",
	"growth_lots/Valle del Mar": "3f9a4db357764652038be3bcc68176b9a04eaa669c1b93ec0f1fa0ff712c0cb1",
	"growth_lots/Oro Canyon": "e3ad141c71abdbe13cda8851618eab07fd5dc202a152e0b218efcc873a248767",
	"growth_lots/Aliso Niguel": "5faead38fce2822f7e3fd43d6a6aea51521cf118a03f42efdaa754ecd7551492",
	"growth_lots/Grant Pass - Soledad": "641fcd2d0fb8d06e43c8724d6e6e29ed6dc1db2f62f8721d5ca3329df5400a52",
	"growth_lots/Lawndale": "dab11b9d6ba7bbcc43ffc0e060a3c5fb90b641e7e8e131cb236310b29acd381d",
	"growth_lots/Salton Shores": "16b4b5f15f91b7018855d318d743ff3b9d7479a9308bf998a2491fdba1f6498f",
	"growth_view/La Presa": "5484c4191ff9d9b3f4274ee4ce3d5d49b2ff181cc185d7ab9c672ba768db9f4b",
	"growth_view/Foothills Ranch": "3f9604e3a733a8750cd02084a35f1834b7c75a359fa0258fae8dcfc359cd5e2d",
	"growth_view/Valle del Mar": "c13fd31db670ad49acddc468208e41e0491e013772229f4f96cf2ff7f6f06a40",
	"growth_batcher/synthetic": "8dcae3a61c329ba42deaede987e93462214ae1def30a8021b45d84d5a1d2e365",
}


static func sha(value: Variant) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes(value))
	return hash.finish().hex_encode()


## Hash with dictionary keys sorted, for values compared with == where
## insertion order does not matter.
static func unordered_sha(value: Variant) -> String:
	return sha(_sorted(value))


static func _sorted(value: Variant) -> Variant:
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return var_to_str(a) < var_to_str(b))
		var pairs := []
		for key: Variant in keys:
			pairs.append([key, _sorted(value[key])])
		return pairs
	if value is Array:
		var items := []
		for item: Variant in value:
			items.append(_sorted(item))
		return items
	return value


## True when digest equals the stored hash for key.
static func matches(key: String, digest: String) -> bool:
	var expected: String = HASHES.get(key, "")
	if digest != expected or not OS.get_environment("PRINT_GOLDENS").is_empty():
		print("\t\"%s\": \"%s\"," % [key, digest])
	return digest == expected
