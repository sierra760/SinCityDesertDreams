// SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
// SPDX-License-Identifier: GPL-3.0-or-later
// See LICENSE and LICENSING.md in the repository root.

// Casino neon at night: thin tubes along rooflines and corners, and chasing
// marquee bulbs along entrance canopies. UV.x is distance along the run (tile
// units), UV.y is 1 for bulbs; vertex colour carries the neon colour.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

global uniform float scdd_night;
// 3 chase, 4 pulse (CasinoNightSignatures.Style); others glow steadily.
uniform int style = 0;
uniform float phase = 0.0;
uniform float strength = 1.0;

void fragment() {
	float s = UV.x;
	float t = TIME+phase;
	float k = 1.0;
	if (UV.y > 0.5) {
		// Separate bulbs about half a metre apart; every third one runs ahead.
		float slot = s*32.0;
		float gap = smoothstep(0.18,0.28,abs(fract(slot)-0.5));
		float lead = step(fract(floor(slot)/3.0-t*1.4),0.34);
		k = (0.35+1.1*lead)*(1.0-gap);
	} else if (style == 3) {
		k = 0.5+0.7*smoothstep(0.65,1.0,fract(s*1.4-t*0.55));
	} else if (style == 4) {
		k = 0.65+0.35*sin(t*1.6);
	}
	ALBEDO = COLOR.rgb*k*strength*scdd_night;
}
