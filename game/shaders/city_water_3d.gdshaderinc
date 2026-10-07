// SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
// SPDX-License-Identifier: GPL-3.0-or-later
// See LICENSE and LICENSING.md in the repository root.

// World-space water detail; the authored surface and query triangles stay fixed.
uniform bool water_style_enabled = false;
uniform sampler2D water_geometry : filter_nearest, repeat_disable;
// The same data texture has separate sampling contracts: exact bank masks and
// smoothly interpolated seabed heights. Depth cannot inherit tile boundaries.
uniform sampler2D water_depth : filter_linear, repeat_disable;
uniform float water_time = 0.0;
uniform int water_quality = 0;

float water_box_distance(vec2 p, vec2 low, vec2 high) {
	return length(max(max(low-p,p-high),vec2(0.0)));
}

// These are the same 0.18-wide bank shelves and 0.20 corner shelves the mesh
// displays. Adjacent open-water cells never introduce a foam line.
float water_shelf_distance(vec2 p, vec2 cell, int mask) {
	vec2 q = p-cell;
	float d = 3.0;
	if ((mask & 9) == 9) d = min(d,water_box_distance(q,vec2(0.0),vec2(1.0,0.18)));
	if ((mask & 3) == 3) d = min(d,water_box_distance(q,vec2(0.82,0.0),vec2(1.0)));
	if ((mask & 6) == 6) d = min(d,water_box_distance(q,vec2(0.0,0.82),vec2(1.0)));
	if ((mask & 12) == 12) d = min(d,water_box_distance(q,vec2(0.0),vec2(0.18,1.0)));
	if ((mask & 8) != 0) d = min(d,water_box_distance(q,vec2(0.0),vec2(0.2)));
	if ((mask & 1) != 0) d = min(d,water_box_distance(q,vec2(0.8,0.0),vec2(1.0,0.2)));
	if ((mask & 2) != 0) d = min(d,water_box_distance(q,vec2(0.8),vec2(1.0)));
	if ((mask & 4) != 0) d = min(d,water_box_distance(q,vec2(0.0,0.8),vec2(0.2,1.0)));
	return d;
}

vec2 water_bank_distances(vec2 p, float level) {
	vec2 cell = floor(p);
	float shore = 3.0;
	float impact = 3.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = cell+vec2(float(x),float(y));
			// The map boundary is open water, never an invented shoreline.
			if (any(lessThan(neighbor,vec2(0.0))) || any(greaterThanEqual(neighbor,vec2(128.0)))) continue;
			vec4 data = texture(water_geometry,(neighbor+0.5)/128.0);
			if (data.r < 0.0) {
				shore = min(shore,water_box_distance(p,neighbor,neighbor+1.0));
			} else if (abs(data.r-level) < 0.04) {
				shore = min(shore,water_shelf_distance(p,neighbor,int(data.b+0.5)));
			} else if (data.r > level+0.04 && data.a < data.r-0.04) {
				impact = min(impact,water_box_distance(p,neighbor,neighbor+1.0));
			}
		}
	}
	return vec2(shore,impact);
}

// x/y are slopes, z is the broad color ripple. Fine waves fade before aliasing.
vec3 water_ripples(vec2 p, float footprint) {
	float a = dot(p,vec2(0.82,0.47))+water_time*0.42;
	float b = dot(p,vec2(-2.6,3.4))-water_time*0.76;
	float c = dot(p,vec2(12.7,9.3))+water_time*1.65;
	float fine = (water_quality == 2 ? 0.0 : 1.0) * (1.0-smoothstep(0.035,0.12,footprint));
	vec2 slope = vec2(0.82,0.47)*cos(a)*0.055 + vec2(-2.6,3.4)*cos(b)*0.016;
	slope += vec2(12.7,9.3)*cos(c)*0.0025*fine;
	return vec3(slope,sin(a)*0.014+sin(b)*0.009+sin(c)*0.003*fine);
}

vec3 water_linear(vec3 color) {
	return OUTPUT_IS_SRGB ? color : mix(pow((color+vec3(0.055))/1.055,vec3(2.4)),color/12.92,lessThanEqual(color,vec3(0.04045)));
}
