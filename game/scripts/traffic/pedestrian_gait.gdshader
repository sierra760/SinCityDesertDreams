// SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
// SPDX-License-Identifier: GPL-3.0-or-later
// See LICENSE and LICENSING.md in the repository root.

shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 tint : source_color = vec4(1.0);
uniform float wave_skin = 0.0;
uniform float wave_elbow = 0.083;
// INSTANCE_CUSTOM.x: gait cycles; y: movement; z: owner wave progress; w: wave active.
// Catalog vertices are in tile units. This keeps batches node/physics free.
void vertex() {
    float moving = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
    float cycle = sin(INSTANCE_CUSTOM.x * 6.2831853);
    float side = sign(VERTEX.x);
    float leg = 1.0 - smoothstep(0.038, 0.058, VERTEX.y);
    float arm = smoothstep(0.016, 0.024, abs(VERTEX.x)) * smoothstep(0.041, 0.063, VERTEX.y) * (1.0 - smoothstep(0.079, 0.095, VERTEX.y));
    VERTEX.z += cycle * side * moving * (leg * 0.011 - arm * 0.006);
    VERTEX.y += max(0.0, cycle * side) * leg * moving * 0.003;
    if (INSTANCE_CUSTOM.w > 0.0 && wave_skin > 0.0) {
        // A stationary right arm greeting, driven by the same finite owner action
        // as the near rig. No shader TIME and exactly zero deformation when idle.
        float t = clamp(INSTANCE_CUSTOM.z, 0.0, 1.0);
        float envelope = smoothstep(0.0, 0.25, t) * (1.0 - smoothstep(0.75, 1.0, t));
        float right_arm = step(0.009, VERTEX.x) * wave_skin;
        float angle = envelope * (1.9 + 0.12 * sin(t * 18.849556));
        vec2 pivot = vec2(wave_elbow, 0.0);
        vec2 arm_local = VERTEX.yz - pivot;
        vec2 raised = vec2(arm_local.x * cos(angle) - arm_local.y * sin(angle), arm_local.x * sin(angle) + arm_local.y * cos(angle)) + pivot;
        VERTEX.yz = mix(VERTEX.yz, raised, right_arm * clamp(INSTANCE_CUSTOM.w, 0.0, 1.0));
    }
}
void fragment() {
    ALBEDO = tint.rgb;
    ROUGHNESS = 0.72;
}
