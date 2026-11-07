# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Cartoon sound effects for Explore's slapstick weapons, synthesized once at
## first use (no recorded audio): a pop when someone falls apart, the rubber
## chicken's squawk, a pie splat, the mallet's bonk and the springy boing of
## a pedestrian snapping back together.
class_name ExploreMayhemSounds
extends RefCounted

const MIX_RATE := 22050
const CUES: Array[StringName] = [&"pop",&"squawk",&"splat",&"bonk",&"boing",&"whoosh"]
static var _streams: Dictionary = {}

## The cue's stream, or null for an unknown cue.
static func stream(cue: StringName) -> AudioStreamWAV:
	if _streams.has(cue): return _streams[cue]
	var samples := PackedFloat32Array()
	match cue:
		&"pop": samples = _pop()
		&"squawk": samples = _squawk()
		&"splat": samples = _splat()
		&"bonk": samples = _bonk()
		&"boing": samples = _boing()
		&"whoosh": samples = _whoosh()
		_: return null
	var data := PackedByteArray()
	data.resize(samples.size()*2)
	for index: int in samples.size():
		data.encode_s16(index*2,int(clampf(samples[index],-1.0,1.0)*32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	_streams[cue] = wav
	return wav

static func _buffer(seconds: float) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	samples.resize(int(seconds*MIX_RATE))
	return samples

## A cork-like pop: a falling sine with a click of noise at the start.
static func _pop() -> PackedFloat32Array:
	var samples := _buffer(.16)
	var noise := RandomNumberGenerator.new()
	noise.seed = 11
	var phase := 0.0
	for index: int in samples.size():
		var t := float(index)/MIX_RATE
		phase += TAU*lerpf(900.0,140.0,minf(1.0,t/.09))/MIX_RATE
		var click := noise.randf_range(-1.0,1.0)*exp(-t*160.0)*.6
		samples[index] = (sin(phase)*exp(-t*26.0)+click)*.8
	return samples

## A rubber-chicken squeal: a buzzy tone that rises, wobbles and falls.
static func _squawk() -> PackedFloat32Array:
	var samples := _buffer(.34)
	var phase := 0.0
	for index: int in samples.size():
		var t := float(index)/MIX_RATE
		var u := t/.34
		var pitch := 640.0+520.0*sin(PI*minf(1.0,u*1.4))+40.0*sin(TAU*28.0*t)
		phase += pitch/MIX_RATE
		var saw := 2.0*fposmod(phase,1.0)-1.0
		var square := 1.0 if fposmod(phase*2.0,1.0) < .5 else -1.0
		var envelope := minf(1.0,t*60.0)*(1.0-u)*(1.0-u)
		samples[index] = (saw*.55+square*.2)*envelope*.6
	return samples

## Soft, wet noise that thins out quickly.
static func _splat() -> PackedFloat32Array:
	var samples := _buffer(.3)
	var noise := RandomNumberGenerator.new()
	noise.seed = 23
	var low := 0.0
	for index: int in samples.size():
		var t := float(index)/MIX_RATE
		var cutoff := lerpf(.5,.04,minf(1.0,t/.25))
		low += (noise.randf_range(-1.0,1.0)-low)*cutoff
		samples[index] = low*exp(-t*12.0)*2.2
	return samples

## A hollow foam thump: low falling sine with a woody overtone.
static func _bonk() -> PackedFloat32Array:
	var samples := _buffer(.32)
	var phase := 0.0
	for index: int in samples.size():
		var t := float(index)/MIX_RATE
		phase += TAU*lerpf(240.0,95.0,minf(1.0,t/.12))/MIX_RATE
		samples[index] = (sin(phase)+.35*sin(phase*2.7)*exp(-t*30.0))*exp(-t*13.0)*.85
	return samples

## A spring boing: a rising tone whose vibrato grows and then rings out.
static func _boing() -> PackedFloat32Array:
	var samples := _buffer(.7)
	var phase := 0.0
	for index: int in samples.size():
		var t := float(index)/MIX_RATE
		var u := t/.7
		var pitch := (170.0+260.0*minf(1.0,u*2.5))*(1.0+.12*u*sin(TAU*14.0*t))
		phase += TAU*pitch/MIX_RATE
		samples[index] = sin(phase)*minf(1.0,t*90.0)*exp(-t*4.2)*.7
	return samples

## A quick airy swish for a swing.
static func _whoosh() -> PackedFloat32Array:
	var samples := _buffer(.2)
	var noise := RandomNumberGenerator.new()
	noise.seed = 5
	var low := 0.0
	var band := 0.0
	for index: int in samples.size():
		var t := float(index)/MIX_RATE
		var u := t/.2
		low += (noise.randf_range(-1.0,1.0)-low)*lerpf(.08,.35,u)
		band += (low-band)*.5
		samples[index] = (low-band)*sin(PI*u)*1.6
	return samples
