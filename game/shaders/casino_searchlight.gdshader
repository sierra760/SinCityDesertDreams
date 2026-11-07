// SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
// SPDX-License-Identifier: GPL-3.0-or-later
// See LICENSE and LICENSING.md in the repository root.

// A searchlight beam above a casino at night: a soft additive cone, brightest
// at its core and near the lamp, fading out into the sky.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

global uniform float scdd_night;
uniform vec3 beam_color : source_color = vec3(0.9,0.95,1.0);
uniform float strength = 0.15;
uniform float beam_length = 9.0;
// The narrow end of the cone (local +Y) is the lamp.
varying float lamp_side;

void vertex() {
	lamp_side = clamp(0.5+VERTEX.y/beam_length,0.0,1.0);
}

void fragment() {
	float along = pow(lamp_side,2.2);
	float core = pow(abs(dot(normalize(NORMAL),normalize(VIEW))),3.0);
	ALBEDO = beam_color*along*core*strength*scdd_night;
}
