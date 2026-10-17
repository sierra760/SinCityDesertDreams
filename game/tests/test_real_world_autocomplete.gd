# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
extends "res://tests/exploration/async_test_case.gd"
const Fake := preload("res://tests/real_world/fake_map_backend.gd")
var dialog: RealWorldTerrainDialog
var maps: RefCounted
func provider() -> Dictionary:
 var value := TerrainMapConfig.DEFAULT.duplicate(true)
 value.tiles.enabled=false
 value.search={"enabled":true,"url":"https://places.example.org/v1/places?q={query}&lang={lang}","format":"geojson","min_interval_ms":0,"autocomplete":true,"debounce_ms":550,"min_chars":3,"attribution":"Powered by Geoapify · © OpenStreetMap contributors","attribution_url":"https://www.geoapify.com/"}
 return value
func before_each() -> void:
 dialog=RealWorldTerrainDialog.new()
 maps=Fake.new()
 dialog.basemap.request_factory=maps.factory
 dialog.map_config.request_factory=maps.factory
 dialog.map_config.configure_cache("")
 dialog.place_search.request_factory=maps.factory
 dialog.place_search.platform_name="iOS"
 root.add_child(dialog)
 dialog.open({})
 dialog.apply_map_config(provider())
func after_each() -> void:
 dialog.close()
 dialog.free()
 await process_frame
func requests() -> Array:
 return maps.starts.filter(func(item: Dictionary) -> bool: return item.url.begins_with("https://places.example.org/"))
func type_text(text: String) -> void:
 dialog.search_field.text=text
 dialog.search_field.text_changed.emit(text)
func test_config_is_additive_and_nominatim_never_autocompletes() -> void:
 var accepted := TerrainMapConfig.validate(provider())
 check(accepted.ok)
 check(accepted.config.search.get("autocomplete",false),"autocomplete option survives validated config")
 check_eq(accepted.config.search.get("debounce_ms",0),550)
 var forbidden := provider()
 forbidden.search.url=TerrainMapConfig.DEFAULT.search.url
 check(not TerrainMapConfig.validate(forbidden).ok,"public endpoint forbids search-as-you-type")
 check(not TerrainMapConfig.validate({"schema":1,"tiles":provider().tiles,"search":dict_with_invalid_delay()}).ok,"unbounded debounce settings rejected")
 check(TerrainMapConfig.validate(TerrainMapConfig.DEFAULT).ok,"legacy submit-only provider remains accepted")
func dict_with_invalid_delay() -> Dictionary:
 var search: Dictionary=provider().search.duplicate(true)
 search.debounce_ms=-1
 return search
func test_geoapify_formatted_names_are_readable() -> void:
 var result := TerrainPlaceSearch.parse('{"type":"FeatureCollection","features":[{"type":"Feature","geometry":{"type":"Point","coordinates":[-115.1398,36.1699]},"properties":{"formatted":"Las Vegas, Nevada, United States"}}]}',"geojson")
 check(result.ok)
 check_eq(result.results.size(),1,"formatted provider result is not dropped")
 if not result.results.is_empty(): check_eq(result.results[0].name,"Las Vegas, Nevada, United States")
func test_debounce_cancellation_cache_and_hidden_dialog() -> void:
 var timer: Timer=dialog.get("_autocomplete_timer")
 check(timer!=null,"autocomplete has a cancellable debounce timer")
 if timer==null: return
 type_text("La")
 check(timer.is_stopped(),"short prefixes make no calls")
 type_text("Las")
 type_text("Las Veg")
 check(requests().is_empty(),"typing does not issue immediate requests")
 await create_timer(.7).timeout
 check_eq(requests().size(),1,"one call after typing pauses")
 var old: Node=dialog.place_search.get("_backend")
 type_text("Las Vegas")
 old.finished.emit(HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(),'{"features":[]}'.to_utf8_buffer())
 check_eq(dialog.search_results.get_child_count(),0,"obsolete reply cannot show suggestions")
 await create_timer(.7).timeout
 maps.search_json='{"type":"FeatureCollection","features":[{"geometry":{"type":"Point","coordinates":[-115.1398,36.1699]},"properties":{"formatted":"Las Vegas, Nevada"}}]}'
 maps.serve()
 await process_frame
 check_eq(dialog.search_results.get_child_count(),1,"current suggestions are visible")
 check(dialog.search_results.get_child(0).size.y>=44,"suggestion has a touch target")
 var calls := requests().size()
 type_text("Las Vegas")
 await create_timer(.7).timeout
 await process_frame
 check_eq(requests().size(),calls,"same query uses memory cache")
 type_text("Henderson")
 dialog.close()
 await create_timer(.7).timeout
 check_eq(requests().size(),calls,"closing cancels delayed lookup")

func test_hidden_owner_makes_no_autocomplete_requests() -> void:
 var owner := Control.new()
 root.add_child(owner)
 owner.hide()
 dialog.reparent(owner)
 type_text("Henderson")
 await create_timer(.7).timeout
 check(requests().is_empty(),"hidden owner cannot spend a provider request")
 dialog.reparent(root)
 owner.free()
func test_short_view_shows_first_suggestion_without_losing_typing_focus() -> void:
 root.size=Vector2i(390,420)
 dialog.apply_layout(true)
 for frame in 8: await process_frame
 type_text("Las Vegas")
 dialog.search_field.grab_focus()
 await create_timer(.7).timeout
 maps.search_json='{"features":[{"geometry":{"type":"Point","coordinates":[-115.14,36.17]},"properties":{"formatted":"Las Vegas, Nevada, United States"}}]}'
 maps.serve()
 for frame in 8: await process_frame
 var clip: Rect2=(dialog.panel.get_meta("window_chrome").body_scroll as Control).get_global_rect()
 check(dialog.search_field.has_focus(),"suggestions preserve typing focus")
 check(clip.grow(.1).encloses(dialog.search_field.get_global_rect()),"typed query remains visible")
 if dialog.search_results.get_child_count()>0:
  check(clip.grow(.1).encloses(dialog.search_results.get_child(0).get_global_rect()),"first suggestion is immediately readable on a short display")
