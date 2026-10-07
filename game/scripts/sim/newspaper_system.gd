# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## The Desert Dispatch: monthly issues, extra editions and the advisor list.
##
## Collects the reports the other systems queue during the day into a small
## priority queue, prints an issue on the scheduled day (and an extra when big
## news lands), and answers the advisor panel from the same context.
extends SimSystem

## Pending stories: {kind: StringName, args: Dictionary, priority: int,
## born_day: int, seq: int}. Kept sorted, highest priority first.
var _queue: Array[Dictionary] = []
var _seq := 0
## Report dictionaries already copied today, so the same day's list is not
## absorbed twice when it is read more than once.
var _seen: Array = []
var _seen_day := -1
var _extra_day := -1
var _last_issue: Dictionary = {}
## Weak so the context's system table and this system do not keep each other alive.
var _ctx_ref: WeakRef


func _init() -> void:
	key = &"newspaper"


func setup(ctx: SimContext) -> void:
	_ctx_ref = weakref(ctx)
	if _last_issue.is_empty() and not ctx.stats.newspaper_archive.is_empty():
		_last_issue = ctx.stats.newspaper_archive[ctx.stats.newspaper_archive.size() - 1]


func daily(ctx: SimContext) -> void:
	var fresh := _absorb(ctx)
	if _extra_day == ctx.clock.day:
		return
	for story in fresh:
		if int(story["priority"]) >= NewspaperParams.EXTRA_PRIORITY:
			_publish(ctx, true)
			_extra_day = ctx.clock.day
			return


func monthly(ctx: SimContext, _phase: int = 0) -> void:
	_absorb(ctx)
	_publish(ctx, false)
	_decay()


func networks_changed(ctx: SimContext, _rect: Rect2i) -> void:
	_absorb(ctx)


# ── Public getters ───────────────────────────────────────────────────────

## The most recent issue, or an empty Dictionary before the first one.
func latest_issue() -> Dictionary:
	if _last_issue.is_empty():
		var kept := archive()
		if not kept.is_empty():
			_last_issue = kept[kept.size() - 1]
	return _last_issue


## Every kept issue, oldest first.
func archive() -> Array[Dictionary]:
	var ctx := _context()
	if ctx == null:
		return []
	return ctx.stats.newspaper_archive


## Copies of the pending stories, highest priority first.
func pending() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in _queue:
		out.append(s.duplicate(true))
	return out


## Queue one report directly, as if a system had reported it today.
func submit(ctx: SimContext, kind: StringName, args: Dictionary = {}, priority: int = 1) -> void:
	_enqueue(ctx, kind, args, priority)


## What the advisors want the mayor to hear: [{kind, title, text, urgent}],
## most urgent first. Text variants rotate with the calendar so the panel is
## stable within a day and the simulation's random stream is untouched.
func advice() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ctx := _context()
	if ctx == null:
		return out
	var st := ctx.stats
	var kinds: Array[StringName] = []
	var urgent: Dictionary = {}
	var disasters := ctx.system(&"disasters")
	if disasters != null and disasters.has_method("advice"):
		var listed: Variant = disasters.call("advice")
		if typeof(listed) == TYPE_ARRAY:
			for item in listed:
				var k := _need_kind(item)
				if k != &"" and not (k in kinds):
					kinds.append(k)
					urgent[k] = true
	if st.power_demand > 0 and _spare(st.power_capacity, st.power_demand) < NewspaperParams.SHORTAGE_MARGIN:
		_add_need(kinds, &"power_shortage")
	if st.water_demand > 0 and _spare(st.water_capacity, st.water_demand) < NewspaperParams.SHORTAGE_MARGIN:
		_add_need(kinds, &"water_shortage")
	if st.active_fires > 0:
		_add_need(kinds, &"fire_protection")
	if st.average_crime >= NewspaperParams.CRIME_WARNING:
		_add_need(kinds, &"police")
	if st.average_traffic >= NewspaperParams.TRAFFIC_WARNING:
		_add_need(kinds, &"traffic")
	if st.average_pollution >= NewspaperParams.POLLUTION_WARNING:
		_add_need(kinds, &"pollution")
	if st.unemployment >= NewspaperParams.UNEMPLOYMENT_WARNING:
		_add_need(kinds, &"unemployment")
	if maxi(st.tax_residential, maxi(st.tax_commercial, st.tax_industrial)) >= NewspaperParams.TAX_WARNING:
		_add_need(kinds, &"taxes")
	if st.approval < NewspaperParams.APPROVAL_WARNING:
		_add_need(kinds, &"approval")
	var values := NewsStories.values_for(&"", {}, ctx.city.name, ctx.city.mayor, ctx.year())
	var text_rng := SimRng.new(ctx.clock.day + 1)
	for k in kinds:
		if not AdvisorLines.has(k):
			continue
		out.append({
			"kind": k,
			"title": AdvisorLines.title(k),
			"text": AdvisorLines.line(k, values, text_rng),
			"urgent": bool(urgent.get(k, false)),
		})
	return out


# ── Absorbing reports ────────────────────────────────────────────────────

## Called by the Simulation at the end of every day, before the event queue
## is cleared, so reports made after this system's daily pass still land.
func absorb(ctx: SimContext) -> void:
	var fresh := _absorb(ctx)
	if _extra_day == ctx.clock.day:
		return
	for story in fresh:
		if int(story["priority"]) >= NewspaperParams.EXTRA_PRIORITY:
			_publish(ctx, true)
			_extra_day = ctx.clock.day
			return


## Copy reports not yet seen today into the queue. Returns the stories added.
func _absorb(ctx: SimContext) -> Array[Dictionary]:
	if ctx.clock.day != _seen_day:
		_seen.clear()
		_seen_day = ctx.clock.day
	var added: Array[Dictionary] = []
	for report in ctx.events.news:
		var known := false
		for s in _seen:
			if is_same(s, report):
				known = true
				break
		if known:
			continue
		_seen.append(report)
		var kind := StringName(String(report.get("kind", "")))
		if kind == &"":
			continue
		var args: Dictionary = report.get("args", {})
		var story := _enqueue(ctx, kind, args, int(report.get("priority", 1)))
		if not story.is_empty():
			added.append(story)
	return added


## Insert or refresh a story; returns the queued story, or {} when the queue
## was full of more important news.
func _enqueue(ctx: SimContext, kind: StringName, args: Dictionary, report_priority: int) -> Dictionary:
	var priority := maxi(NewsStories.priority_of(kind, args), priority_floor(report_priority))
	var clean := _json_args(args)
	for existing in _queue:
		if existing["kind"] == kind and _same_subject(existing["args"], clean):
			existing["priority"] = maxi(int(existing["priority"]), priority)
			existing["born_day"] = ctx.clock.day
			_sort_queue()
			return existing
	var story := {"kind": kind, "args": clean, "priority": priority, "born_day": ctx.clock.day, "seq": _seq}
	_seq += 1
	_queue.append(story)
	_sort_queue()
	if _queue.size() > NewspaperParams.QUEUE_SIZE:
		var dropped: Dictionary = _queue.pop_back()
		if is_same(dropped, story):
			return {}
	return story


static func _same_subject(a: Dictionary, b: Dictionary) -> bool:
	return NewsStories.place_text(a) == NewsStories.place_text(b) \
		and NewsStories.count_text(a) == NewsStories.count_text(b) \
		and NewsStories.kind_text(&"", a) == NewsStories.kind_text(&"", b)


func _sort_queue() -> void:
	_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["priority"]) != int(b["priority"]):
			return int(a["priority"]) > int(b["priority"])
		return int(a["seq"]) < int(b["seq"]))


func _decay() -> void:
	var kept: Array[Dictionary] = []
	for s in _queue:
		var p := int(s["priority"]) - NewsStories.decay_of(s["kind"], s["args"])
		if p > 0:
			s["priority"] = p
			kept.append(s)
	_queue = kept
	_sort_queue()


# ── Publishing ───────────────────────────────────────────────────────────

func _publish(ctx: SimContext, extra: bool) -> void:
	var city := ctx.city
	var stories: Array = []
	var printed := 0
	while printed < NewspaperParams.LEAD_COUNT and not _queue.is_empty():
		var s: Dictionary = _queue.pop_front()
		stories.append(_format(ctx, s["kind"], s["args"], int(s["priority"])))
		printed += 1
	if stories.is_empty():
		stories.append(_format(ctx, NewsStories.QUIET, {}, 0))
	var values := NewsStories.values_for(&"", {}, city.name, city.mayor, ctx.year())
	var used: Array = []
	while stories.size() < NewspaperParams.ISSUE_STORIES:
		var i := NewsStories.pick_filler(ctx.rng, used)
		if i < 0:
			break
		used.append(i)
		stories.append({
			"kind": "",
			"headline": NewsStories.filler_headline(i, values),
			"body": NewsStories.filler_body(i, values),
			"priority": 0,
			"filler": true,
		})
	var issue := {
		"title": NewspaperParams.TITLE,
		"date": ctx.clock.date_text(),
		"year": ctx.year(),
		"month": ctx.month(),
		"day": ctx.clock.day_of_month(),
		"extra": extra,
		"stories": stories,
	}
	var archive_list := ctx.stats.newspaper_archive
	archive_list.append(issue)
	while archive_list.size() > NewspaperParams.ARCHIVE_ISSUES:
		archive_list.pop_front()
	_last_issue = issue
	ctx.events.notify(&"newspaper", issue)


func _format(ctx: SimContext, kind: StringName, args: Dictionary, priority: int) -> Dictionary:
	var values := NewsStories.values_for(kind, args, ctx.city.name, ctx.city.mayor, ctx.year())
	return {
		"kind": String(kind),
		"headline": NewsStories.headline(kind, args, values, ctx.rng),
		"body": NewsStories.body(kind, args, values),
		"priority": priority,
		"filler": false,
	}


# ── Helpers ──────────────────────────────────────────────────────────────

func _context() -> SimContext:
	if _ctx_ref == null:
		return null
	var ctx: Variant = _ctx_ref.get_ref()
	return ctx if ctx is SimContext else null


## The least priority a report's own 0..3 importance guarantees: 2 means at
## least a major story, 3 at least an urgent one; 0 and 1 leave it to the kind.
static func priority_floor(report_priority: int) -> int:
	if report_priority >= 3:
		return NewspaperParams.PRIORITY_URGENT
	if report_priority == 2:
		return NewspaperParams.PRIORITY_MAJOR
	return 0


static func _spare(capacity: int, demand: int) -> int:
	if capacity <= 0:
		return 0
	@warning_ignore("integer_division")
	var used := demand * 100 / capacity
	return clampi(100 - used, 0, 100)


static func _add_need(kinds: Array[StringName], kind: StringName) -> void:
	if not (kind in kinds):
		kinds.append(kind)


static func _need_kind(item: Variant) -> StringName:
	match typeof(item):
		TYPE_STRING_NAME, TYPE_STRING:
			return AdvisorLines.normalize(StringName(String(item)))
		TYPE_DICTIONARY:
			var d: Dictionary = item
			for k in ["kind", "need"]:
				if d.has(k):
					return AdvisorLines.normalize(StringName(String(d[k])))
	return &""


## Report args with String keys and JSON-safe values; positions become "x,y".
static func _json_args(args: Dictionary) -> Dictionary:
	var out := {}
	for k in args:
		var v: Variant = args[k]
		match typeof(v):
			TYPE_VECTOR2I:
				out[String(k)] = tile_key(v)
			TYPE_STRING_NAME:
				out[String(k)] = String(v)
			TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_STRING:
				out[String(k)] = v
			_:
				out[String(k)] = str(v)
	return out


# ── Persistence ──────────────────────────────────────────────────────────

func save() -> Dictionary:
	var q: Array = []
	for s in _queue:
		q.append({
			"kind": String(s["kind"]),
			"args": s["args"],
			"priority": int(s["priority"]),
			"born_day": int(s["born_day"]),
			"seq": int(s["seq"]),
		})
	return {"queue": q, "seq": _seq, "extra_day": _extra_day}


func load(data: Dictionary) -> void:
	_queue.clear()
	var q: Variant = data.get("queue", [])
	if typeof(q) == TYPE_ARRAY:
		for item in q:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			var d: Dictionary = item
			var args: Variant = d.get("args", {})
			_queue.append({
				"kind": StringName(String(d.get("kind", "generic"))),
				"args": args if typeof(args) == TYPE_DICTIONARY else {},
				"priority": int(d.get("priority", 0)),
				"born_day": int(d.get("born_day", 0)),
				"seq": int(d.get("seq", 0)),
			})
	_seq = int(data.get("seq", _queue.size()))
	_extra_day = int(data.get("extra_day", -1))
	_seen.clear()
	_seen_day = -1
	_last_issue = {}
	_sort_queue()
