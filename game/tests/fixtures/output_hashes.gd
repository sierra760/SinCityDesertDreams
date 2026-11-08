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
	"network_physics/mixed_far_city": "c34248a34632d93e51abc1a70422be57a704f510974a5aced3b45541dd8afe75",
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
	"ramp/29_3": "1a4c68997f62aefcce8a725b5be02fab94c109c477de7a1815172c3efa836dd8",
	"ramp/32_3": "6190f7a3d64929366819ff465ac75bc7458ef680f52e34aa49f93e2234fdc0cb",
	"ramp/29_5": "29107c8b2d25d3d91a26144ea6b5b0369761bf6d3678e9d292ffb6772131d76a",
	"ramp/32_5": "d6d3bd2ddd9a291baa46479a3f60dbac21e612d5152d801f92fc7a808331328f",
	"ramp/29_10": "537f051a9b7d0a12642197047271c964034b493f5ba1b10365557aa6f40aaaac",
	"ramp/32_10": "0a82d140ce1fc9df31013e116fd214856ef6aea706e35a58f0fbbe652efa04af",
	"ramp/29_12": "ad641d7d1e65a44e5a7c72a7ddf702689023a7dea265c93cf62269c314496126",
	"ramp/32_12": "fe985d8c5553d782681a1c3ed9fb97e15f680df1b8632b5f27569b75ca846a56",
	"world_quad/random_quads": "e2539e14c565442ce3230c3a363c869041b4bffebd576a8db4c09929d3ca8afb",
	# Model subtrees include the prepared-night source tag; view refreshes also
	# include the current casino signs and Mayor's House model.
	"growth_lots/La Presa": "22d0e7c9309bb6bd17ab639ac8e746f1f33d5caaa6d6f412406c907c2cff046f",
	"growth_lots/Foothills Ranch": "85e4e76e84c18c5b5eefd7d0b5624176b2151be192b3eb171f1ab2d8218680df",
	"growth_lots/Valle del Mar": "37a964213d0cbfb6175eeb92f10d95ee37b8df98940e8b69cf38814b73de6b6d",
	"growth_lots/Oro Canyon": "0ecae991c6efa96d07dbeee024053d98bdb5436f346f8d043eae8a86f6569d95",
	"growth_lots/Aliso Niguel": "2636c33105eb67511febb5e5e5e5edd7813536b0dc8099448bd30827dcb8bd1e",
	"growth_lots/Grant Pass - Soledad": "641fcd2d0fb8d06e43c8724d6e6e29ed6dc1db2f62f8721d5ca3329df5400a52",
	"growth_lots/Lawndale": "efddd3755d6c27ec6199a5f940985d0703f5b1ed984cf04623fa4a9cf990aba1",
	"growth_lots/Salton Shores": "19c0580a659d90193b5e2e60fdc27d2dd1925698b621b1a17d12b5258fc0258e",
	"growth_view/La Presa": "1944d04505468f14168bfd25c79ec50cbddd028afd763e1381acf6532c8a12bf",
	"growth_view/Foothills Ranch": "1c93981ca3df88312d039b67f3c4d977246f96315b171b7ee5753a20a9b239c0",
	"growth_view/Valle del Mar": "0e6e4d1db9d5e175e15488e50b0bde82b7fa492fe64f9a04c02e86fcd64daf96",
	"growth_batcher/synthetic": "8dcae3a61c329ba42deaede987e93462214ae1def30a8021b45d84d5a1d2e365",
}

const PLATFORM_HASHES := {
	"Windows": {
		"ramp/32_3": "7116f46522f4c1827ab5f65d59a0a1f3d7ba6496f44533bd94123faac5d827c7",
		"ramp/32_5": "39cea01ca5e4f7e153a849701659d38822c86c6e40053555ad6d322bb81a77fd",
		"ramp/32_10": "0b66e6e3b4365450cf064b49d84e718e879362c5529c3bb7e59357a97ab4029a",
		"ramp/32_12": "006dd146677f9c465366e9b614e3515c0b2ee2ece1e77f2ae261380fd0c10a28",
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
