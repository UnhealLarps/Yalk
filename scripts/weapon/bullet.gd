extends Area2D

@export_range(1.0, 100000.0, 1.0) var speed: float = 1800.0
@export_range(0.0, 1000.0, 1.0) var penetration: float = 100.0
@export_range(1.0, 50.0, 0.5)  var wound_radius: float = 6.0
@export_range(100.0, 100000.0, 100.0) var max_range: float = 10000.0

var direction := Vector2.RIGHT
var traveled_distance := 0.0
var network_bullet_id := 0
var network_visual := false

var rep := Reporter.new("Bullet")

func set_network_bullet_id(value: int):
	network_bullet_id = value

func set_network_visual(bullet_id: int, start_position: Vector2, start_direction: Vector2):
	network_bullet_id = bullet_id
	network_visual = true
	global_position = start_position
	setup(start_direction)

func finish():
	if network_visual:
		GC.destroy(self)
		return
	if NetworkManager.is_server() and network_bullet_id > 0:
		NetworkManager.finish_bullet(network_bullet_id)
	GC.destroy(self)

func setup(start_direction: Vector2, _start_source: Node = null) -> void:
	if start_direction.length_squared() == 0.0:
		return

	direction = start_direction.normalized()
	global_rotation = direction.angle()

func _physics_process(delta: float):
	if network_visual:
		var visual_step := speed * delta
		global_position += direction * visual_step
		traveled_distance += visual_step
		if traveled_distance >= max_range:
			GC.destroy(self)
		return
	var time_left := delta
	var iterations := 0

	while time_left > 0.0 and iterations < 32:
		iterations += 1
		var step := speed * time_left

		if traveled_distance + step >= max_range:
			var final_step := max_range - traveled_distance
			if final_step <= 0.0:
				finish()
				return

			global_position += direction * final_step
			traveled_distance += final_step
			finish()
			return

		var from := global_position
		var to := from + direction * step
		var query := PhysicsRayQueryParameters2D.create(from, to)

		query.collision_mask = collision_mask
		query.collide_with_bodies = true
		query.collide_with_areas = true
		query.hit_from_inside = false
		query.exclude = [get_rid()]

		var hit := get_world_2d().direct_space_state.intersect_ray(query)

		if hit.is_empty():
			global_position = to
			traveled_distance += step
			return

		var hit_position: Vector2 = hit.position
		var collider: Node = hit.collider

		if collider is Area2D:
			var area := collider as Area2D
			if area.has_meta("ultra_violence"):
				var violence: Node = area.get_meta("ultra_violence")
				var region := int(area.get_meta("ultra_region", -1))
				var organ := int(area.get_meta("ultra_organ", -1))
				if violence == null:
					finish()
					return
				if organ >= 0 and violence.has_method("apply_organ_hit"):
					global_position = hit_position
					violence.apply_organ_hit(
						organ,
						hit_position,
						direction
					)

					rep.debug("Fatal hit: %s" % area.name)
					finish()
					return

				if region >= 0 and violence.has_method("find_visible_flesh_hit"):
					var inside_from := hit_position + direction * 0.1
					var inside_to := to
					var next_hit := PhysicsRayQueryParameters2D.create(
						inside_from,
						to
					)

					next_hit.collision_mask = collision_mask
					next_hit.collide_with_bodies = true
					next_hit.collide_with_areas = true
					next_hit.hit_from_inside = false
					next_hit.exclude = [
						get_rid(),
						area.get_rid()
					]

					var exit_hit := get_world_2d().direct_space_state.intersect_ray(next_hit)
					if not exit_hit.is_empty():
						inside_to = exit_hit.position
					var flesh_hit: Variant = violence.find_visible_flesh_hit(
						region,
						inside_from,
						inside_to
					)
					if flesh_hit != null:
						var visible_hit := flesh_hit as Vector2
						global_position = visible_hit
						violence.apply_hit(
							region,
							penetration,
							visible_hit,
							wound_radius,
							direction
						)

						rep.debug("Hit %s | Penetration: %.1f" % [area.name, penetration])
						finish()
						return

					var passed_distance := from.distance_to(inside_to)
					global_position = inside_to
					traveled_distance += passed_distance
					time_left -= passed_distance / speed

					if exit_hit.is_empty():
						return
					continue
			finish()
			return

		global_position = hit_position
		rep.debug("Hit body: %s" % collider.name)

		finish()
		return
