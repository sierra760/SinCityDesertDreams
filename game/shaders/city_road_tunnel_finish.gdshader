// SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
// SPDX-License-Identifier: GPL-3.0-or-later
// See LICENSE and LICENSING.md in the repository root.

// Procedural cast-concrete finish. World projection joins cell/chunk boundaries;
// one city unit is 16 metres, matching the Explore actor scale.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;

varying vec3 map_position;
varying vec3 map_normal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float grain(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(cell), hash(cell + vec2(1.0, 0.0)), f.x),
		mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0)), f.x), f.y);
}

void vertex() {
	map_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	map_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 normal = abs(map_normal);
	bool ceiling = normal.y > 0.7;
	vec2 metres = (ceiling ? map_position.xz :
		(normal.x > normal.z ? map_position.zy : map_position.xy)) * 16.0;
	// Grain and small pores fade to their average before they alias at distance.
	float fine_fade = 1.0 - smoothstep(0.3, 1.1, length(fwidth(metres * 42.0)));
	float grit_fade = 1.0 - smoothstep(0.4, 1.4, length(fwidth(metres * 12.0)));
	float fine = (grain(metres * 42.0) - 0.5) * fine_fade;
	float grit = (grain(metres * 12.0) - 0.5) * grit_fade;
	float mottle = grain(metres * 0.65) - 0.5;
	vec2 pore_cell = floor(metres * 24.0);
	vec2 pore_center = 0.2 + 0.6 * vec2(hash(pore_cell), hash(pore_cell + vec2(19.3, 7.1)));
	float pore_distance = length(fract(metres * 24.0) - pore_center);
	float pore_aa = max(length(fwidth(metres * 24.0)), 0.01);
	float pores = (1.0 - smoothstep(0.055, 0.055 + pore_aa, pore_distance))
		* step(0.65, hash(pore_cell + vec2(5.2, 13.7))) * grit_fade;
	// Quiet formwork joints give the broad surfaces a readable concrete scale.
	vec2 panel_size = ceiling ? vec2(3.6, 2.4) : vec2(3.6, 1.2);
	vec2 panel = metres / panel_size;
	vec2 edge = min(fract(panel), 1.0 - fract(panel)) * panel_size;
	vec2 aa = max(fwidth(metres), vec2(0.001));
	vec2 panel_interior = smoothstep(vec2(0.012), vec2(0.012) + aa, edge);
	float joint = 1.0 - panel_interior.x * panel_interior.y;
	float panel_tone = hash(floor(panel)) - 0.5;
	float variation = 1.0 + mottle * 0.10 + grit * 0.16 + fine * 0.12
		+ panel_tone * 0.025 - pores * 0.16;
	vec3 base = COLOR.rgb * variation * (1.0 - joint * 0.13);
	base = clamp(base, vec3(0.0), vec3(1.0));
	// Procedural RGB is authored in sRGB; keep both renderers on that palette.
	ALBEDO = OUTPUT_IS_SRGB ? base : mix(pow((base + vec3(0.055)) / 1.055, vec3(2.4)),
		base / 12.92, lessThanEqual(base, vec3(0.04045)));
	ROUGHNESS = clamp(0.94 + grit * 0.06, 0.86, 1.0);
}
