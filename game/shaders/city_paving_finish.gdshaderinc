// SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
// SPDX-License-Identifier: GPL-3.0-or-later
// See LICENSE and LICENSING.md in the repository root.

// Procedural world-projected concrete: metres, not tile-sized aggregate.
float paving_hash(vec2 p) {
	return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);
}
float paving_noise(vec2 p) {
	vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(paving_hash(i),paving_hash(i+vec2(1,0)),f.x),
		mix(paving_hash(i+vec2(0,1)),paving_hash(i+vec2(1,1)),f.x),f.y);
}
vec3 paving_finish(vec3 base, vec3 world, vec3 normal) {
	vec3 m=world*16.0;
	vec3 n=abs(normal);
	vec2 p=n.y>0.5 ? m.xz : (n.x>n.z ? m.zy : m.xy);
	float footprint=max(length(dFdx(p)),length(dFdy(p)));
	float fine=(paving_noise(p*75.0)-0.5)*(1.0-smoothstep(.006,.035,footprint));
	float mottling=paving_noise(p*2.6)-0.5;
	float grain=paving_noise(p*18.0)-0.5;
	vec2 slab=abs(fract(p/1.5+.5)-.5)*1.5;
	float distance_to_joint=min(slab.x,slab.y);
	float aa=max(footprint,.002);
	float joint=(1.0-smoothstep(.004,.004+aa,distance_to_joint))*(1.0-smoothstep(.025,.18,footprint));
	return base*(1.0+mottling*.08+grain*.045+fine*.10-joint*.19);
}
