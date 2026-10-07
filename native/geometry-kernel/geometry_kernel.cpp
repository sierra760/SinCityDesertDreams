// SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
// SPDX-License-Identifier: GPL-3.0-or-later
// See LICENSE and LICENSING.md in the repository root.

// Native port of scripts/view/city_network_physics.gd resolve(). Its output
// bytes equal the GDScript resolver's: float32 vector arithmetic is spelled
// exactly as the engine's own uncontracted expressions (build with
// -ffp-contract=off), scalar predicates stay double, dictionary insertion
// order is preserved and Godot's introsort governs equal-role patch order.
// Containers are flat open-addressing tables and linked-list bins so the
// million-edge cities spend their time on geometry, not allocation.
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/rect2.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <cmath>
#include <cstdint>
#include <cstring>
#include <unordered_map>
#include <utility>
#include <vector>

#include "scdd_sort_array.hpp"

#ifdef SCDD_PROFILE
#include <chrono>
#include <godot_cpp/variant/utility_functions.hpp>
#define SCDD_STAGE(name) scdd_profile_stage(name)
static std::chrono::steady_clock::time_point scdd_profile_last;
static void scdd_profile_stage(const char *name) {
	auto now = std::chrono::steady_clock::now();
	if (name[0] != '\0') {
		godot::UtilityFunctions::print("SCDD_PROFILE ", name, " ", std::chrono::duration_cast<std::chrono::microseconds>(now - scdd_profile_last).count(), "us");
	}
	scdd_profile_last = now;
}
#else
#define SCDD_STAGE(name) ((void)0)
#endif

using namespace godot;

namespace {

constexpr int BIN_SCALE = 32;
constexpr int COARSE_BIN_SCALE = 4;
constexpr double DENSE_LIMIT = 0.125;
constexpr double CANDIDATE_PAD = 0.0001;

using Polygon = std::vector<Vector2>;

// Engine float32 vector methods, written as the engine source spells them.
inline float cross2(const Vector2 &a, const Vector2 &b) { return a.x * b.y - a.y * b.x; }
inline float dot2(const Vector2 &a, const Vector2 &b) { return a.x * b.x + a.y * b.y; }
inline float length_squared2(const Vector2 &a) { return a.x * a.x + a.y * a.y; }
inline float length2(const Vector2 &a) { return std::sqrt(a.x * a.x + a.y * a.y); }
inline Vector2 normalized2(Vector2 v) {
	float l = v.x * v.x + v.y * v.y;
	if (l != 0) {
		l = std::sqrt(l);
		v.x /= l;
		v.y /= l;
	}
	return v;
}
inline float lerpf(float from, float to, float weight) { return from + (to - from) * weight; }
inline Vector2 lerp2(const Vector2 &a, const Vector2 &b, float w) { return Vector2(lerpf(a.x, b.x, w), lerpf(a.y, b.y, w)); }
inline Vector3 lerp3(const Vector3 &a, const Vector3 &b, float w) { return Vector3(lerpf(a.x, b.x, w), lerpf(a.y, b.y, w), lerpf(a.z, b.z, w)); }
inline Vector3 cross3(const Vector3 &a, const Vector3 &b) {
	return Vector3((a.y * b.z) - (a.z * b.y), (a.z * b.x) - (a.x * b.z), (a.x * b.y) - (a.y * b.x));
}
inline float length_squared3(const Vector3 &a) {
	float x2 = a.x * a.x;
	float y2 = a.y * a.y;
	float z2 = a.z * a.z;
	return x2 + y2 + z2;
}
inline Vector2 xz(const Vector3 &p) { return Vector2(p.x, p.z); }
// GDScript subtracts the components as doubles; the Vector2 constructor narrows.
inline Vector2 delta_xz(const Vector3 &a, const Vector3 &b) {
	return Vector2((float)((double)b.x - (double)a.x), (float)((double)b.z - (double)a.z));
}
inline int64_t floori(double x) { return (int64_t)std::floor(x); }
inline int64_t roundi(double x) { return (int64_t)std::round(x); }
inline Vector3 down_by(double depth) { return Vector3(0, -1, 0) * (float)depth; }
inline double maxd(double a, double b) { return a > b ? a : b; }
inline double mind(double a, double b) { return a < b ? a : b; }

// Integer keys mirror Vector2i/Vector3i/Vector4i component widths.
struct Key2 {
	int32_t a, b;
	bool operator==(const Key2 &o) const { return a == o.a && b == o.b; }
};
struct Key3 {
	int32_t a, b, c;
	bool operator==(const Key3 &o) const { return a == o.a && b == o.b && c == o.c; }
};
struct Key4 {
	int32_t a, b, c, d;
	bool operator==(const Key4 &o) const { return a == o.a && b == o.b && c == o.c && d == o.d; }
};
inline uint64_t mix64(uint64_t h, uint64_t v) {
	v *= 0x9e3779b97f4a7c15ull;
	v ^= v >> 29;
	h ^= v;
	h *= 0xbf58476d1ce4e5b9ull;
	return h ^ (h >> 32);
}
inline uint64_t pack32(int32_t a, int32_t b) { return (uint64_t)(uint32_t)a | ((uint64_t)(uint32_t)b << 32); }
inline uint64_t hash_key(const Key2 &k) { return mix64(0x1234567ull, pack32(k.a, k.b)); }
inline uint64_t hash_key(const Key3 &k) { return mix64(mix64(0x1234567ull, pack32(k.a, k.b)), (uint32_t)k.c); }
inline uint64_t hash_key(const Key4 &k) { return mix64(mix64(0x1234567ull, pack32(k.a, k.b)), pack32(k.c, k.d)); }

// Insert-only open-addressing table; values are small trivially copyable types.
template <typename K, typename V>
class FlatMap {
	struct Slot {
		K key;
		V value;
		bool used;
	};
	std::vector<Slot> slots;
	size_t mask = 0;
	size_t count = 0;

	void grow() {
		std::vector<Slot> old = std::move(slots);
		size_t capacity = old.empty() ? 64 : old.size() * 2;
		slots.assign(capacity, Slot{ K{}, V{}, false });
		mask = capacity - 1;
		for (const Slot &slot : old) {
			if (!slot.used) {
				continue;
			}
			size_t i = (size_t)hash_key(slot.key) & mask;
			while (slots[i].used) {
				i = (i + 1) & mask;
			}
			slots[i] = slot;
		}
	}

public:
	void reserve(size_t expected) {
		size_t capacity = 64;
		while (capacity * 3 < expected * 4) {
			capacity <<= 1;
		}
		slots.assign(capacity, Slot{ K{}, V{}, false });
		mask = capacity - 1;
		count = 0;
	}
	void clear() {
		for (Slot &slot : slots) {
			slot.used = false;
		}
		count = 0;
	}
	size_t size() const { return count; }
	V *find(const K &key) {
		if (slots.empty()) {
			return nullptr;
		}
		size_t i = (size_t)hash_key(key) & mask;
		while (slots[i].used) {
			if (slots[i].key == key) {
				return &slots[i].value;
			}
			i = (i + 1) & mask;
		}
		return nullptr;
	}
	// Returns the value slot; `inserted` reports whether the key was new.
	V &get(const K &key, const V &initial, bool &inserted) {
		if ((count + 1) * 4 > slots.size() * 3) {
			grow();
		}
		size_t i = (size_t)hash_key(key) & mask;
		while (slots[i].used) {
			if (slots[i].key == key) {
				inserted = false;
				return slots[i].value;
			}
			i = (i + 1) & mask;
		}
		slots[i].used = true;
		slots[i].key = key;
		slots[i].value = initial;
		count++;
		inserted = true;
		return slots[i].value;
	}
	template <typename F>
	void for_each(F &&visit) const {
		for (const Slot &slot : slots) {
			if (slot.used) {
				visit(slot.key, slot.value);
			}
		}
	}
};

// Lists of indices per key as singly linked nodes; order within a list is
// only used where the GDScript result does not depend on it.
struct IndexLists {
	FlatMap<Key3, int32_t> heads;
	std::vector<int32_t> values;
	std::vector<int32_t> next;
	void add(const Key3 &key, int32_t value) {
		bool inserted = false;
		int32_t &head = heads.get(key, -1, inserted);
		values.push_back(value);
		next.push_back(head);
		head = (int32_t)values.size() - 1;
	}
	int32_t first(const Key3 &key) {
		int32_t *head = heads.find(key);
		return head ? *head : -1;
	}
};

struct Less {
	template <typename T>
	bool operator()(const T &a, const T &b) const { return a < b; }
};
struct RoleDescending {
	const int32_t *roles = nullptr;
	bool operator()(int32_t a, int32_t b) const { return roles[a] > roles[b]; }
};

inline Rect2 bounds_of(const Vector2 *points, size_t count) {
	Rect2 result(points[0], Vector2());
	for (size_t i = 0; i < count; i++) {
		result = result.expand(points[i]);
	}
	return result;
}
inline Rect2 bounds_of(const Polygon &polygon) { return bounds_of(polygon.data(), polygon.size()); }

struct CellRect {
	int64_t x0 = 0, y0 = 0, x1 = 0, y1 = 0;
	int64_t area() const { return (x1 - x0) * (y1 - y0); }
};

inline CellRect partition_cells(const Rect2 &bounds) {
	Vector2 end = bounds.get_end();
	CellRect cells;
	cells.x0 = floori((double)bounds.position.x * 16);
	cells.y0 = floori((double)bounds.position.y * 16);
	cells.x1 = floori((double)end.x * 16) + 1;
	cells.y1 = floori((double)end.y * 16) + 1;
	return cells;
}

inline double polygon_area(const Polygon &polygon) {
	double area = 0.0;
	for (size_t i = 1; i + 1 < polygon.size(); i++) {
		area += (double)cross2(polygon[i] - polygon[0], polygon[i + 1] - polygon[0]);
	}
	return std::fabs(area) * 0.5;
}

// One plane clips a polygon into the retained side (`sign_value`) and the cut
// side (`-sign_value`). Both outputs carry exactly the values two separate
// GDScript clips would: the shared cross product, each side's own signed
// predicate and its own lerp weight.
inline void clip_both_sides(const Polygon &polygon, const Vector2 &origin, const Vector2 &edge, double sign_value, Polygon &inside, Polygon &outside) {
	inside.clear();
	outside.clear();
	if (polygon.empty()) {
		return;
	}
	const double outside_sign = -sign_value;
	Vector2 previous = polygon.back();
	double cross_before = (double)cross2(edge, previous - origin);
	double before_in = cross_before * sign_value;
	double before_out = cross_before * outside_sign;
	for (const Vector2 &current : polygon) {
		double cross_now = (double)cross2(edge, current - origin);
		double now_in = cross_now * sign_value;
		double now_out = cross_now * outside_sign;
		if ((before_in >= 0) != (now_in >= 0)) {
			inside.push_back(lerp2(previous, current, (float)(before_in / (before_in - now_in))));
		}
		if (now_in >= 0) {
			inside.push_back(current);
		}
		if ((before_out >= 0) != (now_out >= 0)) {
			outside.push_back(lerp2(previous, current, (float)(before_out / (before_out - now_out))));
		}
		if (now_out >= 0) {
			outside.push_back(current);
		}
		previous = current;
		before_in = now_in;
		before_out = now_out;
	}
}

// Reusable list of polygons; buffers keep their capacity between groups.
struct PieceSet {
	std::vector<Polygon> items;
	size_t count = 0;
	void clear() { count = 0; }
	bool empty() const { return count == 0; }
	Polygon &push() {
		if (count == items.size()) {
			items.emplace_back();
		}
		Polygon &piece = items[count++];
		piece.clear();
		return piece;
	}
	void pop() { count--; }
	const Polygon &operator[](size_t i) const { return items[i]; }
};

struct ClipScratch {
	Polygon buffers[2];
};

// Fewer than three vertices always has area 0.0, so the GDScript thresholds
// reject them without the loop.
inline void subtract_triangle(const Polygon &polygon, const Vector2 *cut, const Rect2 &cut_bounds, PieceSet &out, ClipScratch &scratch) {
	if (!bounds_of(polygon).intersects(cut_bounds)) {
		out.push() = polygon;
		return;
	}
	double sign_value = ((double)cross2(cut[1] - cut[0], cut[2] - cut[0]) < 0) ? -1.0 : 1.0;
	const Polygon *remainder = &polygon;
	int next_buffer = 0;
	for (int i = 0; i < 3; i++) {
		Vector2 a = cut[i];
		Vector2 delta = cut[(i + 1) % 3] - a;
		Polygon &outside = out.push();
		Polygon &clipped = scratch.buffers[next_buffer];
		next_buffer ^= 1;
		clip_both_sides(*remainder, a, delta, sign_value, clipped, outside);
		if (outside.size() < 3 || !(polygon_area(outside) > 0.000000001)) {
			out.pop();
		}
		remainder = &clipped;
		if (remainder->size() < 3 || polygon_area(*remainder) < 0.000000001) {
			break;
		}
	}
}

// Flat partition result: polygon k owns pieces polygon_begin[k]..polygon_begin[k+1],
// piece j owns points piece_begin[j]..piece_begin[j+1].
struct FlatPartition {
	std::vector<Vector2> points;
	std::vector<uint32_t> piece_begin{ 0 };
	std::vector<uint32_t> polygon_begin{ 0 };
};

struct PartitionWork {
	std::vector<Rect2> occupied_bounds;
	FlatMap<Key2, int32_t> bin_heads;
	std::vector<int32_t> bin_values;
	std::vector<int32_t> bin_next;
	std::vector<int32_t> broad;
	std::vector<int32_t> candidates;
	std::vector<int32_t> stamps;
	PieceSet pieces;
	PieceSet rest;
	ClipScratch scratch;
};

// `triangles` holds three local points per polygon. The bins and broad list
// only accelerate the search: every earlier polygon whose bounds intersect
// shares a 1/16 cell with this one, so the applied cuts are always exactly the
// earlier intersecting polygons in increasing index order, as in GDScript.
void partition_polygons(const Vector2 *triangles, size_t polygon_count, PartitionWork &work, FlatPartition &result) {
	result.points.clear();
	result.piece_begin.assign(1, 0);
	result.polygon_begin.assign(1, 0);
	work.occupied_bounds.clear();
	work.bin_heads.clear();
	work.bin_values.clear();
	work.bin_next.clear();
	work.broad.clear();
	work.stamps.assign(polygon_count, -1);
	const bool indexed = polygon_count > 64;
	if (indexed) {
		work.bin_heads.reserve(polygon_count * 4);
	}
	const scdd::SortArray<int32_t, Less, true> int_sorter;
	for (size_t polygon_index = 0; polygon_index < polygon_count; polygon_index++) {
		const Vector2 *polygon = triangles + polygon_index * 3;
		Rect2 polygon_bounds = bounds_of(polygon, 3);
		PieceSet *pieces = &work.pieces;
		PieceSet *rest = &work.rest;
		pieces->clear();
		pieces->push().assign(polygon, polygon + 3);
		CellRect cells = indexed ? partition_cells(polygon_bounds) : CellRect();
		std::vector<int32_t> &candidates = work.candidates;
		candidates.clear();
		if (indexed && cells.area() <= 4096) {
			const int32_t stamp = (int32_t)polygon_index;
			for (int32_t index : work.broad) {
				if (work.stamps[index] != stamp) {
					work.stamps[index] = stamp;
					if (polygon_bounds.intersects(work.occupied_bounds[index])) {
						candidates.push_back(index);
					}
				}
			}
			for (int64_t y = cells.y0; y < cells.y1; y++) {
				for (int64_t x = cells.x0; x < cells.x1; x++) {
					int32_t *head = work.bin_heads.find(Key2{ (int32_t)x, (int32_t)y });
					for (int32_t node = head ? *head : -1; node >= 0; node = work.bin_next[node]) {
						int32_t index = work.bin_values[node];
						if (work.stamps[index] != stamp) {
							work.stamps[index] = stamp;
							if (polygon_bounds.intersects(work.occupied_bounds[index])) {
								candidates.push_back(index);
							}
						}
					}
				}
			}
			int_sorter.sort(candidates.data(), (int64_t)candidates.size());
		} else {
			for (int32_t index = 0; index < (int32_t)polygon_index; index++) {
				if (polygon_bounds.intersects(work.occupied_bounds[index])) {
					candidates.push_back(index);
				}
			}
		}
		for (int32_t cut_index : candidates) {
			const Rect2 &cut_bounds = work.occupied_bounds[cut_index];
			const Vector2 *cut = triangles + (size_t)cut_index * 3;
			rest->clear();
			for (size_t i = 0; i < pieces->count; i++) {
				subtract_triangle((*pieces)[i], cut, cut_bounds, *rest, work.scratch);
			}
			std::swap(pieces, rest);
			if (pieces->empty()) {
				break;
			}
		}
		if (indexed) {
			int32_t index = (int32_t)polygon_index;
			if (cells.area() > 4096) {
				work.broad.push_back(index);
			} else {
				for (int64_t y = cells.y0; y < cells.y1; y++) {
					for (int64_t x = cells.x0; x < cells.x1; x++) {
						bool inserted = false;
						int32_t &head = work.bin_heads.get(Key2{ (int32_t)x, (int32_t)y }, -1, inserted);
						work.bin_values.push_back(index);
						work.bin_next.push_back(head);
						head = (int32_t)work.bin_values.size() - 1;
					}
				}
			}
		}
		work.occupied_bounds.push_back(polygon_bounds);
		for (size_t i = 0; i < pieces->count; i++) {
			const Polygon &piece = (*pieces)[i];
			result.points.insert(result.points.end(), piece.begin(), piece.end());
			result.piece_begin.push_back((uint32_t)result.points.size());
		}
		result.polygon_begin.push_back((uint32_t)result.piece_begin.size() - 1);
	}
}

inline Vector3 patch_point(const Vector3 *triangle, const Vector2 &p) {
	const Vector3 a = triangle[0];
	const Vector3 b = triangle[1];
	const Vector3 c = triangle[2];
	if (a.y == b.y && a.y == c.y) {
		return Vector3(p.x, a.y, p.y);
	}
	Vector2 ab = delta_xz(a, b);
	Vector2 ac = delta_xz(a, c);
	Vector2 ap = p - Vector2(a.x, a.z);
	double area = (double)cross2(ab, ac);
	double y = (double)a.y + ((double)b.y - (double)a.y) * (double)cross2(ap, ac) / area + ((double)c.y - (double)a.y) * (double)cross2(ab, ap) / area;
	return Vector3(p.x, (float)y, p.y);
}

// Godot's Variant hash of Array[PackedVector2Array]; the partition cache keeps
// the engine's single slot per hash and reuses only on exact `==` equality.
constexpr uint32_t HASH_MURMUR3_SEED = 0x7f07c65u;
constexpr uint32_t VARIANT_TYPE_ARRAY = 28;
inline uint32_t murmur3_one_32(uint32_t in, uint32_t seed) {
	in *= 0xcc9e2d51u;
	in = (in << 15) | (in >> 17);
	in *= 0x1b873593u;
	seed ^= in;
	seed = (seed << 13) | (seed >> 19);
	seed = seed * 5 + 0xe6546b64u;
	return seed;
}
inline uint32_t murmur3_one_float(float value, uint32_t seed) {
	union {
		float f;
		uint32_t i;
	} u;
	if (value == 0.0f) {
		u.f = 0.0f;
	} else if (std::isnan(value)) {
		u.f = NAN;
	} else {
		u.f = value;
	}
	return murmur3_one_32(u.i, seed);
}
inline uint32_t fmix32(uint32_t h) {
	h ^= h >> 16;
	h *= 0x85ebca6bu;
	h ^= h >> 13;
	h *= 0xc2b2ae35u;
	h ^= h >> 16;
	return h;
}
uint32_t godot_hash(const Vector2 *triangles, size_t polygon_count) {
	uint32_t h = murmur3_one_32(VARIANT_TYPE_ARRAY, HASH_MURMUR3_SEED);
	for (size_t k = 0; k < polygon_count; k++) {
		uint32_t ph = HASH_MURMUR3_SEED;
		for (size_t i = 0; i < 3; i++) {
			ph = murmur3_one_float(triangles[k * 3 + i].x, ph);
			ph = murmur3_one_float(triangles[k * 3 + i].y, ph);
		}
		ph = fmix32(ph);
		h = murmur3_one_32(ph, h);
	}
	return fmix32(h);
}
inline bool polygons_equal(const std::vector<Vector2> &a, const Vector2 *b, size_t polygon_count) {
	if (a.size() != polygon_count * 3) {
		return false;
	}
	for (size_t i = 0; i < a.size(); i++) {
		if (a[i] != b[i]) {
			return false;
		}
	}
	return true;
}
struct PartitionCache {
	struct Entry {
		std::vector<Vector2> polygons;
		FlatPartition partitions;
	};
	std::unordered_map<uint32_t, Entry> slots;
	PartitionWork work;
	const FlatPartition &resolve(const Vector2 *triangles, size_t polygon_count) {
		uint32_t key = godot_hash(triangles, polygon_count);
		auto it = slots.find(key);
		if (it != slots.end() && polygons_equal(it->second.polygons, triangles, polygon_count)) {
			return it->second.partitions;
		}
		Entry &stored = slots[key];
		stored.polygons.assign(triangles, triangles + polygon_count * 3);
		partition_polygons(triangles, polygon_count, work, stored.partitions);
		return stored.partitions;
	}
};

struct PreparedDeck {
	const Vector3 *triangles = nullptr;
	std::vector<Vector2> projected;
	std::vector<double> values;
	std::vector<uint8_t> flats;
	explicit PreparedDeck(const std::vector<Vector3> &source) {
		triangles = source.data();
		size_t count = source.size() / 3;
		projected.resize(count * 6);
		values.resize(count * 5);
		flats.resize(count);
		for (size_t index = 0; index < count; index++) {
			const Vector3 *points = triangles + index * 3;
			flats[index] = (points[0].y == points[1].y && points[0].y == points[2].y) ? 1 : 0;
			Vector2 a = xz(points[0]);
			Vector2 b = xz(points[1]);
			Vector2 c = xz(points[2]);
			Vector2 ab = b - a;
			Vector2 bc = c - b;
			Vector2 ca = a - c;
			double area = (double)cross2(ab, c - a);
			double sign_value = area > 0 ? 1.0 : -1.0;
			double ab_limit = -0.000002 * (double)length2(ab);
			double bc_limit = -0.000002 * (double)length2(bc);
			double ca_limit = -0.000002 * (double)length2(ca);
			size_t vector_offset = index * 6;
			projected[vector_offset] = a;
			projected[vector_offset + 1] = b;
			projected[vector_offset + 2] = c;
			projected[vector_offset + 3] = ab;
			projected[vector_offset + 4] = bc;
			projected[vector_offset + 5] = ca;
			size_t scalar_offset = index * 5;
			values[scalar_offset] = area;
			values[scalar_offset + 1] = sign_value;
			values[scalar_offset + 2] = ab_limit;
			values[scalar_offset + 3] = bc_limit;
			values[scalar_offset + 4] = ca_limit;
		}
	}
};

struct TriangleBins {
	IndexLists bins;
	bool coarse = false;
};

// Any covering triangle answers true, so list order inside a bin is irrelevant.
inline bool deck_bin_covers(const Vector2 &point, double height, TriangleBins &bins, const PreparedDeck &prepared, int scale) {
	int32_t node = bins.bins.first(Key3{ (int32_t)floori((double)point.x * scale), (int32_t)floori((double)point.y * scale), scale });
	const std::vector<Vector2> &projected = prepared.projected;
	const std::vector<double> &values = prepared.values;
	for (; node >= 0; node = bins.bins.next[node]) {
		int32_t index = bins.bins.values[node];
		size_t scalar_offset = (size_t)index * 5;
		if (std::fabs(values[scalar_offset]) < 0.000000001) {
			continue;
		}
		size_t vector_offset = (size_t)index * 6;
		double sign_value = values[scalar_offset + 1];
		if ((double)cross2(projected[vector_offset + 3], point - projected[vector_offset]) * sign_value < values[scalar_offset + 2]) {
			continue;
		}
		if ((double)cross2(projected[vector_offset + 4], point - projected[vector_offset + 1]) * sign_value < values[scalar_offset + 3]) {
			continue;
		}
		if ((double)cross2(projected[vector_offset + 5], point - projected[vector_offset + 2]) * sign_value < values[scalar_offset + 4]) {
			continue;
		}
		const Vector3 *triangle = prepared.triangles + (size_t)index * 3;
		double surface_y = prepared.flats[index] ? (double)triangle[0].y : (double)patch_point(triangle, point).y;
		if (std::fabs(surface_y - height) < 0.03) {
			return true;
		}
	}
	return false;
}

inline bool deck_covers(const Vector2 &point, double height, TriangleBins &bins, const PreparedDeck &prepared) {
	return deck_bin_covers(point, height, bins, prepared, BIN_SCALE) || (bins.coarse && deck_bin_covers(point, height, bins, prepared, COARSE_BIN_SCALE));
}

inline bool deck_edge_is_internal(const Vector3 &a, const Vector3 &b, TriangleBins &bins, const PreparedDeck &prepared) {
	Vector3 midpoint = (a + b) * (float)0.5;
	Vector2 direction = normalized2(delta_xz(a, b));
	Vector2 across = Vector2(-direction.y, direction.x) * (float)0.00004;
	Vector2 center(midpoint.x, midpoint.z);
	return deck_covers(center + across, (double)midpoint.y, bins, prepared) && deck_covers(center - across, (double)midpoint.y, bins, prepared);
}

inline Key2 edge_key(const Vector3 &p) {
	return Key2{ (int32_t)roundi((double)p.x * 100000), (int32_t)roundi((double)p.z * 100000) };
}

inline void side_wall(std::vector<Vector3> &faces, const Vector3 &a, const Vector3 &b, const Vector3 &c, const Vector3 &d) {
	if (a == c && b == d) {
		return;
	}
	const Vector3 triangles[2][3] = { { a, b, c }, { b, d, c } };
	for (const auto &triangle : triangles) {
		if ((double)length_squared3(cross3(triangle[1] - triangle[0], triangle[2] - triangle[0])) < 0.000000000001) {
			continue;
		}
		faces.push_back(triangle[0]);
		faces.push_back(triangle[1]);
		faces.push_back(triangle[2]);
		faces.push_back(triangle[2]);
		faces.push_back(triangle[1]);
		faces.push_back(triangle[0]);
	}
}

// `edge_groups` (one group index per edge, non-decreasing) and `wall_ends`
// (one cumulative wall point count per group) are optional bookkeeping for the
// incremental resolver; they never change the emitted faces. Walls of one
// quantized segment key belong to the group of the key's first segment.
void append_numeric_deck_boundaries(const std::vector<Vector3> &points, const std::vector<double> &depths, const std::vector<Vector3> &triangles, std::vector<Vector3> &faces, const int32_t *edge_groups = nullptr, std::vector<int32_t> *wall_ends = nullptr) {
	TriangleBins triangle_bins;
	PreparedDeck prepared(triangles);
	const size_t triangle_count = triangles.size() / 3;
	triangle_bins.bins.heads.reserve(triangle_count * 2);
	triangle_bins.bins.values.reserve(triangle_count * 4);
	triangle_bins.bins.next.reserve(triangle_count * 4);
	for (size_t triangle_index = 0; triangle_index < triangle_count; triangle_index++) {
		const Vector3 *triangle = triangles.data() + triangle_index * 3;
		const Vector2 polygon[3] = { xz(triangle[0]), xz(triangle[1]), xz(triangle[2]) };
		Rect2 bounds = bounds_of(polygon, 3);
		double area = prepared.values[triangle_index * 5];
		if (std::fabs(area) < 0.000000001) {
			continue;
		}
		size_t vector_offset = triangle_index * 6;
		Vector3 lengths(length2(prepared.projected[vector_offset + 3]), length2(prepared.projected[vector_offset + 4]), length2(prepared.projected[vector_offset + 5]));
		double longest = maxd((double)lengths.x, maxd((double)lengths.y, (double)lengths.z));
		double margin = .00005 * ((double)lengths.x + (double)lengths.y + (double)lengths.z) * longest / std::fabs(area) + CANDIDATE_PAD;
		Rect2 expanded = bounds.grow((float)margin);
		int scale = maxd((double)expanded.size.x, (double)expanded.size.y) < DENSE_LIMIT ? BIN_SCALE : COARSE_BIN_SCALE;
		if (scale == COARSE_BIN_SCALE) {
			triangle_bins.coarse = true;
		}
		Vector2 bounds_end = bounds.get_end();
		Vector2 expanded_end = expanded.get_end();
		int64_t fine_x_low = floori((double)expanded.position.x * scale);
		int64_t fine_x_high = floori((double)expanded_end.x * scale);
		int64_t fine_z_low = floori((double)expanded.position.y * scale);
		int64_t fine_z_high = floori((double)expanded_end.y * scale);
		for (int64_t x = floori((double)bounds.position.x); x <= floori((double)bounds_end.x); x++) {
			for (int64_t z = floori((double)bounds.position.y); z <= floori((double)bounds_end.y); z++) {
				int64_t x_begin = x * scale > fine_x_low ? x * scale : fine_x_low;
				int64_t x_end = (x + 1) * scale - 1 < fine_x_high ? (x + 1) * scale - 1 : fine_x_high;
				int64_t z_begin = z * scale > fine_z_low ? z * scale : fine_z_low;
				int64_t z_end = (z + 1) * scale - 1 < fine_z_high ? (z + 1) * scale - 1 : fine_z_high;
				for (int64_t fine_x = x_begin; fine_x <= x_end; fine_x++) {
					for (int64_t fine_z = z_begin; fine_z <= z_end; fine_z++) {
						triangle_bins.bins.add(Key3{ (int32_t)fine_x, (int32_t)fine_z, scale }, (int32_t)triangle_index);
					}
				}
			}
		}
	}
	SCDD_STAGE("deck-triangle-bins");
	// Per-cell quantized vertex de-duplication: the last value written wins.
	FlatMap<Key4, Vector2> vertices;
	vertices.reserve(depths.size() / 2 + 64);
	for (size_t index = 0; index < depths.size(); index++) {
		for (int side = 0; side < 2; side++) {
			const Vector3 &p = points[index * 2 + side];
			Key2 key = edge_key(p);
			bool inserted = false;
			vertices.get(Key4{ (int32_t)floori((double)p.x), (int32_t)floori((double)p.z), key.a, key.b }, Vector2(), inserted) = Vector2(p.x, p.z);
		}
	}
	// Candidate order inside a fine bucket only feeds sorted cut parameters.
	IndexLists fine_vertices;
	std::vector<Vector2> retained;
	retained.reserve(vertices.size());
	const bool coarse_vertices = triangle_bins.coarse;
	fine_vertices.heads.reserve(vertices.size() * (coarse_vertices ? 2 : 1));
	vertices.for_each([&](const Key4 &, const Vector2 &p) {
		int32_t retained_index = (int32_t)retained.size();
		retained.push_back(p);
		fine_vertices.add(Key3{ (int32_t)floori((double)p.x * BIN_SCALE), (int32_t)floori((double)p.y * BIN_SCALE), BIN_SCALE }, retained_index);
		if (coarse_vertices) {
			fine_vertices.add(Key3{ (int32_t)floori((double)p.x * COARSE_BIN_SCALE), (int32_t)floori((double)p.y * COARSE_BIN_SCALE), COARSE_BIN_SCALE }, retained_index);
		}
	});
	SCDD_STAGE("deck-vertices");
	// Segments grouped by quantized key in first-appearance order; matches of a
	// key keep their insertion order through a head/tail linked list.
	FlatMap<Key4, int32_t> segment_index;
	segment_index.reserve(depths.size());
	std::vector<int32_t> match_head;
	std::vector<int32_t> match_tail;
	std::vector<uint8_t> match_count;
	std::vector<int32_t> match_next;
	std::vector<Vector3> segment_points;
	std::vector<double> segment_depths;
	std::vector<int32_t> segment_groups;
	match_head.reserve(depths.size());
	match_tail.reserve(depths.size());
	match_count.reserve(depths.size());
	match_next.reserve(depths.size());
	segment_points.reserve(depths.size() * 2);
	segment_depths.reserve(depths.size());
	std::vector<double> cuts;
	const scdd::SortArray<double, Less, true> cut_sorter;
	for (size_t index = 0; index < depths.size(); index++) {
		const Vector3 a = points[index * 2];
		const Vector3 b = points[index * 2 + 1];
		const double depth = depths[index];
		Vector2 start(a.x, a.z);
		Vector2 delta = delta_xz(a, b);
		double length_squared = (double)length_squared2(delta);
		if (length_squared < 0.0000000001) {
			continue;
		}
		// The GDScript cuts cache is output-neutral: cuts depend only on the
		// projected end points and the retained vertices, so recompute them.
		cuts.clear();
		cuts.push_back(0.0);
		cuts.push_back(1.0);
		double cross_limit = 0.000001 * std::sqrt(length_squared);
		int scale = (coarse_vertices && maxd(std::fabs((double)delta.x), std::fabs((double)delta.y)) >= DENSE_LIMIT) ? COARSE_BIN_SCALE : BIN_SCALE;
		int64_t x_low = floori((mind((double)a.x, (double)b.x) - CANDIDATE_PAD) * scale);
		int64_t x_high = floori((maxd((double)a.x, (double)b.x) + CANDIDATE_PAD) * scale);
		int64_t z_low = floori((mind((double)a.z, (double)b.z) - CANDIDATE_PAD) * scale);
		int64_t z_high = floori((maxd((double)a.z, (double)b.z) + CANDIDATE_PAD) * scale);
		for (int64_t x = x_low; x <= x_high; x++) {
			for (int64_t z = z_low; z <= z_high; z++) {
				for (int32_t node = fine_vertices.first(Key3{ (int32_t)x, (int32_t)z, scale }); node >= 0; node = fine_vertices.next[node]) {
					const Vector2 &p = retained[fine_vertices.values[node]];
					double t = (double)dot2(p - start, delta) / length_squared;
					if (t > 0.00001 && t < 0.99999 && std::fabs((double)cross2(delta, p - start)) < cross_limit) {
						cuts.push_back(t);
					}
				}
			}
		}
		cut_sorter.sort(cuts.data(), (int64_t)cuts.size());
		for (size_t i = 0; i + 1 < cuts.size(); i++) {
			if (cuts[i + 1] - cuts[i] < 0.000001) {
				continue;
			}
			Vector3 p = lerp3(a, b, (float)cuts[i]);
			Vector3 q = lerp3(a, b, (float)cuts[i + 1]);
			Key2 pk = edge_key(p);
			Key2 qk = edge_key(q);
			if (pk == qk) {
				continue;
			}
			if (pk.a > qk.a || (pk.a == qk.a && pk.b > qk.b)) {
				std::swap(p, q);
				std::swap(pk, qk);
			}
			int32_t segment = (int32_t)segment_depths.size();
			bool inserted = false;
			int32_t &key_slot = segment_index.get(Key4{ pk.a, pk.b, qk.a, qk.b }, -1, inserted);
			if (inserted) {
				key_slot = (int32_t)match_head.size();
				match_head.push_back(segment);
				match_tail.push_back(segment);
				match_count.push_back(1);
			} else {
				match_next[match_tail[key_slot]] = segment;
				match_tail[key_slot] = segment;
				if (match_count[key_slot] < 3) {
					match_count[key_slot]++;
				}
			}
			match_next.push_back(-1);
			segment_points.push_back(p);
			segment_points.push_back(q);
			segment_depths.push_back(depth);
			if (edge_groups) {
				segment_groups.push_back(edge_groups[index]);
			}
		}
	}
	SCDD_STAGE("deck-segments");
	const size_t wall_start = faces.size();
	size_t wall_group = 0;
	for (size_t key = 0; key < match_head.size(); key++) {
		if (edge_groups && wall_ends) {
			const size_t owner = (size_t)segment_groups[match_head[key]];
			while (wall_group < owner && wall_group < wall_ends->size()) {
				(*wall_ends)[wall_group++] = (int32_t)(faces.size() - wall_start);
			}
		}
		if (match_count[key] == 1) {
			int32_t index = match_head[key];
			const Vector3 &a = segment_points[(size_t)index * 2];
			const Vector3 &b = segment_points[(size_t)index * 2 + 1];
			double depth = segment_depths[index];
			if (deck_edge_is_internal(a, b, triangle_bins, prepared)) {
				continue;
			}
			side_wall(faces, a, b, a + down_by(depth), b + down_by(depth));
		} else if (match_count[key] == 2) {
			int32_t first = match_head[key];
			int32_t second = match_next[first];
			const Vector3 &first_a = segment_points[(size_t)first * 2];
			const Vector3 &first_b = segment_points[(size_t)first * 2 + 1];
			const Vector3 &second_a = segment_points[(size_t)second * 2];
			const Vector3 &second_b = segment_points[(size_t)second * 2 + 1];
			double first_depth = segment_depths[first];
			double second_depth = segment_depths[second];
			if (maxd(std::fabs((double)first_a.y - (double)second_a.y), std::fabs((double)first_b.y - (double)second_b.y)) < 0.03) {
				side_wall(faces, first_a, first_b, second_a, second_b);
				side_wall(faces, first_a + down_by(first_depth), first_b + down_by(first_depth), second_a + down_by(second_depth), second_b + down_by(second_depth));
			} else {
				for (int32_t index = first; index >= 0; index = match_next[index]) {
					const Vector3 &a = segment_points[(size_t)index * 2];
					const Vector3 &b = segment_points[(size_t)index * 2 + 1];
					double depth = segment_depths[index];
					side_wall(faces, a, b, a + down_by(depth), b + down_by(depth));
				}
			}
		}
	}
	if (wall_ends) {
		while (wall_group < wall_ends->size()) {
			(*wall_ends)[wall_group++] = (int32_t)(faces.size() - wall_start);
		}
	}
	SCDD_STAGE("deck-walls");
}

PackedVector3Array to_packed(const std::vector<Vector3> &source) {
	PackedVector3Array result;
	result.resize((int64_t)source.size());
	if (!source.empty()) {
		std::memcpy(result.ptrw(), source.data(), source.size() * sizeof(Vector3));
	}
	return result;
}

PackedInt32Array to_packed_int(const std::vector<int32_t> &source) {
	PackedInt32Array result;
	result.resize((int64_t)source.size());
	if (!source.empty()) {
		std::memcpy(result.ptrw(), source.data(), source.size() * sizeof(int32_t));
	}
	return result;
}

PackedFloat64Array to_packed_double(const std::vector<double> &source) {
	PackedFloat64Array result;
	result.resize((int64_t)source.size());
	if (!source.empty()) {
		std::memcpy(result.ptrw(), source.data(), source.size() * sizeof(double));
	}
	return result;
}

// Deck edges in resolver order: (a,b), (b,c), (c,a) of every deck triangle,
// each with its triangle's depth and owning group.
void deck_edges(const Vector3 *deck, const double *deck_depths, size_t triangle_count, const int32_t *deck_ends, size_t group_count,
		std::vector<Vector3> &points, std::vector<double> &depths, std::vector<int32_t> &edge_groups) {
	points.clear();
	depths.clear();
	edge_groups.clear();
	points.reserve(triangle_count * 6);
	depths.reserve(triangle_count * 3);
	edge_groups.reserve(triangle_count * 3);
	size_t group = 0;
	for (size_t t = 0; t < triangle_count; t++) {
		while (group < group_count && (size_t)deck_ends[group] <= t * 3) {
			group++;
		}
		const Vector3 &a = deck[t * 3];
		const Vector3 &b = deck[t * 3 + 1];
		const Vector3 &c = deck[t * 3 + 2];
		const Vector3 edge_points[6] = { a, b, b, c, c, a };
		for (int i = 0; i < 6; i++) {
			points.push_back(edge_points[i]);
		}
		for (int i = 0; i < 3; i++) {
			depths.push_back(deck_depths[t]);
			edge_groups.push_back((int32_t)group);
		}
	}
}

} // namespace

class SCDDNetworkPhysics : public RefCounted {
	GDCLASS(SCDDNetworkPhysics, RefCounted)
protected:
	static void _bind_methods() {
		ClassDB::bind_static_method("SCDDNetworkPhysics", D_METHOD("available"), &SCDDNetworkPhysics::available);
		ClassDB::bind_static_method("SCDDNetworkPhysics", D_METHOD("resolve_packed", "cells", "groups", "roles", "depths", "triangles", "obstacles"), &SCDDNetworkPhysics::resolve_packed);
		ClassDB::bind_static_method("SCDDNetworkPhysics", D_METHOD("resolve_detailed", "cells", "groups", "roles", "depths", "triangles", "with_walls"), &SCDDNetworkPhysics::resolve_detailed);
		ClassDB::bind_static_method("SCDDNetworkPhysics", D_METHOD("resolve_boundaries", "deck", "deck_depths", "deck_ends"), &SCDDNetworkPhysics::resolve_boundaries);
		ClassDB::bind_static_method("SCDDNetworkPhysics", D_METHOD("diff_groups", "old_cells", "old_groups", "old_roles", "old_depths", "old_triangles", "cells", "groups", "roles", "depths", "triangles"), &SCDDNetworkPhysics::diff_groups);
		ClassDB::bind_static_method("SCDDNetworkPhysics", D_METHOD("splice_vector3", "sources", "runs"), &SCDDNetworkPhysics::splice_vector3);
		ClassDB::bind_static_method("SCDDNetworkPhysics", D_METHOD("splice_float64", "sources", "runs"), &SCDDNetworkPhysics::splice_float64);
	}

public:
	static bool available() { return true; }

	static Dictionary resolve_packed(const PackedInt32Array &cells, const PackedInt32Array &groups, const PackedInt32Array &roles, const PackedFloat64Array &depths, const PackedVector3Array &triangles, const PackedVector3Array &obstacles) {
		Dictionary result;
		const int64_t count = depths.size();
		ERR_FAIL_COND_V_MSG(cells.size() != count * 2 || groups.size() != count || roles.size() != count || triangles.size() != count * 3, result, "SCDDNetworkPhysics.resolve_packed: packed patch arrays disagree on the patch count.");
		SCDD_STAGE("");
		const int32_t *cell_ptr = cells.ptr();
		const int32_t *group_ptr = groups.ptr();
		const int32_t *role_ptr = roles.ptr();
		const double *depth_ptr = depths.ptr();
		const Vector3 *triangle_ptr = triangles.ptr();

		// Groups keyed by (cell, group) in first-appearance order.
		FlatMap<Key3, int32_t> group_index;
		group_index.reserve((size_t)count / 16 + 64);
		std::vector<std::vector<int32_t>> group_members;
		for (int64_t index = 0; index < count; index++) {
			bool inserted = false;
			int32_t &slot = group_index.get(Key3{ cell_ptr[index * 2], cell_ptr[index * 2 + 1], group_ptr[index] }, -1, inserted);
			if (inserted) {
				slot = (int32_t)group_members.size();
				group_members.emplace_back();
			}
			group_members[slot].push_back((int32_t)index);
		}
		SCDD_STAGE("group");

		std::vector<Vector3> floor;
		floor.reserve((size_t)count * 3);
		std::vector<Vector3> obstacle_faces(obstacles.ptr(), obstacles.ptr() + obstacles.size());
		obstacle_faces.reserve(obstacles.size() + (size_t)count * 6);
		std::vector<Vector3> deck_points;
		std::vector<double> deck_depths;
		std::vector<Vector3> deck_triangles;
		deck_points.reserve((size_t)count * 6);
		deck_depths.reserve((size_t)count * 3);
		deck_triangles.reserve((size_t)count * 3);
		PartitionCache partition_cache;
		scdd::SortArray<int32_t, RoleDescending, true> role_sorter;
		role_sorter.compare.roles = role_ptr;
		std::vector<Vector2> local;
		for (std::vector<int32_t> &patches : group_members) {
			role_sorter.sort(patches.data(), (int64_t)patches.size());
			// Work near the origin like the GDScript resolver.
			Vector2 origin((float)cell_ptr[patches[0] * 2], (float)cell_ptr[patches[0] * 2 + 1]);
			local.clear();
			for (int32_t patch : patches) {
				const Vector3 *points = triangle_ptr + (size_t)patch * 3;
				local.push_back(xz(points[0]) - origin);
				local.push_back(xz(points[1]) - origin);
				local.push_back(xz(points[2]) - origin);
			}
			const FlatPartition &partitions = partition_cache.resolve(local.data(), patches.size());
			for (size_t index = 0; index < patches.size(); index++) {
				const int32_t patch = patches[index];
				const Vector3 *triangle = triangle_ptr + (size_t)patch * 3;
				const double depth = depth_ptr[patch];
				for (uint32_t piece = partitions.polygon_begin[index]; piece < partitions.polygon_begin[index + 1]; piece++) {
					const Vector2 *piece_points = partitions.points.data() + partitions.piece_begin[piece];
					const size_t piece_size = partitions.piece_begin[piece + 1] - partitions.piece_begin[piece];
					for (size_t i = 1; i + 1 < piece_size; i++) {
						Vector3 a = patch_point(triangle, piece_points[0] + origin);
						Vector3 b = patch_point(triangle, piece_points[i] + origin);
						Vector3 c = patch_point(triangle, piece_points[i + 1] + origin);
						double winding = (double)cross3(b - a, c - a).y;
						if (std::fabs(winding) < 0.000000001) {
							continue;
						}
						if (winding > 0) {
							std::swap(b, c);
						}
						floor.push_back(a);
						floor.push_back(b);
						floor.push_back(c);
						if (depth > 0) {
							deck_triangles.push_back(a);
							deck_triangles.push_back(b);
							deck_triangles.push_back(c);
							Vector3 down = down_by(depth);
							obstacle_faces.push_back(c + down);
							obstacle_faces.push_back(b + down);
							obstacle_faces.push_back(a + down);
							deck_points.push_back(a);
							deck_points.push_back(b);
							deck_points.push_back(b);
							deck_points.push_back(c);
							deck_points.push_back(c);
							deck_points.push_back(a);
							deck_depths.push_back(depth);
							deck_depths.push_back(depth);
							deck_depths.push_back(depth);
						}
					}
				}
			}
		}
		SCDD_STAGE("floor-partitions");
		append_numeric_deck_boundaries(deck_points, deck_depths, deck_triangles, obstacle_faces);
		result["physical_floor_faces"] = to_packed(floor);
		result["physical_obstacle_faces"] = to_packed(obstacle_faces);
		SCDD_STAGE("pack-output");
		return result;
	}

	// Per-group results of the same resolution, for exact incremental reuse:
	// group keys in first-appearance order, the first/last input patch of each
	// group, its floor, deck-bottom and deck triangles (with one depth per deck
	// triangle), deck XZ bounds and, optionally, the walls owned by each group.
	// Concatenating the per-group blocks reproduces resolve_packed exactly:
	// floor = floor; obstacles = inputs + bottoms + walls.
	static Dictionary resolve_detailed(const PackedInt32Array &cells, const PackedInt32Array &groups, const PackedInt32Array &roles, const PackedFloat64Array &depths, const PackedVector3Array &triangles, bool with_walls) {
		Dictionary result;
		const int64_t count = depths.size();
		ERR_FAIL_COND_V_MSG(cells.size() != count * 2 || groups.size() != count || roles.size() != count || triangles.size() != count * 3, result, "SCDDNetworkPhysics.resolve_detailed: packed patch arrays disagree on the patch count.");
		const int32_t *cell_ptr = cells.ptr();
		const int32_t *group_ptr = groups.ptr();
		const int32_t *role_ptr = roles.ptr();
		const double *depth_ptr = depths.ptr();
		const Vector3 *triangle_ptr = triangles.ptr();
		FlatMap<Key3, int32_t> group_index;
		group_index.reserve((size_t)count / 16 + 64);
		std::vector<std::vector<int32_t>> group_members;
		std::vector<int32_t> keys;
		for (int64_t index = 0; index < count; index++) {
			bool inserted = false;
			Key3 key{ cell_ptr[index * 2], cell_ptr[index * 2 + 1], group_ptr[index] };
			int32_t &slot = group_index.get(key, -1, inserted);
			if (inserted) {
				slot = (int32_t)group_members.size();
				group_members.emplace_back();
				keys.push_back(key.a);
				keys.push_back(key.b);
				keys.push_back(key.c);
			}
			group_members[slot].push_back((int32_t)index);
		}
		const size_t group_count = group_members.size();
		std::vector<int32_t> first(group_count), last(group_count);
		std::vector<Vector3> floor, bottoms, deck;
		std::vector<double> deck_depths, bounds(group_count * 4);
		std::vector<int32_t> floor_ends(group_count), bottom_ends(group_count);
		floor.reserve((size_t)count * 3);
		PartitionCache partition_cache;
		scdd::SortArray<int32_t, RoleDescending, true> role_sorter;
		role_sorter.compare.roles = role_ptr;
		std::vector<Vector2> local;
		for (size_t g = 0; g < group_count; g++) {
			std::vector<int32_t> &patches = group_members[g];
			first[g] = patches.front();
			last[g] = patches.back();
			role_sorter.sort(patches.data(), (int64_t)patches.size());
			Vector2 origin((float)cell_ptr[patches[0] * 2], (float)cell_ptr[patches[0] * 2 + 1]);
			local.clear();
			for (int32_t patch : patches) {
				const Vector3 *points = triangle_ptr + (size_t)patch * 3;
				local.push_back(xz(points[0]) - origin);
				local.push_back(xz(points[1]) - origin);
				local.push_back(xz(points[2]) - origin);
			}
			const FlatPartition &partitions = partition_cache.resolve(local.data(), patches.size());
			const size_t deck_begin = deck.size();
			for (size_t index = 0; index < patches.size(); index++) {
				const int32_t patch = patches[index];
				const Vector3 *triangle = triangle_ptr + (size_t)patch * 3;
				const double depth = depth_ptr[patch];
				for (uint32_t piece = partitions.polygon_begin[index]; piece < partitions.polygon_begin[index + 1]; piece++) {
					const Vector2 *piece_points = partitions.points.data() + partitions.piece_begin[piece];
					const size_t piece_size = partitions.piece_begin[piece + 1] - partitions.piece_begin[piece];
					for (size_t i = 1; i + 1 < piece_size; i++) {
						Vector3 a = patch_point(triangle, piece_points[0] + origin);
						Vector3 b = patch_point(triangle, piece_points[i] + origin);
						Vector3 c = patch_point(triangle, piece_points[i + 1] + origin);
						double winding = (double)cross3(b - a, c - a).y;
						if (std::fabs(winding) < 0.000000001) {
							continue;
						}
						if (winding > 0) {
							std::swap(b, c);
						}
						floor.push_back(a);
						floor.push_back(b);
						floor.push_back(c);
						if (depth > 0) {
							deck.push_back(a);
							deck.push_back(b);
							deck.push_back(c);
							deck_depths.push_back(depth);
							Vector3 down = down_by(depth);
							bottoms.push_back(c + down);
							bottoms.push_back(b + down);
							bottoms.push_back(a + down);
						}
					}
				}
			}
			floor_ends[g] = (int32_t)floor.size();
			bottom_ends[g] = (int32_t)bottoms.size();
			double *box = bounds.data() + g * 4;
			if (deck.size() > deck_begin) {
				box[0] = box[2] = (double)deck[deck_begin].x;
				box[1] = box[3] = (double)deck[deck_begin].z;
				for (size_t i = deck_begin; i < deck.size(); i++) {
					box[0] = mind(box[0], (double)deck[i].x);
					box[1] = mind(box[1], (double)deck[i].z);
					box[2] = maxd(box[2], (double)deck[i].x);
					box[3] = maxd(box[3], (double)deck[i].z);
				}
			} else {
				box[0] = box[1] = box[2] = box[3] = 0.0;
			}
		}
		std::vector<Vector3> walls;
		std::vector<int32_t> wall_ends(group_count, 0);
		if (with_walls) {
			std::vector<Vector3> edge_points;
			std::vector<double> edge_depths;
			std::vector<int32_t> edge_groups;
			deck_edges(deck.data(), deck_depths.data(), deck_depths.size(), bottom_ends.data(), group_count, edge_points, edge_depths, edge_groups);
			append_numeric_deck_boundaries(edge_points, edge_depths, deck, walls, edge_groups.data(), &wall_ends);
		}
		result["keys"] = to_packed_int(keys);
		result["first"] = to_packed_int(first);
		result["last"] = to_packed_int(last);
		result["bounds"] = to_packed_double(bounds);
		result["floor"] = to_packed(floor);
		result["floor_ends"] = to_packed_int(floor_ends);
		result["bottoms"] = to_packed(bottoms);
		result["bottom_ends"] = to_packed_int(bottom_ends);
		result["deck"] = to_packed(deck);
		result["deck_depths"] = to_packed_double(deck_depths);
		result["walls"] = to_packed(walls);
		result["wall_ends"] = to_packed_int(wall_ends);
		return result;
	}

	// Deck boundary walls of an ordered subset of groups. `deck_ends` holds the
	// cumulative deck point count of each group; walls are attributed as above.
	static Dictionary resolve_boundaries(const PackedVector3Array &deck, const PackedFloat64Array &deck_depths, const PackedInt32Array &deck_ends) {
		Dictionary result;
		ERR_FAIL_COND_V_MSG(deck.size() != deck_depths.size() * 3 || (deck_ends.size() > 0 && deck_ends[deck_ends.size() - 1] != deck.size()), result, "SCDDNetworkPhysics.resolve_boundaries: deck arrays disagree.");
		std::vector<Vector3> triangles(deck.ptr(), deck.ptr() + deck.size());
		std::vector<Vector3> edge_points;
		std::vector<double> edge_depths;
		std::vector<int32_t> edge_groups;
		deck_edges(deck.ptr(), deck_depths.ptr(), (size_t)deck_depths.size(), deck_ends.ptr(), (size_t)deck_ends.size(), edge_points, edge_depths, edge_groups);
		std::vector<Vector3> walls;
		std::vector<int32_t> wall_ends((size_t)deck_ends.size(), 0);
		append_numeric_deck_boundaries(edge_points, edge_depths, triangles, walls, edge_groups.data(), &wall_ends);
		result["walls"] = to_packed(walls);
		result["wall_ends"] = to_packed_int(wall_ends);
		return result;
	}

	// Compares two patch sets group by group. Returns the new group keys in
	// first-appearance order, a changed flag per new group (its ordered patch
	// sequence differs from the old group with the same key, or is new), the
	// old keys that disappeared and the new patches of every changed group in
	// input order. Equality is exact: integer and IEEE bit-pattern comparison.
	static Dictionary diff_groups(const PackedInt32Array &old_cells, const PackedInt32Array &old_groups, const PackedInt32Array &old_roles, const PackedFloat64Array &old_depths, const PackedVector3Array &old_triangles,
			const PackedInt32Array &cells, const PackedInt32Array &groups, const PackedInt32Array &roles, const PackedFloat64Array &depths, const PackedVector3Array &triangles) {
		Dictionary result;
		const int64_t old_count = old_depths.size();
		const int64_t count = depths.size();
		ERR_FAIL_COND_V_MSG(old_cells.size() != old_count * 2 || old_groups.size() != old_count || old_roles.size() != old_count || old_triangles.size() != old_count * 3, result, "SCDDNetworkPhysics.diff_groups: old patch arrays disagree.");
		ERR_FAIL_COND_V_MSG(cells.size() != count * 2 || groups.size() != count || roles.size() != count || triangles.size() != count * 3, result, "SCDDNetworkPhysics.diff_groups: patch arrays disagree.");
		struct Side {
			FlatMap<Key3, int32_t> index;
			std::vector<Key3> keys;
			std::vector<std::vector<int32_t>> members;
		};
		auto collect = [](Side &side, const int32_t *cell_ptr, const int32_t *group_ptr, int64_t n) {
			side.index.reserve((size_t)n / 16 + 64);
			for (int64_t i = 0; i < n; i++) {
				bool inserted = false;
				Key3 key{ cell_ptr[i * 2], cell_ptr[i * 2 + 1], group_ptr[i] };
				int32_t &slot = side.index.get(key, -1, inserted);
				if (inserted) {
					slot = (int32_t)side.keys.size();
					side.keys.push_back(key);
					side.members.emplace_back();
				}
				side.members[slot].push_back((int32_t)i);
			}
		};
		Side before, after;
		collect(before, old_cells.ptr(), old_groups.ptr(), old_count);
		collect(after, cells.ptr(), groups.ptr(), count);
		auto same_bits = [](const void *a, const void *b, size_t size) { return std::memcmp(a, b, size) == 0; };
		std::vector<int32_t> keys;
		std::vector<uint8_t> changed(after.keys.size(), 0);
		std::vector<bool> kept(before.keys.size(), false);
		std::vector<int32_t> subset;
		for (size_t g = 0; g < after.keys.size(); g++) {
			const Key3 &key = after.keys[g];
			keys.push_back(key.a);
			keys.push_back(key.b);
			keys.push_back(key.c);
			int32_t *old_slot = before.index.find(key);
			bool same = old_slot != nullptr && before.members[*old_slot].size() == after.members[g].size();
			if (old_slot) {
				kept[*old_slot] = true;
			}
			if (same) {
				const std::vector<int32_t> &a = before.members[*old_slot];
				const std::vector<int32_t> &b = after.members[g];
				for (size_t i = 0; same && i < a.size(); i++) {
					same = old_roles[a[i]] == roles[b[i]] && same_bits(&old_depths.ptr()[a[i]], &depths.ptr()[b[i]], sizeof(double)) && same_bits(old_triangles.ptr() + (size_t)a[i] * 3, triangles.ptr() + (size_t)b[i] * 3, sizeof(Vector3) * 3);
				}
			}
			if (!same) {
				changed[g] = 1;
				subset.insert(subset.end(), after.members[g].begin(), after.members[g].end());
			}
		}
		std::vector<int32_t> removed;
		for (size_t g = 0; g < before.keys.size(); g++) {
			if (!kept[g]) {
				removed.push_back(before.keys[g].a);
				removed.push_back(before.keys[g].b);
				removed.push_back(before.keys[g].c);
			}
		}
		const scdd::SortArray<int32_t, Less, true> int_sorter;
		int_sorter.sort(subset.data(), (int64_t)subset.size());
		PackedInt32Array subset_cells, subset_groups, subset_roles;
		PackedFloat64Array subset_depths;
		PackedVector3Array subset_triangles;
		subset_cells.resize((int64_t)subset.size() * 2);
		subset_groups.resize((int64_t)subset.size());
		subset_roles.resize((int64_t)subset.size());
		subset_depths.resize((int64_t)subset.size());
		subset_triangles.resize((int64_t)subset.size() * 3);
		for (size_t i = 0; i < subset.size(); i++) {
			const int32_t p = subset[i];
			subset_cells.set((int64_t)i * 2, cells[(int64_t)p * 2]);
			subset_cells.set((int64_t)i * 2 + 1, cells[(int64_t)p * 2 + 1]);
			subset_groups.set((int64_t)i, groups[p]);
			subset_roles.set((int64_t)i, roles[p]);
			subset_depths.set((int64_t)i, depths[p]);
			for (int k = 0; k < 3; k++) {
				subset_triangles.set((int64_t)i * 3 + k, triangles[(int64_t)p * 3 + k]);
			}
		}
		PackedByteArray changed_flags;
		changed_flags.resize((int64_t)changed.size());
		if (!changed.empty()) {
			std::memcpy(changed_flags.ptrw(), changed.data(), changed.size());
		}
		result["keys"] = to_packed_int(keys);
		result["changed"] = changed_flags;
		result["removed"] = to_packed_int(removed);
		Array subset_arrays;
		subset_arrays.push_back(subset_cells);
		subset_arrays.push_back(subset_groups);
		subset_arrays.push_back(subset_roles);
		subset_arrays.push_back(subset_depths);
		subset_arrays.push_back(subset_triangles);
		result["subset"] = subset_arrays;
		return result;
	}

	// Concatenates [source, begin, end) runs of packed sources into one array.
	static PackedVector3Array splice_vector3(const Array &sources, const PackedInt32Array &runs) {
		PackedVector3Array result;
		ERR_FAIL_COND_V_MSG(runs.size() % 3 != 0, result, "SCDDNetworkPhysics.splice_vector3: runs hold three integers each.");
		std::vector<PackedVector3Array> arrays;
		for (int64_t i = 0; i < sources.size(); i++) {
			arrays.push_back(sources[i]);
		}
		int64_t total = 0;
		for (int64_t r = 0; r < runs.size(); r += 3) {
			ERR_FAIL_COND_V(runs[r] < 0 || runs[r] >= (int64_t)arrays.size() || runs[r + 1] < 0 || runs[r + 2] < runs[r + 1] || runs[r + 2] > arrays[runs[r]].size(), PackedVector3Array());
			total += runs[r + 2] - runs[r + 1];
		}
		result.resize(total);
		Vector3 *out = result.ptrw();
		for (int64_t r = 0; r < runs.size(); r += 3) {
			const int64_t length = runs[r + 2] - runs[r + 1];
			if (length > 0) {
				std::memcpy(out, arrays[runs[r]].ptr() + runs[r + 1], (size_t)length * sizeof(Vector3));
				out += length;
			}
		}
		return result;
	}

	static PackedFloat64Array splice_float64(const Array &sources, const PackedInt32Array &runs) {
		PackedFloat64Array result;
		ERR_FAIL_COND_V_MSG(runs.size() % 3 != 0, result, "SCDDNetworkPhysics.splice_float64: runs hold three integers each.");
		std::vector<PackedFloat64Array> arrays;
		for (int64_t i = 0; i < sources.size(); i++) {
			arrays.push_back(sources[i]);
		}
		int64_t total = 0;
		for (int64_t r = 0; r < runs.size(); r += 3) {
			ERR_FAIL_COND_V(runs[r] < 0 || runs[r] >= (int64_t)arrays.size() || runs[r + 1] < 0 || runs[r + 2] < runs[r + 1] || runs[r + 2] > arrays[runs[r]].size(), PackedFloat64Array());
			total += runs[r + 2] - runs[r + 1];
		}
		result.resize(total);
		double *out = result.ptrw();
		for (int64_t r = 0; r < runs.size(); r += 3) {
			const int64_t length = runs[r + 2] - runs[r + 1];
			if (length > 0) {
				std::memcpy(out, arrays[runs[r]].ptr() + runs[r + 1], (size_t)length * sizeof(double));
				out += length;
			}
		}
		return result;
	}
};

static void initialize_geometry(ModuleInitializationLevel level) {
	if (level == MODULE_INITIALIZATION_LEVEL_SCENE) {
		ClassDB::register_class<SCDDNetworkPhysics>();
	}
}

extern "C" GDExtensionBool GDE_EXPORT scdd_geometry_init(GDExtensionInterfaceGetProcAddress get_proc_address, GDExtensionClassLibraryPtr library, GDExtensionInitialization *initialization) {
	GDExtensionBinding::InitObject init(get_proc_address, library, initialization);
	init.register_initializer(initialize_geometry);
	init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init.init();
}
