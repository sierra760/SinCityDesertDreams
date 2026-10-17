# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
class_name CloudSaveTypes
extends RefCounted

const MAX_ASSET_BYTES := 67108864
const MAX_DISPLAY_BYTES := 256
const MAX_ID_BYTES := 128

static func uuid() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	if bytes.size() != 16: return ""
	bytes[6] = (bytes[6] & 15) | 64
	bytes[8] = (bytes[8] & 63) | 128
	var hex := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]

static func valid_id(value: Variant, allow_empty: bool = false) -> bool:
	if not value is String or value.to_utf8_buffer().size() > MAX_ID_BYTES: return false
	if value.is_empty(): return allow_empty
	for character in value:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-": return false
	return true

static func valid_hash(value: Variant, allow_empty: bool = false) -> bool:
	if not value is String: return false
	if value.is_empty(): return allow_empty
	if value.length() != 64: return false
	for character in value:
		if not character in "0123456789abcdef": return false
	return true

static func valid_metadata(value: Variant) -> bool:
	if not value is Dictionary: return false
	for key in value:
		if not key is String or key.to_utf8_buffer().size() > MAX_ID_BYTES: return false
		var item: Variant = value[key]
		if item is String:
			if item.to_utf8_buffer().size() > MAX_DISPLAY_BYTES: return false
		elif not (item is int or item is float or item is bool): return false
	return true

static func valid_payload(value: Variant) -> bool:
	return value is Dictionary and value.get("path") is String and not value.path.is_empty() \
		and valid_hash(value.get("sha256")) and value.get("bytes") is int \
		and value.bytes > 0 and value.bytes <= MAX_ASSET_BYTES

static func valid_pending(value: Variant) -> bool:
	if not value is Dictionary: return false
	if not valid_id(value.get("slot_id")) or not valid_id(value.get("commit_id")): return false
	if not valid_id(value.get("parent_commit_id"), true) or not valid_id(value.get("owner"), true): return false
	if not value.get("generation") is int or value.generation < 1: return false
	if not value.get("baseline") is PackedByteArray or not value.get("baseline_tag") is String: return false
	if value.baseline_tag.to_utf8_buffer().size() > MAX_ID_BYTES or not value.get("tombstone") is bool: return false
	if not value.get("manual") is Dictionary: return false
	if not value.manual.is_empty() and not valid_payload(value.manual): return false
	return value.tombstone or valid_payload(value.get("continuation"))

static func valid_remote(value: Variant) -> bool:
	if not value is Dictionary: return false
	return valid_id(value.get("slot_id")) and valid_id(value.get("commit_id")) \
		and value.get("change_tag") is String and value.change_tag.to_utf8_buffer().size() <= MAX_ID_BYTES \
		and value.get("system_fields") is PackedByteArray and value.get("tombstone") is bool \
		and valid_hash(value.get("continuation_sha256"), value.get("tombstone", false)) \
		and valid_hash(value.get("manual_sha256"), true) and valid_metadata(value.get("metadata"))
