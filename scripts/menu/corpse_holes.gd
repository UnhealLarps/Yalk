extends Node2D

var marks: Array[Dictionary] = []

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var count := rng.randi_range(2, 6)
	for i in range(count):
		var region := rng.randi_range(0, 3)
		var point := Vector2.ZERO
		match region:
			0:
				point = Vector2(rng.randf_range(-6.0, 6.0), rng.randf_range(-53.0, -38.0))
			1:
				point = Vector2(rng.randf_range(-7.0, 7.0), rng.randf_range(-20.0, 12.0))
			2:
				point = Vector2(rng.randf_range(-29.0, -17.0), rng.randf_range(-17.0, -2.0))
			3:
				point = Vector2(rng.randf_range(17.0, 29.0), rng.randf_range(-17.0, -2.0))
		marks.append({"position": point, "radius": rng.randf_range(1.1, 2.1)})
	queue_redraw()

func _draw() -> void:
	for mark in marks:
		var point: Vector2 = mark["position"]
		var radius: float = float(mark["radius"])
		draw_circle(point, radius * 1.55, Color(0.25, 0.035, 0.035, 0.96))
		draw_circle(point, radius, Color(0.025, 0.018, 0.018, 1.0))
		draw_circle(point + Vector2(-radius * 0.18, -radius * 0.15), radius * 0.3, Color(0.09, 0.02, 0.02, 1.0))
