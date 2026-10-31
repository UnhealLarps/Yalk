extends CPUParticles2D

func _ready():
	if not finished.is_connected(_on_finished):
		finished.connect(_on_finished)
	call_deferred("_start_emission")

func configure(value: Vector2, intensity: float):
	var normalized_direction := value.normalized()
	direction = normalized_direction if normalized_direction.length_squared() > 0.001 else Vector2.UP
	var strength := clampf(intensity, 0.4, 3.0)
	amount = clampi(roundi(18.0 * strength), 8, 54)
	initial_velocity_min = 60.0 * strength
	initial_velocity_max = 185.0 * strength
	var scale_factor := clampf(strength, 0.8, 1.6)
	scale_amount_min = 0.18 * scale_factor
	scale_amount_max = 0.45 * scale_factor

func _start_emission():
	emitting = true
	restart()

func _on_finished():
	queue_free()
