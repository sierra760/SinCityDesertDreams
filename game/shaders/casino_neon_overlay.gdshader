// SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
// SPDX-License-Identifier: GPL-3.0-or-later
// See LICENSE and LICENSING.md in the repository root.

// Night-only neon drawn over a casino's own surfaces (material_overlay), so it
// follows the real building: an uplight wash from the street, a chasing
// marquee of bulbs, the resort's neon pattern and a glowing crown.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

global uniform float scdd_night;
uniform vec3 neon_a : source_color = vec3(1.0,0.25,0.65);
uniform vec3 neon_b : source_color = vec3(0.25,0.95,1.0);
uniform float base_y = 0.0;
uniform float top_y = 1.0;
// 0 bands, 1 fins, 2 grid, 3 rising chase, 4 pulse (CasinoNightSignatures.Style).
uniform int style = 0;
uniform float phase = 0.0;

varying vec3 wp;
varying vec3 wn;

void vertex() {
	wp = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	wn = normalize((MODEL_MATRIX*vec4(NORMAL,0.0)).xyz);
}

// A tube of half-width w (in units of x) around x = 0, antialiased.
float tube(float x, float w) {
	float aa = max(fwidth(x),0.0001)*1.2;
	return 1.0-smoothstep(w,w+aa,abs(x));
}

void fragment() {
	float height = wp.y-base_y;
	float span = max(top_y-base_y,0.05);
	float h = clamp(height/span,0.0,1.0);
	float wall = 1.0-smoothstep(0.35,0.75,abs(wn.y));
	float roof = smoothstep(0.75,0.95,wn.y);
	float t = TIME+phase;
	// Distance along the facade, whichever way the wall faces.
	float s = abs(wn.x) > abs(wn.z) ? wp.z : wp.x;
	vec3 c = vec3(0.0);
	// Colour washes up the walls from street lights at the base.
	c += neon_a*wall*exp(-max(height,0.0)*7.0)*0.22;
	// Upper roofs glow like a crown, strongest on the highest parts.
	c += neon_b*roof*smoothstep(0.45,1.0,h)*0.15;
	// Marquee: chasing bulbs just above the entrances.
	float bulbs = step(0.5,fract(s*30.0-t*2.4));
	c += mix(neon_b,vec3(1.0,0.95,0.8),0.45)*wall*tube(height-0.08,0.010)*(0.25+0.95*bulbs);
	float above = smoothstep(0.10,0.14,height);
	// Neon is an accent: a few lines, not every storey or bay.
	float crown = tube(height-span*0.96,0.012);
	if (style == 0 || style == 2) {
		float bands = max(max(tube(height-span*0.35,0.010),tube(height-span*0.68,0.010)),crown);
		c += neon_a*wall*above*bands*0.9;
	}
	if (style == 1) {
		float fins = tube(fract(s*1.6+0.5)-0.5,0.02)*smoothstep(0.18,0.3,h);
		c += neon_b*wall*above*max(fins,crown)*0.85;
	}
	if (style == 2) {
		c += neon_b*wall*above*tube(fract(s*1.2+0.5)-0.5,0.015)*smoothstep(0.3,0.45,h)*0.7;
	}
	if (style == 3) {
		float rise = fract(t*0.12);
		float chase = max(tube(height-span*rise,0.012),tube(height-span*fract(rise+0.5),0.012));
		c += mix(neon_a,neon_b,step(0.5,rise))*wall*above*chase*1.0;
		c += neon_b*wall*crown*0.8;
	}
	if (style == 4) {
		float breathe = 0.5+0.5*sin(t*1.6);
		c += mix(neon_a,neon_b,breathe)*wall*above*smoothstep(0.6,1.0,h)*(0.03+0.04*breathe);
		c += neon_b*wall*crown*(0.5+0.4*breathe);
	}
	ALBEDO = c*scdd_night;
}
