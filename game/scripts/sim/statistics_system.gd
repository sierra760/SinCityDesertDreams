# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Monthly histories for the Graphs window and the city-status summary lines.
##
## Samples every series once a month into CityStats.history and labels the
## settlement class. Observes only; never changes the map or the simulation.
extends SimSystem

const ScanTables := preload("res://scripts/sim/data/public_scan_tables.gd")

var _samples := 0
var _status_lines: Array[String] = []
var _last_status := -1
var _stats: CityStats
## Weak, so the context that owns this system is not kept alive by it.
var _ctx_ref: WeakRef


func _init() -> void:
	key = &"statistics"


func setup(ctx: SimContext) -> void:
	_stats = ctx.stats
	_ctx_ref = weakref(ctx)
	if _status_lines.is_empty():
		_refresh_status(ctx)


func monthly(ctx: SimContext, _phase: int = 0) -> void:
	_sample(ctx)
	_refresh_status(ctx)


# ── Public getters ───────────────────────────────────────────────────────

## Series names in Graphs-window order.
func names() -> Array[StringName]:
	var out: Array[StringName] = []
	for n in StatisticsParams.SERIES:
		out.append(n)
	return out


## The newest `years` years of a series, oldest first. `years` rounds up to
## the nearest offered window (1, 10 or 100).
func series(name: StringName, years: int) -> PackedInt32Array:
	if _stats == null:
		return PackedInt32Array()
	var arr: PackedInt32Array = _stats.history.get(name, PackedInt32Array())
	var months := window_years(years) * GameClock.MONTHS_PER_YEAR
	if arr.size() <= months:
		return arr.duplicate()
	return arr.slice(arr.size() - months)


## The offered window a request rounds up to.
static func window_years(years: int) -> int:
	for w in StatisticsParams.WINDOWS:
		if years <= w:
			return w
	return StatisticsParams.WINDOWS[StatisticsParams.WINDOWS.size() - 1]


## The settlement class label for a status index.
static func status_name(status: int) -> String:
	var names := StatisticsParams.STATUS_NAMES
	return names[clampi(status, 0, names.size() - 1)]


## Short summary lines: class, date, population, funds, employment, approval,
## as of the last monthly report.
func status_lines() -> Array[String]:
	return _status_lines.duplicate()


## The same summary built from the city as it is right now (its current name,
## date, treasury and weather), for the status bar; the monthly report when
## there is no context.
func status_lines_now() -> Array[String]:
	var ctx: SimContext = _ctx_ref.get_ref() if _ctx_ref != null else null
	if ctx == null or ctx.city == null:
		return status_lines()
	return _lines_for(ctx)


## Months sampled since founding.
func samples_taken() -> int:
	return _samples


# ── Sampling ─────────────────────────────────────────────────────────────

func _sample(ctx: SimContext) -> void:
	var st := ctx.stats
	var counts := _zone_tile_counts(ctx.city)
	var keep := StatisticsParams.KEEP_MONTHS
	st.record(&"population", st.total_population(), keep)
	st.record(&"residents", counts.x, keep)
	st.record(&"commercial", counts.y, keep)
	st.record(&"industrial", counts.z, keep)
	st.record(&"money", clampi(ctx.city.funds, StatisticsParams.MONEY_MIN, StatisticsParams.MONEY_MAX), keep)
	st.record(&"crime", st.average_crime, keep)
	st.record(&"pollution", st.average_pollution, keep)
	st.record(&"land_value", st.average_land_value, keep)
	st.record(&"traffic", st.average_traffic, keep)
	st.record(&"power_percent", spare_percent(st.power_capacity, st.power_demand), keep)
	st.record(&"water_percent", spare_percent(st.water_capacity, st.water_demand), keep)
	st.record(&"unemployment", st.unemployment, keep)
	st.record(&"health", st.life_expectancy, keep)
	st.record(&"education", st.education_quotient, keep)
	st.record(&"demand_residential", st.demand.x, keep)
	st.record(&"demand_commercial", st.demand.y, keep)
	st.record(&"demand_industrial", st.demand.z, keep)
	var transport := ctx.system(&"transport")
	var riders := 0
	if transport != null and transport.has_method("monthly_ridership"):
		riders = int(transport.call("monthly_ridership"))
	st.record(&"transit_riders", riders, keep)
	_samples += 1


## Unused capacity as a percentage, 0 when there is no capacity at all.
static func spare_percent(capacity: int, demand: int) -> int:
	if capacity <= 0:
		return 0
	@warning_ignore("integer_division")
	var used := demand * 100 / capacity
	return clampi(100 - used, 0, 100)


## Developed residential, commercial and industrial tiles, one count per tile
## of every occupied lot.
static func _zone_tile_counts(city: City) -> Vector3i:
	var out := Vector3i.ZERO
	var data := city.building.data
	var categories := ScanTables.categories()
	for i in data.size():
		var id := data[i]
		if id == Buildings.NONE:
			continue
		match categories[id]:
			Buildings.Category.RESIDENTIAL:
				out.x += 1
			Buildings.Category.COMMERCIAL:
				out.y += 1
			Buildings.Category.INDUSTRIAL:
				out.z += 1
	return out


func _refresh_status(ctx: SimContext) -> void:
	_last_status = ctx.city.status
	_status_lines = _lines_for(ctx)


static func _lines_for(ctx: SimContext) -> Array[String]:
	var st := ctx.stats
	var city := ctx.city
	var lines: Array[String] = [
		"%s, a %s" % [city.name, status_name(city.status)],
		ctx.clock.date_text(),
		"Population %s" % NewsStories.count_text({"count": st.total_population()}),
		"Funds %s" % NoticeLines.money(city.funds),
		"Employment %d%%" % clampi(100 - st.unemployment, 0, 100),
		"Approval %d%%" % st.approval,
	]
	var environment := ctx.system(&"environment")
	if environment != null and environment.has_method("precipitation"):
		# Map directions: the view may be turned, so "west" names the map's west.
		var name := String(environment.call("wind_from_name")) if environment.has_method("wind_from_name") else ""
		lines.append("Rain this month %d%%, wind %d mph%s" % [int(environment.call("precipitation")),
			int(environment.call("wind_speed")), (" from the map's " + name) if name != "" else ""])
	if st.water_storage_capacity > 0:
		lines.append("Water towers hold %s of %s" % [NewsStories.count_text({"count": st.water_stored}),
			NewsStories.count_text({"count": st.water_storage_capacity})])
	return lines


# ── Persistence ──────────────────────────────────────────────────────────

func save() -> Dictionary:
	return {
		"samples": _samples,
		"status_lines": _status_lines.duplicate(),
		"last_status": _last_status,
	}


func load(data: Dictionary) -> void:
	_samples = int(data.get("samples", 0))
	_last_status = int(data.get("last_status", -1))
	_status_lines.clear()
	var lines: Variant = data.get("status_lines", [])
	if typeof(lines) == TYPE_ARRAY:
		for l in lines:
			_status_lines.append(String(l))
