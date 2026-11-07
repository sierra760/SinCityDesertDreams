// SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
// SPDX-License-Identifier: GPL-3.0-or-later
// See LICENSE and LICENSING.md in the repository root.

// A casino's signature feature lit specially at night, drawn just in front of
// its own geometry: steady, a light chasing round it, rays pulsing outward or
// a slow pulse. Vertex colour carries the feature's colour.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

global uniform float scdd_night;
uniform vec3 center = vec3(0.0);
uniform vec3 axis = vec3(0.0,0.0,1.0);
uniform float radius = 1.0;
// 0 steady, 1 chase, 2 rays, 3 pulse (CasinoNightSignatures.Effect).
uniform int effect = 0;
uniform float strength = 1.0;
uniform float phase = 0.0;

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}

void fragment() {
	vec3 n = normalize(axis);
	vec3 d = wp-center;
	vec3 flat_d = d-n*dot(d,n);
	vec3 u = normalize(abs(n.y) < 0.9 ? cross(n,vec3(0.0,1.0,0.0)) : cross(n,vec3(1.0,0.0,0.0)));
	vec3 v = cross(n,u);
	float angle = atan(dot(flat_d,v),dot(flat_d,u));
	float r = length(flat_d)/max(radius,0.0001);
	float t = TIME+phase;
	float k = 1.0;
	if (effect == 1) {
		float lead = fract(angle/6.2831853*10.0-t*0.7);
		k = 0.45+0.75*smoothstep(0.55,1.0,lead);
	} else if (effect == 2) {
		k = 0.5+0.7*pow(1.0-fract(r*1.6-t*0.45),3.0);
	} else if (effect == 3) {
		k = 0.65+0.35*sin(t*1.8);
	}
	ALBEDO = COLOR.rgb*strength*k*scdd_night;
}
