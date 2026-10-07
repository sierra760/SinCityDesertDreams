// SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
// SPDX-License-Identifier: GPL-3.0-or-later
// See LICENSE and LICENSING.md in the repository root.

// Shared, metre-scaled station finishes. Alpha selects a finish; it is never
// output as transparency. Terrazzo is the only finish that samples a bitmap.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D terrazzo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float grain(vec2 p) {
	vec2 cell=floor(p), f=fract(p);
	f=f*f*(3.0-2.0*f);
	return mix(mix(hash(cell),hash(cell+vec2(1,0)),f.x),mix(hash(cell+vec2(0,1)),hash(cell+vec2(1,1)),f.x),f.y);
}
void fragment() {
	vec3 base=COLOR.rgb;
	float finish=COLOR.a;
	float texture_grain=grain(UV*48.0)-0.5;
	METALLIC=0.0;
	SPECULAR=0.35;
	ROUGHNESS=0.72;
	if (finish<0.1) {
		// Small, quiet aggregate rather than oversized repeated chips.
		base=texture(terrazzo,UV*1.6).rgb;
		base=mix(base,vec3(.67,.60,.49),.30);
		ROUGHNESS=.66+texture_grain*.08;
		EMISSION=base*.18;
	} else if (finish<0.3) {
		// Ivory walls and cooler, darker soffits retain separation in flat fill.
		base*=1.0+texture_grain*.035+(grain(UV*2.4)-.5)*.02;
		ROUGHNESS=finish>.24 ? .90 : .82;
		EMISSION=base*(finish>.24 ? .18 : .24);
	} else if (finish<0.5) {
		// Staggered glazed ceramic with narrow, antialiased recessed grout.
		vec2 tile=UV/vec2(.32,.16);
		tile.x+=mod(floor(tile.y),2.0)*.5;
		vec2 edge=min(fract(tile),1.0-fract(tile));
		vec2 aa=max(fwidth(tile),vec2(.001));
		float glaze=smoothstep(.007,.007+aa.x,edge.x)*smoothstep(.012,.012+aa.y,edge.y);
		base*=.97+(hash(floor(tile))-.5)*.065+texture_grain*.018;
		base=mix(vec3(.095,.145,.132),base,glaze);
		ROUGHNESS=mix(.86,.36,glaze);
		SPECULAR=.45;
		EMISSION=base*.22;
	} else if (finish<0.55) {
		// Smooth painted enamel for furniture and fittings.
		base*=1.0+texture_grain*.025;
		ROUGHNESS=.40;
		SPECULAR=.50;
		EMISSION=base*.20;
	} else if (finish<0.7) {
		base*=.98+texture_grain*.04;
		METALLIC=.62;
		ROUGHNESS=.46;
		SPECULAR=.5;
		EMISSION=base*.10;
	} else {
		base=vec3(.94,.84,.65);
		EMISSION=base*.8;
		ROUGHNESS=.65;
	}
	ALBEDO=base;
}
