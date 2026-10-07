// SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
// SPDX-License-Identifier: GPL-3.0-or-later
// See LICENSE and LICENSING.md in the repository root.

// One tile is one world unit. Derivatives keep boundaries soft at any camera
// angle and suppress the pattern before distant cells become a noisy texture.
uniform bool tile_grid_enabled = false;

vec3 tile_grid_color(vec3 base, vec3 position, vec3 normal) {
	vec2 pixel = max(fwidth(position.xz), vec2(0.00001));
	vec2 edge = abs(fract(position.xz + 0.5) - 0.5);
	vec2 lines = 1.0 - smoothstep(vec2(0.006), vec2(0.006) + pixel * 0.85, edge);
	float distant = 1.0 - smoothstep(0.06, 0.26, max(pixel.x, pixel.y));
	// Cliffs and waterfall walls keep their vertical appearance.
	float surface = smoothstep(0.35, 0.55, abs(normal.y));
	float ink = max(lines.x, lines.y) * distant * surface * 0.13;
	return mix(base, vec3(0.23, 0.20, 0.17), ink);
}
