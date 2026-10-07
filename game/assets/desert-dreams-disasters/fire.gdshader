// SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
// SPDX-License-Identifier: GPL-3.0-or-later
// See LICENSE and LICENSING.md in the repository root.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Blender's Mottle vertex colors retain the six authored surface palettes.
// Export UV2 carries emission strength and roughness, so the whole animated
// fire draws as one surface while smoke remains matte and non-emissive.
uniform vec3 core_emission = vec3(1.0, 0.90, 0.51);
uniform vec3 amber_emission = vec3(1.0, 0.53, 0.08);
uniform vec3 orange_emission = vec3(0.98, 0.23, 0.035);
uniform vec3 coal_emission = vec3(0.58, 0.075, 0.016);

// Atlas rows contain all sampled Blender frames, including the closing frame.
uniform sampler2D motion_positions : filter_nearest, repeat_disable;
uniform sampler2D motion_normals : filter_nearest, repeat_disable;
uniform float playback_seconds = 0.0;
uniform float rows_per_frame = 5.0;
uniform float atlas_height = 2405.0;
uniform float playback_fps = 60.0;
uniform bool atlas_flip_v = false;

void vertex() {
	float frame = mod(playback_seconds, 8.0) * playback_fps;
	float current = floor(frame);
	float weight = fract(frame);
	vec2 at0 = vec2(UV.x, (UV.y + rows_per_frame * current + 0.5) / atlas_height);
	vec2 at1 = vec2(UV.x, (UV.y + rows_per_frame * (current + 1.0) + 0.5) / atlas_height);
	if (atlas_flip_v) {
		at0.y = 1.0 - at0.y;
		at1.y = 1.0 - at1.y;
	}
	VERTEX = mix(textureLod(motion_positions, at0, 0.0).xyz,
		textureLod(motion_positions, at1, 0.0).xyz, weight);
	vec3 first_normal = textureLod(motion_normals, at0, 0.0).xyz;
	vec3 interpolated = mix(first_normal, textureLod(motion_normals, at1, 0.0).xyz, weight);
	NORMAL = length(interpolated) > 0.0001 ? normalize(interpolated) : normalize(first_normal);
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = clamp(1.0 - UV2.y, 0.0, 1.0);
	METALLIC = 0.0;
	float glow = UV2.x;
	vec3 glow_color = vec3(0.0);
	if (glow > 0.9) {
		glow_color = core_emission;
	} else if (glow > 0.45) {
		glow_color = amber_emission;
	} else if (glow > 0.225) {
		glow_color = orange_emission;
	} else if (glow > 0.0) {
		glow_color = coal_emission;
	}
	EMISSION = glow_color * glow;
}
