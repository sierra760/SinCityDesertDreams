# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Table colors and fonts for one resort. The shared ivory, teal and brass
## chrome comes from UITheme; the resort palette only accents it: the felt,
## the chips, the header rule and the sign lettering.
class_name CasinoPalette
extends RefCounted

## Chip colors by denomination step (1, 2, 5 and 10 times the table minimum,
## then the Max chip), each with its edge spots.
const CHIP_FACES: Array[Color] = [Color("f4ead6"), Color("b5432f"), Color("2b5f9e"), Color("2f7d4f"), Color("1c1a17")]
const CHIP_SPOTS: Array[Color] = [Color("2b5f9e"), Color("f4ead6"), Color("f4ead6"), Color("f4ead6"), Color("d8b25e")]
const CHIP_TEXT: Array[Color] = [Color("1f2a30"), Color("fff8eb"), Color("fff8eb"), Color("fff8eb"), Color("f2d48a")]

const CARD_FACE := Color("fffaf0")
const CARD_EDGE := Color("b4a58a")
const CARD_RED := Color("b5432f")
const CARD_BLACK := Color("1f2a30")
const WIN := Color("2f8a5a")
const LOSE := Color("9a3b1a")
## Win and loss words drawn straight on the dark felt (light enough to read).
const WIN_ON_FELT := Color("a8e6bd")
const LOSE_ON_FELT := Color("f0a58a")
const GOLD := Color("e2bb63")

static var _fonts: Dictionary = {}

## The resort key this palette describes.
var resort: StringName = &""
## Felt of the playing surface, a darker rim around it and the lines on it.
var felt := Color("2e5e4e")
var felt_dark := Color("1f4236")
var felt_line := Color("e9dcbf")
## Resort accent (header rule, highlights) and its paper and ink.
var accent := UITheme.ACCENT_BRASS
var metal := UITheme.ACCENT_BRASS
var wood := Color("4a2e1c")
var paper := UITheme.PANEL_FACE
var ink := UITheme.TEXT_PRIMARY
var glass := UITheme.TITLE_BAR
var lamp := Color("ffd9a0")
## Sign lettering (resort font) and body lettering.
var sign_font: Font = UITheme.DISPLAY_FONT
var body_font: Font = UITheme.DISPLAY_FONT
## Display faces whose lower case reads poorly at a glance sign in capitals.
var sign_upper := false


## The palette for a resort; unknown keys fall back to the shared chrome.
static func for_resort(key: StringName) -> CasinoPalette:
	var p := CasinoPalette.new()
	p.resort = key
	if not ResortThemes.has(key):
		return p
	p.felt = ResortThemes.color(key, "felt", p.felt)
	p.felt_dark = p.felt.darkened(0.32)
	p.felt_line = ResortThemes.color(key, "paper", p.felt_line).lerp(Color.WHITE, 0.1)
	p.accent = ResortThemes.color(key, "accent", p.accent)
	p.metal = ResortThemes.color(key, "metal", p.metal)
	p.wood = ResortThemes.color(key, "wood", p.wood)
	p.paper = ResortThemes.color(key, "paper", p.paper)
	p.ink = ResortThemes.color(key, "ink", p.ink)
	p.glass = ResortThemes.color(key, "glass", p.glass)
	p.lamp = ResortThemes.color(key, "lamp", p.lamp)
	p.sign_font = load_font(ResortThemes.font_path(key))
	p.body_font = load_font(ResortThemes.font_path(key, true))
	p.sign_upper = String(ResortThemes.theme(key).get("font", "")) == "atomic_age"
	return p


## Sign lettering for `text` in this resort's style.
func sign_text(text: String) -> String:
	return text.to_upper() if sign_upper else text


## A bundled font by resource path, loaded once.
static func load_font(path: String) -> Font:
	if _fonts.has(path):
		return _fonts[path]
	var font := load(path) as Font if ResourceLoader.exists(path) else null
	if font == null:
		font = UITheme.DISPLAY_FONT
	_fonts[path] = font
	return font


## The chip denominations for a table minimum: 1, 2, 5 and 10 times it.
static func chip_values(minimum: int) -> Array[int]:
	var out: Array[int] = []
	for step: int in CasinoParams.CHIP_STEPS:
		out.append(maxi(1, minimum) * step)
	return out


## Index of the chip color for `amount` at a table with `minimum`: the
## largest denomination step that the amount reaches.
static func chip_index(amount: int, minimum: int) -> int:
	var steps: Array = CasinoParams.CHIP_STEPS
	var index := 0
	for i in steps.size():
		if amount >= maxi(1, minimum) * int(steps[i]):
			index = i
	return index


## A short chip label: 100, 2.5K, 10K, 1M.
static func chip_label(amount: int) -> String:
	if amount >= 1000000 and amount % 100000 == 0:
		return _trim("%.1f" % (amount / 1000000.0)) + "M"
	if amount >= 1000 and amount % 100 == 0:
		return _trim("%.1f" % (amount / 1000.0)) + "K"
	return str(amount)


static func _trim(text: String) -> String:
	return text.trim_suffix(".0")


## Draw a chip (or a stack of `count` chips) centred at `center` on `canvas`.
static func draw_chip(canvas: CanvasItem, center: Vector2, radius: float, index: int, label: String, font: Font, count: int = 1) -> void:
	var i := clampi(index, 0, CHIP_FACES.size() - 1)
	var layers := clampi(count, 1, 4)
	for layer in layers:
		var c := center - Vector2(0, (layers - 1 - layer) * radius * 0.18)
		canvas.draw_circle(c + Vector2(0, radius * 0.08), radius, Color(0, 0, 0, 0.28))
		canvas.draw_circle(c, radius, CHIP_FACES[i])
		for spot in 6:
			var angle := TAU * spot / 6.0 + 0.26
			var a := c + Vector2.from_angle(angle) * radius * 0.82
			canvas.draw_circle(a, radius * 0.15, CHIP_SPOTS[i])
		canvas.draw_arc(c, radius * 0.62, 0.0, TAU, 28, CHIP_SPOTS[i], maxf(1.0, radius * 0.07), true)
		canvas.draw_arc(c, radius, 0.0, TAU, 32, CHIP_FACES[i].darkened(0.35), maxf(1.0, radius * 0.06), true)
	if label.is_empty() or font == null:
		return
	var top := center
	var size := int(clampf(radius * 0.62, 8.0, 40.0))
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var squeeze := minf(1.0, radius * 1.15 / maxf(1.0, width))
	size = maxi(6, int(size * squeeze))
	width = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	canvas.draw_string(font, top + Vector2(-width * 0.5, size * 0.36), label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, CHIP_TEXT[i])
