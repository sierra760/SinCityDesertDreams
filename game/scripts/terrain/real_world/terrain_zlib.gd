# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

class_name TerrainZlib
extends RefCounted

const MAX_BODY := 2*1024*1024
# Empty blocks still consume CPU. Bound blocks separately from decoded bytes;
# charge tree construction by conservative worst-case symbol/bit operations.
const MAX_DEFLATE_BLOCKS := 256
const MAX_DEFLATE_TREE_WORK := 262144
# Length and distance base values and extra-bit counts from RFC 1951, 3.2.5.
const LENGTH_BASE := [3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258]
const LENGTH_BITS := [0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0]
const DIST_BASE := [1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577]
const DIST_BITS := [0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13]

static func _fail(error: String) -> Dictionary:
	return {"ok":false,"error":error}

static func _be32(body: PackedByteArray, at: int) -> int:
	return (int(body[at])<<24)|(int(body[at+1])<<16)|(int(body[at+2])<<8)|int(body[at+3])

static func _bits(state: Dictionary, count: int) -> int:
	if state.bit+count>state.end*8:
		state.ok=false
		return 0
	var value := 0
	for i in count:
		value|=((int(state.body[state.bit>>3])>>(state.bit&7))&1)<<i
		state.bit+=1
	return value

# Canonical DEFLATE codes with explicit bounds, so damaged network input is a
# data error rather than an engine decompression diagnostic.
static func _tree(lengths: PackedInt32Array, state: Dictionary) -> Dictionary:
	# Two length/symbol traversals plus at most 15 code bits per symbol,
	# and the bounded count/canonical bookkeeping loops. Charge before allocation.
	state.tree_work+=lengths.size()*17+32
	if state.tree_work>MAX_DEFLATE_TREE_WORK: return _fail("DEFLATE tree work budget exceeded")
	var counts := PackedInt32Array()
	counts.resize(16)
	for length in lengths:
		if length<0 or length>15: return _fail("Invalid DEFLATE code length")
		if length>0: counts[length]+=1
	var remaining := 1
	for length in range(1,16):
		remaining=remaining*2-counts[length]
		if remaining<0: return _fail("Oversubscribed DEFLATE tree")
	var next := PackedInt32Array()
	next.resize(16)
	var code := 0
	for length in range(1,16):
		code=(code+counts[length-1])<<1
		next[length]=code
	var symbols := {}
	var maximum := 0
	for symbol in lengths.size():
		var length := lengths[symbol]
		if length==0: continue
		maximum=maxi(maximum,length)
		var reversed := 0
		var ordinary := next[length]
		for bit in length: reversed=(reversed<<1)|((ordinary>>bit)&1)
		symbols[(1<<length)|reversed]=symbol
		next[length]+=1
	return {"ok":true,"error":"","symbols":symbols,"maximum":maximum,"remaining":remaining}

static func _symbol(state: Dictionary, tree: Dictionary) -> int:
	var code := 0
	for length in range(1,int(tree.maximum)+1):
		code|=_bits(state,1)<<(length-1)
		if not state.ok: return -1
		var key := (1<<length)|code
		if tree.symbols.has(key): return int(tree.symbols[key])
	state.ok=false
	return -1

static func _trees(state: Dictionary, kind: int) -> Dictionary:
	var literal := PackedInt32Array()
	var distance := PackedInt32Array()
	if kind==1:
		literal.resize(288)
		for i in 288: literal[i]=8 if i<144 else (9 if i<256 else (7 if i<280 else 8))
		distance.resize(32)
		distance.fill(5)
	else:
		var literal_count := _bits(state,5)+257
		var distance_count := _bits(state,5)+1
		var code_count := _bits(state,4)+4
		var order := [16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15]
		var code_lengths := PackedInt32Array()
		code_lengths.resize(19)
		for i in code_count: code_lengths[order[i]]=_bits(state,3)
		state.tree_work+=literal_count+distance_count
		if state.tree_work>MAX_DEFLATE_TREE_WORK: return _fail("DEFLATE tree work budget exceeded")
		var code_tree := _tree(code_lengths,state)
		if not code_tree.ok: return code_tree
		if not state.ok or code_tree.remaining!=0 or literal_count>286: return _fail("Invalid dynamic DEFLATE header")
		var lengths := PackedInt32Array()
		while lengths.size()<literal_count+distance_count:
			var symbol := _symbol(state,code_tree)
			if not state.ok: return _fail("Invalid dynamic DEFLATE code")
			if symbol<16: lengths.append(symbol)
			else:
				if symbol==16 and lengths.is_empty(): return _fail("DEFLATE repeat has no predecessor")
				var repeat := _bits(state,2 if symbol==16 else (3 if symbol==17 else 7))+(3 if symbol!=18 else 11)
				var value := lengths[-1] if symbol==16 else 0
				if not state.ok or lengths.size()+repeat>literal_count+distance_count: return _fail("DEFLATE repeat exceeds tree")
				for i in repeat: lengths.append(value)
		literal=lengths.slice(0,literal_count)
		distance=lengths.slice(literal_count)
	if literal[256]==0: return _fail("DEFLATE tree is missing end marker")
	var literal_tree := _tree(literal,state)
	if not literal_tree.ok: return literal_tree
	var distance_tree := _tree(distance,state)
	if not distance_tree.ok: return distance_tree
	# The code-length tree must be complete; literal/distance trees may only
	# be incomplete for a single one-bit code (or an unused empty distance set).
	if literal_tree.remaining!=0 and literal_tree.maximum!=1: return _fail("Incomplete DEFLATE literal tree")
	if distance_tree.remaining!=0 and distance_tree.maximum>1: return _fail("Incomplete DEFLATE distance tree")
	return {"ok":true,"error":"","literal":literal_tree,"distance":distance_tree}

static func inflate_exact(body: PackedByteArray, expected_bytes: int) -> Dictionary:
	var expected := expected_bytes
	if expected<1 or expected>MAX_BODY or body.size()>MAX_BODY: return _fail("Zlib input or requested output exceeds 2 MiB")
	if body.size()<6 or body[0]&15!=8 or body[0]>>4>7 or ((int(body[0])<<8)|body[1])%31!=0 or body[1]&32: return _fail("Invalid zlib header")
	var state := {"body":body,"bit":16,"end":body.size()-4,"ok":true,"tree_work":0}
	var output := PackedByteArray()
	output.resize(expected)
	var written := 0
	var final := false
	var blocks := 0
	var fixed_trees := {}
	while not final:
		blocks+=1
		if blocks>MAX_DEFLATE_BLOCKS: return _fail("DEFLATE block work budget exceeded")
		final=_bits(state,1)!=0
		var kind := _bits(state,2)
		if not state.ok or kind==3: return _fail("Invalid DEFLATE block")
		if kind==0:
			state.bit=(int(state.bit)+7)&~7
			var length := _bits(state,16)
			var complement := _bits(state,16)
			if not state.ok or length!=(complement^65535) or written+length>expected or state.bit+length*8>state.end*8: return _fail("Invalid stored DEFLATE block")
			for i in length: output[written+i]=body[(int(state.bit)>>3)+i]
			written+=length
			state.bit+=length*8
		else:
			var trees: Dictionary
			if kind==1 and not fixed_trees.is_empty(): trees=fixed_trees
			else:
				trees=_trees(state,kind)
				if not trees.ok: return trees
				if kind==1: fixed_trees=trees
			while true:
				var symbol := _symbol(state,trees.literal)
				if not state.ok: return _fail("Invalid DEFLATE literal")
				if symbol==256: break
				if symbol<256:
					if written>=expected: return _fail("Zlib expanded data exceeds expected size")
					output[written]=symbol
					written+=1
				else:
					if symbol>285: return _fail("Reserved DEFLATE length code")
					var index := symbol-257
					var length: int = LENGTH_BASE[index]+_bits(state,LENGTH_BITS[index])
					var distance_symbol := _symbol(state,trees.distance)
					if not state.ok or distance_symbol<0 or distance_symbol>29: return _fail("Invalid DEFLATE distance code")
					var distance: int = DIST_BASE[distance_symbol]+_bits(state,DIST_BITS[distance_symbol])
					if not state.ok or distance>written or written+length>expected: return _fail("DEFLATE match exceeds bounded output")
					for i in length:
						output[written]=output[written-distance]
						written+=1
	if written!=expected or (int(state.bit)+7)/8!=state.end: return _fail("Truncated zlib stream or trailing compressed bytes")
	var a := 1
	var b := 0
	for value in output:
		a=(a+value)%65521
		b=(b+a)%65521
	if ((b<<16)|a)!=_be32(body,body.size()-4): return _fail("Zlib checksum mismatch")
	return {"ok":true,"error":"","bytes":output}

