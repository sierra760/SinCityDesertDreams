// SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
// SPDX-License-Identifier: GPL-3.0-or-later
// See LICENSE and LICENSING.md in the repository root.

// Lit casino window panes at night: whole authored panes, drawn just in front
// of the glass and added to it. Vertex colour carries each pane's light.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

global uniform float scdd_night;
uniform float strength = 1.0;

void fragment() {
	ALBEDO = COLOR.rgb*strength*scdd_night;
}
