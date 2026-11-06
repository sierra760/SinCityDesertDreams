# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## SHA-256 hashes of deterministic outputs from the monthly simulation scans,
## network geometry and the 3D view's growth refresh, so later changes cannot
## alter them unnoticed. A mismatch prints the current hash. When an output
## changes on purpose, run the affected tests with PRINT_GOLDENS=1 and paste
## the printed lines here.
##
## The goldens are recorded on macOS. Windows rounds some engine math
## differently, so PLATFORM_HASHES holds that platform's hash for each output
## that differs there; record a Windows change there the same way.
extends RefCounted

const HASHES := {
	"monthly_scan/economy": "120014198a51151a6d1b54129a2c5ac5a1db1ba26eefe36170a168b20fc295ce",
	"monthly_scan/population": "e56e7054a2ce978be74efd15ee1b8456f426b0e33b2f13d4d5395fbf7653e852",
	"monthly_scan/budget": "7005cf2678ddd55a74381c9fa1c52a9c8d2e16d5c387bf29d73fd402c3982987",
	"monthly_scan/disaster": "0c88115ef6b5c6f8cdc1abbbb069144ec9d53489197b5e4aebd27ff6a4c84365",
	"network_physics/mixed_far_city": "5728ec5de76280b583340b09f3a7aad9fe039a622973190da6b43011bb4961fa",
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
	"growth_lots/La Presa": "001f0160708cd4ea5c36963df83c15fd22cc3e3febec35f22776344455d60e42",
	"growth_lots/Foothills Ranch": "5e8ba3bd0a3c71585de50b5dcb4bce50e2628735dbe9010aaeaef0aa4de42240",
	"growth_lots/Valle del Mar": "a7c6d617ccddf8f3b4ba16a4727d865bc3a305e33c83c90cf69000536b311358",
	"growth_lots/Oro Canyon": "d4997580134f6295a7b4339a438926086cc48a9295ce43bed03c6610266d812e",
	"growth_lots/Aliso Niguel": "5e27381ac4a3eb45955aad21553c84adc43ff44aa41f3679a9ca52f3d4d1496d",
	"growth_lots/Grant Pass - Soledad": "641fcd2d0fb8d06e43c8724d6e6e29ed6dc1db2f62f8721d5ca3329df5400a52",
	"growth_lots/Lawndale": "e1e36c48f625d2bcc14b81592c8b529551978b841a6fd0bbff44debe83b73f44",
	"growth_lots/Salton Shores": "096cdf32b31b5dafbf3b49ec6d8ae06a8b4a21cd3704ff5d445bb5480b06caef",
	"growth_view/La Presa": "b15ea5fac3a01733e78961573daf8103d6d7e8b67d201df53e193bb6f09364f2",
	"growth_view/Foothills Ranch": "252dc81a1fd9e70b27c4b9afc903528ed707965e5fd563fec53755c3fff93cdb",
	"growth_view/Valle del Mar": "ae09be17a9d51200c0679b516325e8e6a4253fffc27b73f6a070a9a6fb782d3b",
	"growth_batcher/synthetic": "8dcae3a61c329ba42deaede987e93462214ae1def30a8021b45d84d5a1d2e365",
}

const PLATFORM_HASHES := {
	"Windows": {
		"network_physics/mixed_far_city": "f8b3fede66ac8d41e39b7daab3f0d04aac82347b41d68aab4913b0e9d5768588",
		"ramp/32_3": "3b1b1adbbf13b8e1afa5a50beece0595f6938708a68fbab2a06c78dbb303c403",
		"ramp/32_5": "2cb8908033fa4ce13d82bd4267af844edb0d1ccfda1554001210c5b29c9e6f26",
		"ramp/32_10": "b22092a676621280f2eb71b1b2a33d6b64ebdf9651eee8e46d665a24edea1ad0",
		"ramp/32_12": "3838bcef746c55e7bc4049dadc467b572b1db526258467ee4cdec8ca7aaf05c1",
	},
}


## Returns a copy of reference in which the entries recorded for the running
## platform in overrides (keyed by OS.get_name()) replace their counterparts.
## Works for golden dictionaries and for arrays of goldens keyed by index.
static func for_platform(reference: Variant, overrides: Dictionary) -> Variant:
	var table: Variant = reference.duplicate()
	var platform: Dictionary = overrides.get(OS.get_name(), {})
	for key: Variant in platform:
		table[key] = platform[key]
	return table


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
	var expected: String = for_platform(HASHES, PLATFORM_HASHES).get(key, "")
	if digest != expected or not OS.get_environment("PRINT_GOLDENS").is_empty():
		print("\t\"%s\": \"%s\"," % [key, digest])
	return digest == expected
