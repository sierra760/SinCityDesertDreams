# SPDX-FileCopyrightText: 2026 Bristlecone Artists LLC
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and LICENSING.md in the repository root.

## Presentation settings only. No city data, gameplay or UI scaling changes.
extends RefCounted

static func scaled_size(native_size: Vector2i, percent: int) -> Vector2i:
	var scale := percent if percent in [50,75,100] else 100
	return Vector2i(maxi(1,roundi(native_size.x * scale / 100.0)), maxi(1,roundi(native_size.y * scale / 100.0)))

static func apply(view: Node, quality: String) -> void:
	if view.viewport == null: return
	var balanced := quality == "balanced"
	var performance := quality == "performance"
	var mobile := RenderingServer.get_current_rendering_method() == "mobile"
	view.viewport.msaa_3d = Viewport.MSAA_2X if balanced or performance else Viewport.MSAA_4X
	apply_mesh_detail(view, quality)
	# Night mode scales the backend's lighting; 1.0 by day.
	var night: Node = view.get("night")
	var sun_scale: float = night.sun_scale() if night != null else 1.0
	var ambient_scale: float = night.ambient_scale() if night != null else 1.0
	for child: Node in view.world.get_children():
		if child is DirectionalLight3D:
			child.shadow_enabled = not performance
			child.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if balanced and not mobile and is_instance_valid(view.exploration_camera()) else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			child.directional_shadow_blend_splits = true
			child.directional_shadow_max_distance = 320.0 if balanced else 400.0
			child.light_energy = (0.7 if mobile else 0.325) * sun_scale
		elif child is WorldEnvironment:
			child.environment.ambient_light_energy = (0.4 if mobile else 0.195) * ambient_scale
	var explore_camera: Camera3D = view.exploration_camera()
	if is_instance_valid(explore_camera) and explore_camera.environment != null:
		explore_camera.environment.ambient_light_energy = (0.4 if mobile else 0.195) * ambient_scale
	apply_shadow_focus(view)


## Explore targets at most one native pixel of mesh detail error, even when
## the 3D image is rendered below native resolution. Build keeps its own budget.
static func apply_mesh_detail(view: Node, quality: String) -> void:
	var threshold := 4.0 if quality == "performance" else 2.0 if quality == "balanced" else 1.0
	if is_instance_valid(view.exploration_camera()):
		threshold = (1.0 if quality == "performance" else 0.5 if quality == "balanced" else 0.25) * view.render_scale / 100.0
	view.viewport.mesh_lod_threshold = threshold


static func apply_shadow_focus(view: Node) -> void:
	if view.world == null or view.camera == null: return
	var splits := Vector3(0.1, 0.2, 0.5)
	if not is_instance_valid(view.exploration_camera()):
		# Orthographic cascades span camera.far on every renderer. Keep the
		# enormous final cascade beyond all visible ground: otherwise the top
		# of a wide view loses small shadows as it enters that coarse cascade.
		# At 30 degrees, the top ground ray is sqrt(3) * half-height deeper
		# than the focus, plus twice the focus elevation down to sea level.
		# Bound that reach by the city corners so overview zooms stay useful.
		var focus: float = view.camera.position.distance_to(view.center)
		var size: float = minf(view.camera.size, 180.0)
		var far: float = view.camera.far
		var first := clampf(focus - maxf(35.0, size * 0.75), 1.0, far - 3.0)
		var second := clampf(focus - maxf(15.0, size / 3.0), first + 1.0, far - 2.0)
		var screen := Vector2(view.viewport.size)
		var half_height: float = view.camera.size * 0.5
		if view.camera.keep_aspect == Camera3D.KEEP_WIDTH:
			half_height *= screen.y / maxf(screen.x, 1.0)
		var visible_depth: float = focus + half_height * sqrt(3.0) + maxf(0.0, view.center.y) * 2.0
		var city_depth := focus
		for x: float in [0.0, float(City.WIDTH)]:
			for z: float in [0.0, float(City.HEIGHT)]:
				city_depth = maxf(city_depth, -view.camera.to_local(Vector3(x, 0.0, z)).z)
		var third := clampf(maxf(focus + 25.0, minf(visible_depth, city_depth) + 8.0), second + 1.0, far - 1.0)
		splits = Vector3(first, second, third) / far
	for child: Node in view.world.get_children():
		if child is DirectionalLight3D:
			child.directional_shadow_split_1 = splits.x
			child.directional_shadow_split_2 = splits.y
			child.directional_shadow_split_3 = splits.z
