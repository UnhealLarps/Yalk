extends CharacterBody2D

@export var speed := 500.0

func _physics_process(_delta: float):
	var direction := Input.get_vector(
		"move_left",
		"move_right",
		"move_up",
		"move_down"
	)

	velocity = direction * speed
	move_and_slide()
