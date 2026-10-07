// SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
// SPDX-License-Identifier: GPL-3.0-or-later
// See LICENSE and LICENSING.md in the repository root.

// Procedural ballast, timber and brushed steel in metre-scaled UVs.
// Vertex RGB uses the surface railway's sRGB palette; alpha selects the finish.
shader_type spatial;
render_mode unshaded;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
vec3 linear_color(vec3 c) { return mix(c/12.92,pow((c+.055)/1.055,vec3(2.4)),step(vec3(.04045),c)); }
void fragment() {
	vec3 base=COLOR.rgb;
	float finish=COLOR.a;
	if (finish<.15) {
		// Irregular, small crushed stone; derivative fade prevents distant fizz.
		vec2 stone=UV*26.0;
		vec2 cell=floor(stone), f=fract(stone);
		float nearest=8.0, second=8.0, variation=.5;
		for (int y=-1;y<=1;y++) {
			for (int x=-1;x<=1;x++) {
				vec2 offset=vec2(float(x),float(y));
				vec2 seed=cell+offset;
				vec2 center=.15+.70*vec2(hash(seed),hash(seed+vec2(63.7,21.9)));
				float d=length(offset+center-f);
				if(d<nearest) { second=nearest; nearest=d; variation=hash(seed+vec2(7.1,9.2)); }
				else { second=min(second,d); }
			}
		}
		float seam=smoothstep(.015,.11,second-nearest);
		float detail=mix(.77,1.16,variation)*mix(.62,1.0,seam);
		float fade=clamp(1.0-max(fwidth(stone.x),fwidth(stone.y))*.7,0.0,1.0);
		base*=mix(.92,detail,fade);
	} else if (finish<.45) {
		float grain=hash(floor(UV*vec2(3.0,170.0)));
		base*=.86+grain*.23;
	} else if (finish<.75) {
		base*=.97+hash(floor(UV*vec2(240.0,2.0)))*.06;
	} else {
		base*=.94+hash(floor(UV*80.0))*.10;
	}
	ALBEDO=OUTPUT_IS_SRGB ? base : linear_color(base);
}
