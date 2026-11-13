# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## What the street map, place search and published settings accept from the
## network: tile sizes are read from the image header before anything is
## decoded, hosts are normalized before provider rules apply, and a redirect
## is followed only to the host that was asked.
extends "res://tests/test_case.gd"

const PNG_SIGNATURE: Array[int] = [137, 80, 78, 71, 13, 10, 26, 10]
const NOMINATIM_SEARCH := "/search?format=jsonv2&limit={limit}&q={query}"


func _crc32(bytes: PackedByteArray) -> int:
	var crc := 0xffffffff
	for byte in bytes:
		crc ^= byte
		for bit in 8:
			crc = (crc >> 1) ^ 0xedb88320 if crc & 1 else crc >> 1
	return crc ^ 0xffffffff


func _be32(value: int) -> PackedByteArray:
	return PackedByteArray([(value >> 24) & 255, (value >> 16) & 255, (value >> 8) & 255, value & 255])


func _chunk(type: String, data: PackedByteArray) -> PackedByteArray:
	var tagged := type.to_ascii_buffer()
	tagged.append_array(data)
	var out := _be32(data.size())
	out.append_array(tagged)
	out.append_array(_be32(_crc32(tagged)))
	return out


## A well-formed one-bit grayscale PNG of `side` pixels square: a few
## kilobytes on the wire however large it claims to be.
func _blank_png(side: int) -> PackedByteArray:
	var header := _be32(side)
	header.append_array(_be32(side))
	header.append_array(PackedByteArray([1, 0, 0, 0, 0]))
	var rows := PackedByteArray()
	@warning_ignore("integer_division")
	rows.resize(side * (1 + (side + 7) / 8))
	var body := PackedByteArray(PNG_SIGNATURE)
	body.append_array(_chunk("IHDR", header))
	body.append_array(_chunk("IDAT", rows.compress(FileAccess.COMPRESSION_DEFLATE)))
	body.append_array(_chunk("IEND", PackedByteArray()))
	return body


func _tile(side: int, jpeg: bool = false) -> PackedByteArray:
	var image := Image.create(side, side, false, Image.FORMAT_RGB8)
	image.fill(Color("e8e0d0"))
	return image.save_jpg_to_buffer(0.8) if jpeg else image.save_png_to_buffer()


func test_declared_tile_size_is_read_from_the_header() -> void:
	check_eq(TerrainBasemap.declared_size(_tile(256)), Vector2i(256, 256), "PNG")
	check_eq(TerrainBasemap.declared_size(_tile(512)), Vector2i(512, 512), "PNG @2x")
	check_eq(TerrainBasemap.declared_size(_tile(256, true)), Vector2i(256, 256), "JPEG")
	check_eq(TerrainBasemap.declared_size(_tile(512, true)), Vector2i(512, 512), "JPEG @2x")
	check_eq(TerrainBasemap.declared_size(_blank_png(16384)), Vector2i(16384, 16384), "an oversize claim is read, not decoded")
	check_eq(TerrainBasemap.declared_size(PackedByteArray()), Vector2i.ZERO, "empty")
	check_eq(TerrainBasemap.declared_size("<html>not a tile</html>".to_utf8_buffer()), Vector2i.ZERO, "not an image")
	var png := _tile(256)
	check_eq(TerrainBasemap.declared_size(png.slice(0, 20)), Vector2i.ZERO, "a PNG cut off inside its header")
	var reordered := png.duplicate()
	reordered[12] = 0x74
	check_eq(TerrainBasemap.declared_size(reordered), Vector2i.ZERO, "a PNG that does not start with its header chunk")
	var jpeg := _tile(256, true)
	check_eq(TerrainBasemap.declared_size(jpeg.slice(0, 4)), Vector2i.ZERO, "a JPEG cut off before its frame header")
	check_eq(TerrainBasemap.declared_size(PackedByteArray([255, 216, 255, 218, 0, 2, 0, 0])), Vector2i.ZERO, "a JPEG with no frame header before its scan")
	var endless := PackedByteArray([255, 216])
	for i in 64:
		endless.append_array(PackedByteArray([255, 224, 0, 2]))
	check_eq(TerrainBasemap.declared_size(endless), Vector2i.ZERO, "a JPEG of nothing but application segments")


func test_tiles_of_the_expected_size_still_decode() -> void:
	check(TerrainBasemap.decode(_tile(256), 256) != null, "256 px PNG")
	check(TerrainBasemap.decode(_tile(256, true), 256) != null, "256 px JPEG")
	check(TerrainBasemap.decode(_tile(512), 512) != null, "512 px PNG")
	check(TerrainBasemap.decode(_blank_png(256), 256) != null, "a hand-built PNG is well formed")
	check(TerrainBasemap.decode(_tile(512), 256) == null, "a 512 px tile where 256 px was asked")
	check(TerrainBasemap.decode(_tile(256, true), 512) == null, "a 256 px JPEG where 512 px was asked")
	check(TerrainBasemap.decode(_tile(128), 256) == null, "an undersize tile")


func test_oversize_tile_is_refused_without_decoding_it() -> void:
	var bomb := _blank_png(16384)
	check_lt(bomb.size(), TerrainBasemap.MAX_BODY, "the response fits the body limit")
	var before := OS.get_static_memory_peak_usage()
	var started := Time.get_ticks_msec()
	check(TerrainBasemap.decode(bomb, 256) == null, "refused")
	check(TerrainBasemap.decode(bomb, 512) == null, "refused for @2x as well")
	var grown := OS.get_static_memory_peak_usage() - before
	# Decoding it would take a 16384 x 16384 image: hundreds of megabytes.
	check_lt(grown, 8 * 1048576, "memory used refusing it (%d bytes)" % grown)
	check_lt(Time.get_ticks_msec() - started, 250, "time spent refusing it")


func _search_config(url: String, autocomplete: bool = false, min_interval_ms: int = 0) -> Dictionary:
	var config: Dictionary = TerrainMapConfig.DEFAULT.duplicate(true)
	config.search.url = url
	config.search.autocomplete = autocomplete
	config.search.min_interval_ms = min_interval_ms
	return config


func test_hosts_are_normalized_before_they_are_compared() -> void:
	var nominatim := TerrainMapConfig.NOMINATIM_HOST
	for url: String in [
			"https://nominatim.openstreetmap.org" + NOMINATIM_SEARCH,
			"https://nominatim.openstreetmap.org." + NOMINATIM_SEARCH,
			"https://NOMINATIM.OpenStreetMap.ORG" + NOMINATIM_SEARCH,
			"https://nominatim.openstreetmap.org:443" + NOMINATIM_SEARCH,
			"https://nominatim.openstreetmap.org.:443" + NOMINATIM_SEARCH,
			"https://nominatim.openstreetmap.org#" + NOMINATIM_SEARCH,
			"https://nominatim.openstreetmap.org?q={query}",
			"https://user:secret@nominatim.openstreetmap.org" + NOMINATIM_SEARCH,
			"HTTPS://nominatim.openstreetmap.org" + NOMINATIM_SEARCH]:
		check_eq(TerrainMapConfig.host(url), nominatim, url)
	check_eq(TerrainMapConfig.host("https://tiles.example.com/{z}/{x}/{y}.png"), "tiles.example.com")
	check_eq(TerrainMapConfig.host("https://nominatim.openstreetmap.org.example.com/search?q={query}"), "nominatim.openstreetmap.org.example.com", "a longer name is a different host")


func test_public_nominatim_rules_cannot_be_sidestepped_by_spelling() -> void:
	for authority: String in ["nominatim.openstreetmap.org.", "nominatim.openstreetmap.org#", "nominatim.openstreetmap.org.#",
			"NOMINATIM.openstreetmap.org", "nominatim.openstreetmap.org:443", "nominatim.openstreetmap.org.:443"]:
		var url := "https://" + authority + NOMINATIM_SEARCH
		check(not TerrainMapConfig.validate(_search_config(url, true)).ok, "search as you type refused for " + authority)
		var throttled := TerrainMapConfig.validate(_search_config(url, false, 0))
		if throttled.ok:
			check_eq(int(throttled.config.search.min_interval_ms), TerrainMapConfig.NOMINATIM_MIN_INTERVAL_MS, "one request a second kept for " + authority)
		var search := TerrainPlaceSearch.new()
		var provider: Dictionary = TerrainMapConfig.DEFAULT.search.duplicate(true)
		provider.url = url
		provider.autocomplete = true
		search.configure_provider(provider)
		check(not search.autocomplete_enabled(), "the search never runs as you type against " + authority)
		search.platform_name = "iOS"
		check(not search.enabled(), "the iOS restriction holds for " + authority)
		search.free()


func test_published_urls_must_be_plain_https_addresses() -> void:
	var refused := {
		"a trailing dot": "https://tiles.example.com./{z}/{x}/{y}.png",
		"a fragment": "https://tiles.example.com/{z}/{x}/{y}.png#x",
		"a fragment in the host": "https://tiles.example.com#/{z}/{x}/{y}.png",
		"a user name": "https://user@tiles.example.com/{z}/{x}/{y}.png",
		"a password": "https://user:pass@tiles.example.com/{z}/{x}/{y}.png",
		"a port": "https://tiles.example.com:8443/{z}/{x}/{y}.png",
		"an IPv4 address": "https://203.0.113.7/{z}/{x}/{y}.png",
		"an IPv6 address": "https://[2001:db8::1]/{z}/{x}/{y}.png",
		"an empty label": "https://tiles..example.com/{z}/{x}/{y}.png",
		"a leading hyphen": "https://-tiles.example.com/{z}/{x}/{y}.png",
		"an escaped host": "https://tiles%2eexample.com/{z}/{x}/{y}.png",
		"a placeholder in the host": "https://{z}.example.com/{x}/{y}.png",
		"an underscore in the host": "https://tiles_a.example.com/{z}/{x}/{y}.png",
		"a single-label host": "https://localhost/{z}/{x}/{y}.png",
		"http": "http://tiles.example.com/{z}/{x}/{y}.png",
		"an upper-case scheme": "HTTPS://tiles.example.com/{z}/{x}/{y}.png",
		"no host": "https:///{z}/{x}/{y}.png",
	}
	for reason: String in refused:
		var config: Dictionary = TerrainMapConfig.DEFAULT.duplicate(true)
		config.tiles.url = refused[reason]
		check(not TerrainMapConfig.validate(config).ok, "tiles.url with %s is refused" % reason)
		config = TerrainMapConfig.DEFAULT.duplicate(true)
		config.tiles.hidpi_url = refused[reason]
		check(not TerrainMapConfig.validate(config).ok, "tiles.hidpi_url with %s is refused" % reason)
	var search_refused := {
		"a fragment": "https://search.example.com/v1?q={query}#x",
		"a user name": "https://user@search.example.com/v1?q={query}",
		"a port": "https://search.example.com:8443/v1?q={query}",
		"a trailing dot": "https://search.example.com./v1?q={query}",
	}
	for reason: String in search_refused:
		check(not TerrainMapConfig.validate(_search_config(search_refused[reason])).ok, "search.url with %s is refused" % reason)
		var credited := _search_config("https://search.example.com/v1?q={query}")
		credited.search.attribution_url = String(search_refused[reason]).replace("{query}", "x")
		check(not TerrainMapConfig.validate(credited).ok, "search.attribution_url with %s is refused" % reason)
	# Other providers can still be chosen by publishing a file.
	var switched: Dictionary = TerrainMapConfig.DEFAULT.duplicate(true)
	switched.tiles.url = "https://Tiles.Example-Maps.com/tiles/osm_bright/{z}/{x}/{y}.png?api_key=KEY&contact=maps@example.com"
	switched.tiles.hidpi_url = "https://tiles.example-maps.com/tiles/osm_bright/{z}/{x}/{y}@2x.png?api_key=KEY"
	switched.search.url = "https://api.example-maps.com/geocoding/v1/search?text={query}&size={limit}&lang={lang}&api_key=KEY"
	switched.search.format = "geojson"
	switched.search.autocomplete = true
	var accepted := TerrainMapConfig.validate(switched)
	check(accepted.ok, "a provider on another host is accepted: " + String(accepted.error))
	check(TerrainMapConfig.validate(TerrainMapConfig.DEFAULT).ok, "the built-in default is accepted")


func test_redirects_stay_on_the_host_that_was_asked() -> void:
	var asked := "https://tile.openstreetmap.org/3/1/2.png"
	var location := func(value: String) -> PackedStringArray: return PackedStringArray(["Content-Length: 0", "Location: " + value])
	check_eq(TerrainBasemap.redirect_target(asked, location.call("https://tile.openstreetmap.org/v2/3/1/2.png")), "https://tile.openstreetmap.org/v2/3/1/2.png", "same host")
	check_eq(TerrainBasemap.redirect_target(asked, location.call("/v2/3/1/2.png")), "https://tile.openstreetmap.org/v2/3/1/2.png", "a path on the same host")
	check_eq(TerrainBasemap.redirect_target(asked, PackedStringArray(["location:   https://TILE.openstreetmap.org/v2/3/1/2.png  "])), "https://TILE.openstreetmap.org/v2/3/1/2.png", "header name and host ignore case")
	for elsewhere: String in [
			"https://tiles.example.net/3/1/2.png",
			"http://tile.openstreetmap.org/3/1/2.png",
			"//tiles.example.net/3/1/2.png",
			"https://tile.openstreetmap.org@tiles.example.net/3/1/2.png",
			"https://tile.openstreetmap.org.tiles.example.net/3/1/2.png",
			"https://tile.openstreetmap.org:8443/3/1/2.png",
			"https://tile.openstreetmap.org./3/1/2.png",
			"https://tile.openstreetmap.org/3/1/2.png#https://tiles.example.net/",
			"https://tile.openstreetmap.org\\@tiles.example.net/3/1/2.png",
			"/\\tiles.example.net/3/1/2.png",
			"3/1/2.png",
			"ftp://tile.openstreetmap.org/3/1/2.png",
			""]:
		check_eq(TerrainBasemap.redirect_target(asked, location.call(elsewhere)), "", "not followed: '%s'" % elsewhere)
	check_eq(TerrainBasemap.redirect_target(asked, PackedStringArray(["Content-Length: 0"])), "", "no Location header")
	check_eq(TerrainBasemap.redirect_target("http://tile.openstreetmap.org/3/1/2.png", location.call("/v2/3/1/2.png")), "", "only https requests are continued")
	# The engine's own redirect handling, which goes to any host, stays off.
	var request := TerrainBasemap.NativeBackend.make_request()
	check_eq(request.max_redirects, 0, "the engine follows no redirect itself")
	check_eq(request.body_size_limit, TerrainBasemap.MAX_BODY, "the body limit is kept")
	request.free()


## The native backend without its network: records each request it would
## make and is answered by hand.
class RecordingBackend extends TerrainBasemap.NativeBackend:
	var requested: Array[String] = []
	var answers: Array = []
	func _init() -> void:
		finished.connect(func(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void: answers.append([result, code]))
	func _request() -> int:
		requested.append(_url)
		return OK
	func redirect(to: String) -> void:
		_completed(HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED, 301, PackedStringArray(["Location: " + to]), PackedByteArray())


func test_backend_follows_two_same_host_hops_and_no_other() -> void:
	var asked := "https://tile.openstreetmap.org/3/1/2.png"
	var backend := RecordingBackend.new()
	check_eq(backend.max_redirects, 2)
	check_eq(backend.start(asked, PackedStringArray()), OK)
	backend.redirect("/a/3/1/2.png")
	backend.redirect("https://tile.openstreetmap.org/b/3/1/2.png")
	check_eq(backend.requested, [asked, "https://tile.openstreetmap.org/a/3/1/2.png", "https://tile.openstreetmap.org/b/3/1/2.png"] as Array[String], "two hops on the same host")
	check(backend.answers.is_empty(), "nothing is reported while it continues")
	backend.redirect("/c/3/1/2.png")
	check_eq(backend.requested.size(), 3, "a third hop is not taken")
	check_eq(backend.answers, [[HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED, 301]], "it ends as a failed request")
	backend.free()
	backend = RecordingBackend.new()
	backend.start(asked, PackedStringArray())
	backend.redirect("https://tiles.example.net/3/1/2.png")
	check_eq(backend.requested, [asked] as Array[String], "a redirect to another host is never requested")
	check_eq(backend.answers, [[HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED, 301]], "it ends as a failed request")
	backend.free()
	backend = RecordingBackend.new()
	backend.max_redirects = 0
	backend.start(asked, PackedStringArray())
	backend.redirect("/a/3/1/2.png")
	check_eq(backend.requested, [asked] as Array[String], "with no hops allowed even the same host is not followed")
	check_eq(backend.answers.size(), 1)
	backend.free()
	backend = RecordingBackend.new()
	backend.start(asked, PackedStringArray())
	backend._completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), PackedByteArray([1, 2, 3]))
	check_eq(backend.answers, [[HTTPRequest.RESULT_SUCCESS, 200]], "an ordinary answer passes straight through")
	backend.free()
