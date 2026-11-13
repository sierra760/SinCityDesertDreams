// SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
// SPDX-License-Identifier: GPL-3.0-or-later
// See LICENSE and LICENSING.md in the repository root.

// The film projected on a drive-in screen. Black-and-white picture thrown by a
// warm projector lamp; it fades in and out with night mode.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

global uniform float scdd_night;
uniform sampler2D film : source_color, filter_linear, repeat_disable;
uniform float brightness = 1.15;

void fragment() {
	float picture = dot(texture(film, UV).rgb, vec3(0.299, 0.587, 0.114));
	// A projected picture never reaches true black on a painted screen.
	vec3 lamp = vec3(1.0, 0.95, 0.86);
	ALBEDO = mix(vec3(0.035, 0.034, 0.04), lamp, picture) * brightness;
	// Soft edge so the frame does not look cut out of the screen.
	vec2 edge = min(UV, 1.0 - UV);
	float frame = smoothstep(0.0, 0.012, min(edge.x, edge.y));
	ALPHA = clamp(scdd_night, 0.0, 1.0) * frame;
}
