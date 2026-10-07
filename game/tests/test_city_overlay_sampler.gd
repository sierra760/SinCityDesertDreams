# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

extends "res://tests/test_case.gd"

## Fixed authored outputs at 0, 1, 124, 128, 132, 255; intentionally independent
## of rendering owners and production sampler constants/formulas.
const AUTHORED_COLORS := {
	&"zones": [Color.TRANSPARENT, Color(0.45, 0.85, 0.45, 0.44), Color(0.7, 0.7, 0.7, 0.44), Color(0.7, 0.7, 0.7, 0.44), Color(0.7, 0.7, 0.7, 0.44), Color(0.7, 0.7, 0.7, 0.44)],
	&"power": [Color.TRANSPARENT, Color(0.9, 0.2, 0.15, 0.55), Color(0.9, 0.2, 0.15, 0.55), Color(0.9, 0.2, 0.15, 0.55), Color(0.9, 0.2, 0.15, 0.55), Color(0.95, 0.85, 0.2, 0.55)],
	&"water": [Color.TRANSPARENT, Color(0.9, 0.3, 0.2, 0.55), Color(0.9, 0.3, 0.2, 0.55), Color(0.9, 0.3, 0.2, 0.55), Color(0.9, 0.3, 0.2, 0.55), Color(0.25, 0.55, 0.95, 0.55)],
	&"crime": [Color.TRANSPARENT, Color(0.949607843137, 0.348823529412, 0.149607843137, 0.0344423360097), Color(0.90137254902, 0.204117647059, 0.10137254902, 0.383533622015), Color(0.899803921569, 0.199411764706, 0.0998039215686, 0.389670549638), Color(0.898235294118, 0.194705882353, 0.0982352941176, 0.395712313801), Color(0.85, 0.05, 0.05, 0.55)],
	&"pollution": [Color.TRANSPARENT, Color(0.898235294118, 0.598705882353, 0.199490196078, 0.0344423360097), Color(0.681176470588, 0.439529411765, 0.136784313725, 0.383533622015), Color(0.674117647059, 0.434352941176, 0.134745098039, 0.389670549638), Color(0.667058823529, 0.429176470588, 0.132705882353, 0.395712313801), Color(0.45, 0.27, 0.07, 0.55)],
	&"land_value": [Color.TRANSPARENT, Color(0.947058823529, 0.77968627451, 0.100392156863, 0.0344423360097), Color(0.585294117647, 0.741098039216, 0.14862745098, 0.383533622015), Color(0.573529411765, 0.739843137255, 0.150196078431, 0.389670549638), Color(0.561764705882, 0.738588235294, 0.151764705882, 0.395712313801), Color(0.2, 0.7, 0.2, 0.55)],
	&"traffic": [Color.TRANSPARENT, Color(0.202745098039, 0.747529411765, 0.199411764706, 0.0344423360097), Color(0.540392156863, 0.443647058824, 0.127058823529, 0.383533622015), Color(0.55137254902, 0.433764705882, 0.124705882353, 0.389670549638), Color(0.562352941176, 0.423882352941, 0.122352941176, 0.395712313801), Color(0.9, 0.12, 0.05, 0.55)],
	&"police": [Color.TRANSPARENT, Color(0.448549019608, 0.598431372549, 0.949607843137, 0.0344423360097), Color(0.270078431373, 0.405490196078, 0.90137254902, 0.383533622015), Color(0.264274509804, 0.399215686275, 0.899803921569, 0.389670549638), Color(0.258470588235, 0.392941176471, 0.898235294118, 0.395712313801), Color(0.08, 0.2, 0.85, 0.55)],
	&"fire": [Color.TRANSPARENT, Color(0.949803921569, 0.718941176471, 0.348823529412, 0.0344423360097), Color(0.92568627451, 0.588705882353, 0.204117647059, 0.383533622015), Color(0.924901960784, 0.584470588235, 0.199411764706, 0.389670549638), Color(0.924117647059, 0.580235294118, 0.194705882353, 0.395712313801), Color(0.9, 0.45, 0.05, 0.55)],
	&"density": [Color.TRANSPARENT, Color(0.749019607843, 0.498431372549, 0.899215686275, 0.0344423360097), Color(0.628431372549, 0.305490196078, 0.802745098039, 0.383533622015), Color(0.624509803922, 0.299215686275, 0.799607843137, 0.389670549638), Color(0.620588235294, 0.292941176471, 0.796470588235, 0.395712313801), Color(0.5, 0.1, 0.7, 0.55)],
	&"growth": [Color(0.9, 0.1, 0.1, 0.55), Color(0.9, 0.1, 0.1, 0.55), Color(0.9, 0.1, 0.1, 0.0976092160358), Color.TRANSPARENT, Color(0.1, 0.85, 0.85, 0.0976092160358), Color(0.1, 0.85, 0.85, 0.55)],
}

var sampler

func before_all() -> void:
	var path := "res://scripts/view/city_overlay_sampler.gd"
	if ResourceLoader.exists(path): sampler = load(path)

func test_shared_sampler_exists() -> void:
	check(sampler != null, "canonical 3D sampler must exist")

func test_all_resolutions_canonical_coordinates_and_rotation_independence() -> void:
	if sampler == null: return
	var city := flat_city()
	var layers := [&"zones", &"power", &"water", &"crime", &"pollution", &"land_value", &"traffic", &"police", &"fire", &"density", &"growth"]
	check_eq(sampler.LAYERS, layers)
	var grids := [city.crime, city.pollution, city.land_value, city.traffic, city.police, city.fire_cover, city.density, city.growth]
	for i in grids.size():
		var kind: StringName = layers[i + 3]
		var block := 2 if i < 4 else 4
		check_eq(sampler.tiles_per_cell(kind), block)
		grids[i].put(3, 5, 171 + i)
		for rotation in 4:
			city.rotation = rotation
			check_eq(sampler.value_at(city, kind, Vector2i(3 * block + block - 1, 5 * block + block - 1)), 171 + i)
	for kind in [&"zones", &"power", &"water"]: check_eq(sampler.tiles_per_cell(kind), 1)
	check_eq(sampler.tiles_per_cell(&"bogus"), 0)
	check_eq(sampler.value_at(city, &"crime", Vector2i(-1, 2)), 0)
	check_eq(sampler.value_at(null, &"power", Vector2i.ZERO), 0)

func test_service_encoding_growth_dead_band_and_authored_ramps() -> void:
	if sampler == null: return
	var city := flat_city()
	var tile := Vector2i(6, 7)
	check_eq(sampler.value_at(city, &"power", tile), 0)
	city.flags.putv(tile, TileFlags.CONDUCTS_POWER | TileFlags.CONDUCTS_WATER)
	check_eq(sampler.value_at(city, &"power", tile), 128)
	check_eq(sampler.value_at(city, &"water", tile), 128)
	city.flags.putv(tile, 0xf0)
	check_eq(sampler.value_at(city, &"power", tile), 255)
	check_eq(sampler.value_at(city, &"water", tile), 255)
	for value in range(125, 132): check_eq(sampler.cell_color(&"growth", value), Color.TRANSPARENT)
	check_gt(sampler.cell_color(&"growth", 124).a, 0.0)
	check_gt(sampler.cell_color(&"growth", 132).a, 0.0)
	var values := [0, 1, 124, 128, 132, 255]
	for kind in sampler.LAYERS:
		for i in values.size():
			var actual: Color = sampler.cell_color(kind, values[i])
			var expected: Color = AUTHORED_COLORS[kind][i]
			# Literal decimals are rounded once into Color's 32-bit components.
			# The 1e-6 bound permits only floating point arithmetic rounding.
			if kind in [&"zones", &"power", &"water"] or expected == Color.TRANSPARENT:
				check_eq(actual, expected, "%s value %d" % [kind, values[i]])
			else:
				for component in 4:
					check(absf(actual[component] - expected[component]) < 0.000001, "%s value %d component %d" % [kind, values[i], component])
	var zones := {
		Zones.RES_LOW: Color(0.45, 0.85, 0.45, 0.44),
		Zones.RES_HIGH: Color(0.20, 0.60, 0.25, 0.44),
		Zones.COM_LOW: Color(0.45, 0.60, 0.95, 0.44),
		Zones.COM_HIGH: Color(0.20, 0.35, 0.80, 0.44),
		Zones.IND_LOW: Color(0.95, 0.85, 0.35, 0.44),
		Zones.IND_HIGH: Color(0.75, 0.62, 0.15, 0.44),
		Zones.MILITARY: Color(0.55, 0.60, 0.45, 0.44),
		Zones.AIRPORT: Color(0.75, 0.75, 0.80, 0.44),
		Zones.SEAPORT: Color(0.45, 0.70, 0.75, 0.44),
	}
	for kind: int in zones: check_eq(sampler.cell_color(&"zones", kind), zones[kind])
	check_eq(sampler.cell_color(&"bogus", 255), Color.TRANSPARENT)
	check_eq(sampler.legend_entries(&"bogus"), [])
	check_eq(sampler.legend_entries(&"none"), sampler.legend_entries(&""))
	for kind in sampler.LAYERS: check_gt(sampler.legend_entries(kind).size(), 0)
