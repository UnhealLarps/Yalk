extends CharacterBody2D
class_name HandCollision

func move_to_global(target: Vector2) -> KinematicCollision2D:
	if not target.is_finite():
		return null
	var motion := target - global_position
	if motion.length_squared() <= 0.01:
		velocity = Vector2.ZERO
		return null
	velocity = Vector2.ZERO
	return move_and_collide(motion)

func snap_to_global(target: Vector2):
	if not target.is_finite():
		return
	global_position = target
	velocity = Vector2.ZERO
