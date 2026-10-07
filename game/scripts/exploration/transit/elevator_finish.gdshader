// SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
// SPDX-License-Identifier: GPL-3.0-or-later
// See LICENSE and LICENSING.md in the repository root.

// Procedural lift finishes: brushed metal, champagne bronze and walnut veneer.
// Metre-scale detail with derivative filtering; no bitmap texture is sampled.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform int finish = 0; // 0 stainless, 1 champagne, 2 walnut, 3 dark terrazzo
uniform bool door_panel = false;
varying vec2 panel_uv;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float grain(vec2 p) {
	vec2 cell=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(hash(cell),hash(cell+vec2(1,0)),f.x),mix(hash(cell+vec2(0,1)),hash(cell+vec2(1,1)),f.x),f.y);
}
void vertex() { panel_uv=VERTEX.xy*16.0; }
void fragment() {
	vec2 uv=door_panel ? panel_uv : UV;
	float brush=grain(uv*vec2(420.0,2.5))-.5;
	float fade=1.0-clamp(fwidth(uv.x)*180.0,0.0,1.0);
	vec3 base=finish==1 ? vec3(.57,.46,.30) : vec3(.46,.53,.51);
	base*=1.0+brush*.17*fade;
	// Very quiet broad satin bands make the panels legible under station fill.
	if (door_panel) base*=.91+.09*cos(uv.x*180.0)*fade;
	base*=.94+.06*sin(uv.x*7.0+grain(uv*2.0));
	METALLIC=.55; ROUGHNESS=.44+brush*.10*fade; SPECULAR=.45;
	if (finish==2) {
		float wood=grain(vec2(uv.x*24.0+sin(uv.y*2.0)*.24,uv.y*1.7));
		base=mix(vec3(.16,.082,.037),vec3(.31,.18,.079),wood);
		METALLIC=0.0; ROUGHNESS=.58;
	} else if (finish==3) {
		float fleck=grain(uv*130.0);
		base=mix(vec3(.11,.15,.145),vec3(.26,.29,.26),smoothstep(.60,.80,fleck));
		METALLIC=0.0; ROUGHNESS=.62;
	}
	ALBEDO=base;
	EMISSION=base*.32;
}
