// SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
// SPDX-License-Identifier: GPL-3.0-or-later
// See LICENSE and LICENSING.md in the repository root.

// Each authored cell has one constant height. Ascending horizontal bands
// alternation runs at the vertices; fragments only output the flat cell colour.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

global uniform float scdd_night;
uniform vec4 palette_a : source_color = vec4(0.27,0.49,0.61,1.0);
uniform vec4 palette_b : source_color = vec4(0.62,0.74,0.81,1.0);
uniform vec4 palette_c : source_color = vec4(0.90,0.92,0.92,1.0);
uniform float phase_offset = 0.0;
uniform bool explore_steps = false;
varying flat vec3 cell_colour;

void vertex() {
	if (explore_steps) {
		// Actual cell levels, not a continuous sweep: one level per second.
		// Three levels form each colour band. This runs only at vertices.
		float row = floor(COLOR.g*255.0+0.5);
		float band = mod(floor((row-floor(TIME+phase_offset))/3.0),3.0);
		cell_colour = (band < 0.5 ? palette_a.rgb : (band < 1.5 ? palette_b.rgb : palette_c.rgb))*1.15;
	} else {
		// Two regular ribbons of A/B/C span the dome. Increasing shader time
		// moves the bands upward; all cells at one height change together.
		float phase = fract((1.0-COLOR.r)*2.0+(TIME+phase_offset)/48.0)*3.0;
		float dissolve = smoothstep(0.78,1.0,fract(phase));
		vec3 first = palette_a.rgb;
		vec3 next = palette_b.rgb;
		if (phase >= 2.0) {
			first = palette_c.rgb;
			next = palette_a.rgb;
		} else if (phase >= 1.0) {
			first = palette_b.rgb;
			next = palette_c.rgb;
		}
		cell_colour = mix(first,next,dissolve)*1.15;
	}
}

void fragment() {
	ALBEDO = cell_colour;
	ALPHA = scdd_night;
}
