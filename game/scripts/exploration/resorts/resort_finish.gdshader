// SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
// SPDX-License-Identifier: GPL-3.0-or-later
// See LICENSE and LICENSING.md in the repository root.

// Procedural casino-floor finishes, projected in hall metres so the authored
// primitives need no unwrapping and patterns run continuously across parts.
// finish: 0 hard floor, 1 carpet, 2 wall, 3 ceiling, 4 stone, 5 wood,
// 6 metal, 7 glass, 8 felt, 9 lamp, 10 sign plate, 11 screen, 12 rubber,
// 13 cove light, 14 foliage.
// variant selects the resort: 0 Comstock Grand, 1 Silver Junction,
// 2 Boulder Crown, 3 Desert Orbit. No bitmap texture is sampled.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform int finish = 2;
uniform int variant = 0;
uniform vec3 base_color : source_color = vec3(.8,.7,.55);
uniform vec3 accent_color : source_color = vec3(.69,.42,.23);
uniform vec3 detail_color : source_color = vec3(.95,.9,.8);
// World position of the hall floor centre, in tile units.
uniform vec3 origin = vec3(0.0);
uniform float tiles_to_metres = 16.0;
// Hall metres (x, z) on which floor and carpet repeats are centred: the pit.
uniform vec2 pattern_center = vec2(0.0,2.0);
varying vec3 hall;
varying vec3 world_normal;

float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float grain(vec2 p) {
	vec2 cell=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(hash(cell),hash(cell+vec2(1,0)),f.x),mix(hash(cell+vec2(0,1)),hash(cell+vec2(1,1)),f.x),f.y);
}
float line(float value, float period, float width) {
	float d = abs(fract(value/period+.5)-.5)*period;
	return 1.0-smoothstep(width*.5,width*.5+.01,d);
}

void vertex() {
	hall = ((MODEL_MATRIX*vec4(VERTEX,1.0)).xyz-origin)*tiles_to_metres;
	world_normal = normalize((MODEL_MATRIX*vec4(NORMAL,0.0)).xyz);
}

void fragment() {
	vec3 n = abs(world_normal);
	bool horizontal = n.y > max(n.x,n.z);
	vec2 uv = horizontal ? hall.xz : (n.x > n.z ? hall.zy : hall.xy);
	if (horizontal && (finish==0 || finish==1)) uv -= pattern_center;
	float fine = grain(uv*55.0)-.5;
	vec3 base = base_color;
	METALLIC = 0.0;
	ROUGHNESS = .7;
	SPECULAR = .4;
	EMISSION = vec3(0.0);
	float glow = .16;
	if (finish==0) {
		// Hard floors: terrazzo chips everywhere, then each resort's pattern.
		float chip = smoothstep(.70,.86,grain(uv*38.0));
		float chip2 = smoothstep(.78,.92,grain(uv*61.0+7.0));
		base *= 1.0+fine*.08;
		base = mix(base,accent_color,chip*.22);
		base = mix(base,detail_color,chip2*.20);
		if (variant==1) {
			// Checkered ivory and charcoal squares, 1.2 m, brass divider strips.
			float check = mod(floor(uv.x/1.2)+floor(uv.y/1.2),2.0);
			base = mix(base,vec3(.16,.16,.16)+fine*.04,check*.92);
			base = mix(base,accent_color,max(line(uv.x,1.2,.035),line(uv.y,1.2,.035)));
		} else if (variant==2) {
			// Brass sunbursts inlaid on a 6 m grid.
			vec2 c = mod(uv+3.0,6.0)-3.0;
			float r = length(c);
			float a = atan(c.y,c.x);
			float ray = step(.86,abs(cos(a*8.0)))*step(r,2.4)*step(.45,r);
			float ring = line(r,100.0,.06)*step(r,2.5)*step(2.35,r);
			float hub = 1.0-smoothstep(.40,.44,r);
			base = mix(base,accent_color*.85,clamp(ray*.85+ring+hub*.9,0.0,1.0)*.62);
		} else if (variant==3) {
			// Copper orbit rings around 8 m centres.
			vec2 c = mod(uv+4.0,8.0)-4.0;
			float e = length(c*vec2(1.0,1.6));
			base = mix(base,accent_color,line(e,1.25,.05)*step(e,3.8));
		} else {
			// Sandstone flags with mortar joints.
			float row = floor(uv.y/.9);
			float joint = max(line(uv.y,.9,.025),line(uv.x+mod(row,2.0)*.6,1.2,.025));
			base *= mix(.95,1.06,grain(vec2(floor((uv.x+mod(row,2.0)*.6)/1.2),row)*3.7));
			base = mix(base,base*.62,joint);
		}
		ROUGHNESS = .38;
		SPECULAR = .45;
		glow = .08;
	} else if (finish==1) {
		// Cut-pile carpet: soft fibre noise and each resort's repeat.
		float pile = grain(uv*140.0)-.5;
		base *= 1.0+pile*.10+fine*.05;
		if (variant==1) {
			base = mix(base,detail_color*.92,line(uv.x,.6,.025)*.85);
		} else if (variant==3) {
			vec2 c = mod(uv+3.0,6.0)-3.0;
			float e = length(c*vec2(1.0,2.0));
			float orbit = 1.0-smoothstep(.06,.11,abs(fract(e/1.1+.5)-.5)*1.1);
			base = mix(base,detail_color*.85,orbit*step(e,2.6)*.7);
			float star = step(.985,hash(floor(uv*3.0)))*(1.0-smoothstep(.04,.09,length(fract(uv*3.0)-.5)));
			base = mix(base,detail_color,star);
		} else if (variant==2) {
			float chevron = line(abs(mod(uv.x,2.0)-1.0)+uv.y,1.0,.10);
			base = mix(base,accent_color*.85,chevron*.7);
		} else {
			// Copper medallions on a 2.4 m grid with a fine border lattice.
			vec2 c = mod(uv+1.2,2.4)-1.2;
			float r = length(c);
			float ring = 1.0-smoothstep(.025,.045,abs(r-.5));
			float hub = 1.0-smoothstep(.10,.13,r);
			float petals = step(.86,abs(cos(atan(c.y,c.x)*4.0)))*step(.18,r)*step(r,.40);
			base = mix(base,accent_color*.8,clamp(ring+hub+petals*.7,0.0,1.0)*.42);
			base = mix(base,accent_color*.6,max(line(uv.x,2.4,.03),line(uv.y,2.4,.03))*.35);
		}
		ROUGHNESS = .96;
		SPECULAR = .1;
		glow = .07;
	} else if (finish==2) {
		// Wall: ashlar courses, limestone panels or enamel panelling.
		if (variant==3) {
			base *= mix(.90,1.0,line(uv.x,2.0,.03) > .5 ? 0.0 : 1.0)*(1.0+fine*.03);
			ROUGHNESS = .42;
			SPECULAR = .5;
		} else {
			float course = variant==1 ? 1.5 : .75;
			float row = floor(uv.y/course);
			float block = variant==1 ? 3.0 : 1.5;
			float joint = max(line(uv.y,course,.02),line(uv.x+mod(row,2.0)*block*.5,block,.02));
			base *= mix(.94,1.05,grain(vec2(floor((uv.x+mod(row,2.0)*block*.5)/block),row)*2.3));
			base *= 1.0+fine*.10;
			base = mix(base,base*.72,joint);
			ROUGHNESS = .82;
		}
		glow = .18;
	} else if (finish==3) {
		// Ceiling, seen from below.
		if (variant==0) {
			// Pressed tin: 0.6 m tiles with a raised rosette and bead border.
			vec2 c = mod(uv,.6)-.3;
			float bead = max(line(uv.x,.6,.03),line(uv.y,.6,.03));
			float rose = smoothstep(.16,.10,length(c))*(.6+.4*cos(atan(c.y,c.x)*8.0));
			float diamond = line(abs(c.x)+abs(c.y),100.0,.02)*step(abs(abs(c.x)+abs(c.y)-.22),.02);
			base *= .86+rose*.22+diamond*.18-bead*.20;
			METALLIC = .45;
			ROUGHNESS = .38;
		} else if (variant==1) {
			// Green glass panes in brass glazing bars, glowing like daylight.
			float bars = max(line(uv.x,1.6,.06),line(uv.y,2.4,.06));
			base = mix(base*(1.0+fine*.08),accent_color,bars);
			glow = .55-bars*.4;
			ROUGHNESS = .2;
		} else if (variant==2) {
			// Stepped Deco coffers.
			vec2 c = abs(mod(uv,3.0)-1.5);
			float step1 = step(1.2,max(c.x,c.y));
			float step2 = step(.8,max(c.x,c.y));
			base *= .80+step2*.12+step1*.12;
			base = mix(base,accent_color,line(max(c.x,c.y),100.0,.05)*step(abs(max(c.x,c.y)-1.0),.03));
		} else {
			// Planetarium dome: navy sky, star points and faint orbit rings.
			vec2 cell = floor(uv*1.6);
			vec2 f = fract(uv*1.6)-.5;
			float star = step(.90,hash(cell))*(1.0-smoothstep(.02,.07,length(f-vec2(hash(cell+3.1),hash(cell+7.7))*.5+.25)));
			float rings = line(length(hall.xz*vec2(1.0,1.35)),5.5,.04)*.55;
			base = mix(base*(1.0+fine*.05),detail_color,clamp(star+rings*.5,0.0,1.0));
			EMISSION = detail_color*star*2.2+accent_color*rings*.25;
			glow = .10;
		}
	} else if (finish==4) {
		base *= 1.0+fine*.12+(grain(uv*7.0)-.5)*.08;
		ROUGHNESS = .55;
		SPECULAR = .5;
		glow = .16;
	} else if (finish==5) {
		float wood = grain(vec2(uv.x*18.0+sin(uv.y*2.0)*.4,uv.y*1.3));
		base *= mix(.72,1.18,wood);
		ROUGHNESS = .32;
		SPECULAR = .55;
		glow = .14;
	} else if (finish==6) {
		float brush = grain(uv*vec2(240.0,3.0))-.5;
		base *= 1.0+brush*.12;
		METALLIC = .78;
		ROUGHNESS = .30+brush*.08;
		SPECULAR = .6;
		glow = .16;
	} else if (finish==7) {
		base *= 1.0+fine*.04;
		METALLIC = .1;
		ROUGHNESS = .12;
		SPECULAR = .8;
		glow = .32;
	} else if (finish==8) {
		float nap = grain(uv*220.0)-.5;
		base *= 1.0+nap*.08+fine*.04;
		ROUGHNESS = .95;
		SPECULAR = .12;
		glow = .16;
	} else if (finish==9) {
		ROUGHNESS = .4;
		EMISSION = base*2.4;
		glow = 0.0;
	} else if (finish==10) {
		ROUGHNESS = .5;
		glow = .30;
	} else if (finish==11) {
		// Display: lit cells with a quiet scanline, like split-flap or tube digits.
		vec2 cell = abs(fract(uv*vec2(3.2,2.6))-.5);
		float frame = step(.42,max(cell.x,cell.y));
		float scan = .88+.12*sin(uv.y*90.0);
		base = mix(base*scan,base*.25,frame);
		ROUGHNESS = .25;
		EMISSION = base*1.4;
		glow = 0.0;
	} else if (finish==13) {
		// Cove strip: a cool, even glow along the cornice.
		ROUGHNESS = .5;
		EMISSION = base*1.8;
		glow = 0.0;
	} else if (finish==14) {
		// Palm fronds: veined leaf blades.
		float vein = line(uv.x,.12,.012);
		base *= (1.0+fine*.12)*mix(1.0,1.25,vein);
		ROUGHNESS = .7;
		glow = .10;
	} else {
		base *= .9+fine*.06;
		ROUGHNESS = .9;
		glow = .08;
	}
	ALBEDO = base;
	EMISSION += base*glow;
}
