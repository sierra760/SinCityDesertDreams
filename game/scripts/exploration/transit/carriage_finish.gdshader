// SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
// SPDX-License-Identifier: GPL-3.0-or-later
// See LICENSE and LICENSING.md in the repository root.

// Procedural passenger-cabin finishes for the rider's carriage, projected in
// the model's own metres so the authored primitives need no unwrapping.
// 0 ribbed floor, 1 ivory enamel panel, 2 teal glazed enamel, 3 woven seat,
// 4 brass, 5 brushed stainless, 6 lit diffuser, 7 perforated ceiling,
// 8 walnut, 9 wheel rubber. No bitmap texture is sampled.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform int finish = 1;
uniform vec3 base_color : source_color = vec3(.9,.86,.76);
varying vec3 local_position;
varying vec3 local_normal;

float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float grain(vec2 p) {
	vec2 cell=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(hash(cell),hash(cell+vec2(1,0)),f.x),mix(hash(cell+vec2(0,1)),hash(cell+vec2(1,1)),f.x),f.y);
}

void vertex() {
	local_position = VERTEX;
	local_normal = NORMAL;
}

void fragment() {
	vec3 n = abs(normalize(local_normal));
	// Box projection: the dominant axis of the face picks the metre plane.
	vec2 uv = n.y > max(n.x,n.z) ? local_position.xz : (n.x > n.z ? local_position.zy : local_position.xy);
	// Daylight and the sky fill reach the open cabin, so the finishes are
	// kept a step darker than their authored swatches and glow only a little.
	vec3 base = base_color*.74;
	float fine = grain(uv*60.0)-.5;
	METALLIC = 0.0;
	ROUGHNESS = .72;
	SPECULAR = .4;
	EMISSION = vec3(0.0);
	if (finish==0) {
		// Dark ribbed rubber running the length of the car, with mica flecks.
		float rib = smoothstep(.30,.42,abs(fract(local_position.x*9.0)-.5));
		float fleck = smoothstep(.72,.90,grain(uv*170.0));
		base = mix(base*.80,base*1.12,rib);
		base = mix(base,vec3(.30,.32,.30),fleck*.55);
		ROUGHNESS = .78-rib*.12;
		EMISSION = base*.10;
	} else if (finish==1) {
		// Ivory enamel panels with a faint seam every 0.9 m.
		float seam = smoothstep(.012,.020,abs(fract(uv.x/.9)-.5)*.9);
		base *= (1.0+fine*.04)*mix(.84,1.0,seam);
		ROUGHNESS = .38;
		SPECULAR = .5;
		EMISSION = base*.16;
	} else if (finish==2) {
		base *= 1.0+fine*.03;
		ROUGHNESS = .30;
		SPECULAR = .55;
		EMISSION = base*.14;
	} else if (finish==3) {
		// Woven moquette: two interleaved thread directions and a quiet fleck.
		vec2 thread = uv*140.0;
		float warp = smoothstep(.35,.65,abs(fract(thread.x)-.5));
		float weft = smoothstep(.35,.65,abs(fract(thread.y+.5)-.5));
		float weave = mix(.86,1.08,warp*.5+weft*.5);
		base = mix(base*weave,base*1.35,smoothstep(.80,.96,grain(uv*23.0))*.35);
		ROUGHNESS = .92;
		SPECULAR = .2;
		EMISSION = base*.12;
	} else if (finish==4) {
		float brush = grain(uv*vec2(260.0,3.0))-.5;
		base *= 1.0+brush*.14;
		METALLIC = .75;
		ROUGHNESS = .34+brush*.08;
		SPECULAR = .5;
		EMISSION = base*.10;
	} else if (finish==5) {
		float brush = grain(uv*vec2(3.0,320.0))-.5;
		base *= 1.0+brush*.16;
		METALLIC = .62;
		ROUGHNESS = .40+brush*.10;
		SPECULAR = .5;
		EMISSION = base*.08;
	} else if (finish==6) {
		base = vec3(.98,.93,.80);
		float ribs = .94+.06*cos(uv.x*120.0);
		base *= ribs;
		ROUGHNESS = .5;
		EMISSION = base*1.6;
	} else if (finish==7) {
		// Perforated acoustic panel: a regular field of small dark holes.
		vec2 cell = fract(uv*28.0)-.5;
		float hole = 1.0-smoothstep(.15,.21,length(cell));
		base = mix(base,base*.55,hole);
		ROUGHNESS = .70;
		EMISSION = base*.18;
	} else if (finish==8) {
		float wood = grain(vec2(uv.x*22.0+sin(uv.y*2.2)*.3,uv.y*1.6));
		base = mix(vec3(.16,.082,.037),vec3(.33,.19,.085),wood);
		ROUGHNESS = .55;
		EMISSION = base*.12;
	} else {
		base *= .9+fine*.06;
		ROUGHNESS = .9;
	}
	ALBEDO = base;
}
