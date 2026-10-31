extends Node2D
class_name Blood

@export_category("Surfaces")
@export var surfaces: Array[Sprite2D] = []

@export_category("Blood")
@export_range(0.2, 10.0, 0.1) var stain_radius: float = 1.3
@export_range(0.1, 5.0, 0.1) var splash_radius: float = 0.45
@export_range(1, 20, 1) var splash_count: int = 5
@export_range(0.0, 1.0, 0.01) var alpha: float = 0.9

var rng := RandomNumberGenerator.new()

func _ready():
	rng.randomize()

func receive_hit(region: int, penetration: float, position: Vector2, wound_radius: float):
	var violence := get_parent()
	if violence == null:
		return
	var surface: Sprite2D = null
	match region:
		0:
			surface = violence.body_skin
		1:
			surface = violence.head_skin
		2:
			surface = violence.left_hand_skin
		3:
			surface = violence.right_hand_skin

	if surface == null or not is_allowed_surface(surface):
		return

	var local_position := surface.to_local(position)
	var surface_scale := get_surface_scale(surface)
	var local_wound_radius := wound_radius / surface_scale
	var strength := clampf(penetration / 100.0, 0.35, 2.5)

	add_blood_ring(surface, local_position, local_wound_radius, strength)

func receive_surface_hit(surface: Sprite2D, position: Vector2, wound_radius: float, strength: float):
	if surface == null or not is_allowed_surface(surface):
		return
	var local_position := surface.to_local(position)
	var surface_scale := get_surface_scale(surface)
	var local_radius := wound_radius / surface_scale
	add_blood_ring(surface, local_position, local_radius, strength)

func is_allowed_surface(surface: Sprite2D) -> bool:
	if surfaces.is_empty():
		return false
	return surfaces.has(surface)

func get_surface_scale(surface: Sprite2D) -> float:
	var scale_x := surface.global_transform.x.length()
	var scale_y := surface.global_transform.y.length()

	return maxf((scale_x + scale_y) * 0.5, 0.001)

func add_blood_ring(surface: Sprite2D, center: Vector2, wound_radius: float, strength: float):
	var surface_scale := get_surface_scale(surface)
	var local_stain_radius := stain_radius / surface_scale
	var local_splash_radius := splash_radius / surface_scale
	var count := clampi(roundi(4.0 + strength * 2.0), 4, 9)

	for _i in range(count):
		var angle := rng.randf_range(0.0, TAU)
		var distance := wound_radius + local_stain_radius * rng.randf_range(0.8, 1.8)
		var position := (center + Vector2.from_angle(angle) * distance)
		add_stain(surface, position, local_stain_radius * rng.randf_range(0.6, 1.15))

	for _i in range(splash_count):
		var angle := rng.randf_range(0.0, TAU)
		var distance := wound_radius + local_stain_radius * rng.randf_range(1.3, 3.0)
		var position := (center + Vector2.from_angle(angle) * distance)
		add_stain(surface, position, local_splash_radius * rng.randf_range(0.6, 1.2))

func add_stain(surface: Sprite2D, position: Vector2, radius: float):
	var polygon := Polygon2D.new()
	polygon.name = "BloodStain"
	polygon.position = position
	polygon.color = Color(0.28, 0.002, 0.002, alpha * rng.randf_range(0.75, 1.0))

	var points := PackedVector2Array()
	var segments := rng.randi_range(7, 12)
	var start_angle := rng.randf_range(0.0, TAU)

	for i in range(segments):
		var angle := (start_angle + TAU * float(i) / float(segments))
		var distance := (radius * rng.randf_range(0.55, 1.15))
		points.append(Vector2.from_angle(angle) * distance)

	polygon.polygon = points
	surface.add_child(polygon)
