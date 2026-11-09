// SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
// SPDX-License-Identifier: GPL-3.0-or-later
// See LICENSE and LICENSING.md in the repository root.

// Steady silver neon on the authored seams. HDR colour feeds the existing
// night bloom; no light nodes, texture reads or per-frame uploads are needed.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

global uniform float scdd_night;

void fragment() {
	ALBEDO = vec3(1.12,1.15,1.20);
	ALPHA = scdd_night;
}
