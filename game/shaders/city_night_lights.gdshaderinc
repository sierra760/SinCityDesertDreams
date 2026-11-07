// SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
// SPDX-License-Identifier: GPL-3.0-or-later
// See LICENSE and LICENSING.md in the repository root.

// Night mode presentation. scdd_night is 0 by day, so these terms vanish and
// the daytime image is unchanged. Registered by city_night_globals.gd.
global uniform float scdd_night;
// One texel per tile: lens x/z within the tile, lens height, pool strength.
global uniform sampler2D scdd_night_lamps : filter_nearest, repeat_disable;
// One colour per tile (alpha = strength): casino neon spilling onto the ground.
global uniform sampler2D scdd_night_wash : filter_linear, repeat_disable;

const vec3 NIGHT_SKY_REFLECTION = vec3(0.025,0.035,0.075);
// Warm sodium-tungsten light, the colour of an old Las Vegas boulevard.
const vec3 NIGHT_LAMP_COLOR = vec3(1.0,0.74,0.46);

// Light from the street lamps on the nine tiles around p. A pool is brightest
// straight beneath its lens and widens a little on surfaces far below it;
// surfaces above a lens (an overpass deck) or far beneath it stay dark.
vec3 night_lamp_pools(vec3 p) {
	vec2 cell = floor(p.xz);
	float light = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 n = cell+vec2(float(x),float(y));
			if (any(lessThan(n,vec2(0.0))) || any(greaterThanEqual(n,vec2(128.0)))) continue;
			vec4 lamp = texelFetch(scdd_night_lamps,ivec2(n),0);
			if (lamp.a <= 0.0) continue;
			vec3 lens = vec3(n.x+lamp.r,lamp.b,n.y+lamp.g);
			float drop = lens.y-p.y;
			if (drop < -0.02 || drop > 1.1) continue;
			float reach = 0.48+drop*0.30;
			float fall = 1.0-smoothstep(0.0,reach,length(lens.xz-p.xz));
			light += lamp.a*fall*fall;
		}
	}
	return NIGHT_LAMP_COLOR*min(light*1.5,2.2);
}

// Casino colour on the ground, smoothly filtered between tile centres.
vec3 night_casino_wash(vec3 p) {
	vec4 wash = texture(scdd_night_wash,p.xz/128.0);
	return wash.rgb*wash.a;
}
