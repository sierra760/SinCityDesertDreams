// SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
// SPDX-License-Identifier: GPL-3.0-or-later
// See LICENSE and LICENSING.md in the repository root.

// The authored crowd gait, driven exclusively by this Explore session.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 tint : source_color = vec4(1.0);
uniform float phase = 0.0;
uniform float movement = 0.0;
void vertex() {
    float moving = clamp(movement, 0.0, 1.0);
    float cycle = sin(phase * 6.2831853);
    float side = sign(VERTEX.x);
    float leg = 1.0 - smoothstep(0.038, 0.058, VERTEX.y);
    float arm = smoothstep(0.016, 0.024, abs(VERTEX.x)) * smoothstep(0.041, 0.063, VERTEX.y) * (1.0 - smoothstep(0.079, 0.095, VERTEX.y));
    VERTEX.z += cycle * side * moving * (leg * 0.011 - arm * 0.006);
    VERTEX.y += max(0.0, cycle * side) * leg * moving * 0.003;
}
void fragment() {
    ALBEDO = tint.rgb;
    ROUGHNESS = 0.72;
}
