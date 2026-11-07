# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Shader globals for night mode. Presentation only: no city data or RNG.
## Shaders that read them compile only after ensure() has registered them, so
## the shared surface factory calls it before building its shader.
extends RefCounted

const NIGHT := &"scdd_night"
## 128×128 float texels, one per tile: lens x/z within the tile, lens height,
## and pool strength (0 = no lamp over this tile).
const LAMPS := &"scdd_night_lamps"
## 128×128 colour per tile: casino neon spilling onto the ground around it.
const WASH := &"scdd_night_wash"

static var _registered := false
static var _empty: ImageTexture
static var _no_wash: ImageTexture

static func ensure() -> void:
	if _registered: return
	_registered = true
	# Registered once per process. (Listing existing globals is editor-only.)
	RenderingServer.global_shader_parameter_add(NIGHT,RenderingServer.GLOBAL_VAR_TYPE_FLOAT,0.0)
	RenderingServer.global_shader_parameter_add(LAMPS,RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D,empty_lamps())
	RenderingServer.global_shader_parameter_add(WASH,RenderingServer.GLOBAL_VAR_TYPE_SAMPLER2D,empty_wash())

## A lamp table with no lamps, so pools are dark until a city places some.
static func empty_lamps() -> ImageTexture:
	if _empty == null:
		_empty = ImageTexture.create_from_image(Image.create(City.WIDTH,City.HEIGHT,false,Image.FORMAT_RGBAF))
	return _empty

## No casino wash anywhere.
static func empty_wash() -> ImageTexture:
	if _no_wash == null:
		_no_wash = ImageTexture.create_from_image(Image.create(City.WIDTH,City.HEIGHT,false,Image.FORMAT_RGBA8))
	return _no_wash

static func set_wash(texture: Texture2D) -> void:
	ensure()
	RenderingServer.global_shader_parameter_set(WASH,texture if texture != null else empty_wash())

static func set_night(amount: float) -> void:
	ensure()
	RenderingServer.global_shader_parameter_set(NIGHT,clampf(amount,0.0,1.0))

static func set_lamps(texture: Texture2D) -> void:
	ensure()
	RenderingServer.global_shader_parameter_set(LAMPS,texture if texture != null else empty_lamps())
