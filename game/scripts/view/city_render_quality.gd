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
	view.viewport.mesh_lod_threshold = 4.0 if performance else 2.0 if balanced else 1.0
	for child: Node in view.world.get_children():
		if child is DirectionalLight3D:
			child.shadow_enabled = not performance
			child.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if balanced and not mobile else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			child.directional_shadow_max_distance = 320.0 if balanced else 400.0
			child.light_energy = 0.7 if mobile else 0.325
		elif child is WorldEnvironment:
			child.environment.ambient_light_energy = 0.4 if mobile else 0.195
	var explore_camera: Camera3D = view.exploration_camera()
	if is_instance_valid(explore_camera) and explore_camera.environment != null:
		explore_camera.environment.ambient_light_energy = 0.4 if mobile else 0.195
	apply_shadow_focus(view)


static func apply_shadow_focus(view: Node) -> void:
	if view.world == null or view.camera == null: return
	var splits := Vector3(0.1, 0.2, 0.5)
	if RenderingServer.get_current_rendering_method() == "mobile" and not is_instance_valid(view.exploration_camera()):
		# Orthographic Mobile cascades span camera.far, even when the light's
		# max distance is shorter. The aerial camera sits ~185 units from its
		# focus: default splits waste the near cascades and cause terrain acne.
		# Concentrate two cascades around the visible city, widening with zoom.
		# Camera clipping and shadow bias remain untouched. Actor cameras use
		# normal near-camera splits rather than this distant aerial focus.
		var focus: float = view.camera.position.distance_to(view.center)
		var size: float = minf(view.camera.size, 180.0)
		var far: float = view.camera.far
		var first := clampf(focus - maxf(35.0, size * 0.75), 1.0, far - 3.0)
		var second := clampf(focus - maxf(15.0, size / 3.0), first + 1.0, far - 2.0)
		var third := clampf(focus + maxf(25.0, size * 0.5), second + 1.0, far - 1.0)
		splits = Vector3(first, second, third) / far
	for child: Node in view.world.get_children():
		if child is DirectionalLight3D:
			child.directional_shadow_split_1 = splits.x
			child.directional_shadow_split_2 = splits.y
			child.directional_shadow_split_3 = splits.z
