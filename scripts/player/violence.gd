extends Node

signal damage_changed(region: int, value: float)
signal hand_disabled(region: int)
signal died(impulse_direction: Vector2, hit_position: Vector2)

enum Region {
	BODY,
	HEAD,
	LEFT_HAND,
	RIGHT_HAND
}

enum Organ {
	HEART,
	BRAIN
}

enum Layer {
	SKIN,
	MUSCLE,
	SKELETON
}

@export_category("HitBoxes")
@export var body_hitbox: Area2D
@export var head_hitbox: Area2D
@export var left_hand_hitbox: Area2D
@export var right_hand_hitbox: Area2D

@export_category("Body Visuals")
@export var body_skin: Sprite2D
@export var body_muscle: Sprite2D
@export var body_skeleton: Sprite2D

@export_category("Head Visuals")
@export var head_skin: Sprite2D
@export var head_muscle: Sprite2D
@export var head_skeleton: Sprite2D

@export_category("Left Hand Visuals")
@export var left_hand_skin: Sprite2D
@export var left_hand_muscle: Sprite2D
@export var left_hand_skeleton: Sprite2D

@export_category("Right Hand Visuals")
@export var right_hand_skin: Sprite2D
@export var right_hand_muscle: Sprite2D
@export var right_hand_skeleton: Sprite2D

@export_category("Damage")
@export_range(0.0, 1000.0, 1.0) var max_damage: float = 100.0
@export_range(0.0, 3000.0, 1.0) var base_speed_loss: float = 1500.0
@export_range(0.0, 3000.0, 1.0) var head_speed_loss: float = 1650.0
@export_range(0.0, 2000.0, 1.0) var hand_speed_loss: float = 900.0
@export_range(0.0, 1500.0, 1.0) var muscle_speed_loss: float = 350.0
@export_range(0.0, 1000.0, 1.0) var skeleton_speed_loss: float = 120.0
@export_range(1.0, 50.0, 0.5) var default_wound_radius: float = 6.0

var body_damage := 0.0
var head_damage := 0.0
var left_hand_damage := 0.0
var right_hand_damage := 0.0

var left_hand_is_disabled := false
var right_hand_is_disabled := false
var is_dead := false

var mask_images: Array = []
var mask_textures: Array = []
var materials: Array = []
var skin_images: Array = []
var muscle_images: Array = []
var bleeding_wounds: Array[Dictionary] = []
var blood_volume := 100.0
var bleeding_hit_count := 0
var last_hit_direction := Vector2.ZERO

const BLOOD_PARTICLES_SCENE := preload("res://prefabs/effects/blood_particles.tscn")
const MAX_BLEEDING_WOUNDS := 5
const BLOOD_LOSS_PER_INTENSITY := 4.0
const BLEEDING_CALLS_TO_DEATH := 4

func _ready():
	if left_hand_hitbox == null:
		left_hand_hitbox = get_node_or_null("../LeftHandCollision/LeftHandArea") as Area2D
	if right_hand_hitbox == null:
		right_hand_hitbox = get_node_or_null("../RightHandCollision/RightHandArea") as Area2D

	setup_hitbox(body_hitbox, Region.BODY)
	setup_hitbox(head_hitbox, Region.HEAD)
	setup_hitbox(left_hand_hitbox, Region.LEFT_HAND)
	setup_hitbox(right_hand_hitbox, Region.RIGHT_HAND)

	setup_organ_hitbox(get_node_or_null("../HitBoxes/Heart") as Area2D, Organ.HEART)
	setup_organ_hitbox(get_node_or_null("../HitBoxes/Brain") as Area2D, Organ.BRAIN)

	setup_region(Region.BODY, body_skin, body_muscle, body_skeleton)
	setup_region(Region.HEAD, head_skin, head_muscle, head_skeleton)
	setup_region(Region.LEFT_HAND, left_hand_skin, left_hand_muscle, left_hand_skeleton)
	setup_region(Region.RIGHT_HAND, right_hand_skin, right_hand_muscle, right_hand_skeleton)

func _process(delta: float):
	if is_dead:
		bleeding_wounds.clear()
		return
	var active_blood_loss := 0.0
	for i in range(bleeding_wounds.size() - 1, -1, -1):
		var wound: Dictionary = bleeding_wounds[i]
		var remaining := float(wound.get("remaining", 0.0)) - delta
		if remaining <= 0.0:
			bleeding_wounds.remove_at(i)
		else:
			wound["remaining"] = remaining
			bleeding_wounds[i] = wound
			active_blood_loss += float(wound.get("intensity", 1.0)) * BLOOD_LOSS_PER_INTENSITY
	if NetworkManager.is_server_authority() and active_blood_loss > 0.0:
		blood_volume = maxf(0.0, blood_volume - active_blood_loss * delta)

func reset_for_round():
	bleeding_wounds.clear()
	blood_volume = 100.0
	bleeding_hit_count = 0
	last_hit_direction = Vector2.ZERO
	body_damage = 0.0
	head_damage = 0.0
	left_hand_damage = 0.0
	right_hand_damage = 0.0
	left_hand_is_disabled = false
	right_hand_is_disabled = false
	is_dead = false
	for i in range(mask_images.size()):
		var mask: Image = mask_images[i]
		if mask == null:
			continue
		mask.fill(Color(0.0, 0.0, 0.0, 1.0))
		if i < mask_textures.size() and mask_textures[i] != null:
			mask_textures[i].update(mask)

func setup_hitbox(hitbox: Area2D, region: int):
	if hitbox == null:
		return
	hitbox.set_meta("ultra_violence", self)
	hitbox.set_meta("ultra_region", region)

func setup_organ_hitbox(hitbox: Area2D, organ: int):
	if hitbox == null:
		return
	hitbox.set_meta("ultra_violence", self)
	hitbox.set_meta("ultra_organ", organ)

func setup_region(region: int, skin: Sprite2D, muscle: Sprite2D, skeleton: Sprite2D):
	while mask_images.size() <= region:
		mask_images.append(null)
		mask_textures.append(null)
		materials.append(null)
		skin_images.append(null)
		muscle_images.append(null)
	if skin == null or skin.texture == null:
		return

	var texture_size := skin.texture.get_size()
	var mask := Image.create(
		int(texture_size.x),
		int(texture_size.y),
		false,
		Image.FORMAT_RGBA8
	)

	mask.fill(Color(0.0, 0.0, 0.0, 1.0))
	var texture := ImageTexture.create_from_image(mask)

	mask_images[region] = mask
	mask_textures[region] = texture
	skin_images[region] = skin.texture.get_image()
	muscle_images[region] = muscle.texture.get_image() if muscle != null and muscle.texture != null else null

	materials[region] = [
		setup_material(skin, texture, Layer.SKIN),
		setup_material(muscle, texture, Layer.MUSCLE),
		setup_material(skeleton, texture, Layer.SKELETON)
	]

func setup_material(sprite: Sprite2D, damage_mask: ImageTexture, channel: int) -> ShaderMaterial:
	if sprite == null:
		return null
	var shader := load("res://shaders/ultra_violence.gdshader") as Shader
	if shader == null:
		return null

	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("damage_mask", damage_mask)
	material.set_shader_parameter("damage_channel", channel)
	sprite.material = material

	return material

func get_damage(region: int) -> float:
	match region:
		Region.BODY:
			return body_damage
		Region.HEAD:
			return head_damage
		Region.LEFT_HAND:
			return left_hand_damage
		Region.RIGHT_HAND:
			return right_hand_damage

	return 0.0

func set_damage(region: int, value: float):
	var damage := clampf(value, 0.0, max_damage)
	match region:
		Region.BODY:
			body_damage = damage
		Region.HEAD:
			head_damage = damage
		Region.LEFT_HAND:
			left_hand_damage = damage
		Region.RIGHT_HAND:
			right_hand_damage = damage
	damage_changed.emit(region, damage)

	if region == Region.LEFT_HAND and damage > max_damage * 0.5 and not left_hand_is_disabled:
		left_hand_is_disabled = true
		hand_disabled.emit(region)
	if region == Region.RIGHT_HAND and damage > max_damage * 0.5 and not right_hand_is_disabled:
		right_hand_is_disabled = true
		hand_disabled.emit(region)

func get_damage_multiplier(region: int) -> float:
	match region:
		Region.BODY:
			return 1.0
		Region.HEAD:
			return 1.5
		Region.LEFT_HAND, Region.RIGHT_HAND:
			return 0.8

	return 1.0

func apply_hit(region: int, penetration: float, hit_position: Vector2, radius: float = -1.0, hit_direction: Vector2 = Vector2.ZERO) -> float:
	if is_dead:
		return 0.0
	if not has_visible_flesh_at(region, hit_position):
		return 0.0
	var power := maxf(penetration, 0.0)
	if power <= 0.0:
		return 0.0
	if hit_direction.is_finite() and hit_direction.length_squared() > 0.001:
		last_hit_direction = hit_direction.normalized()
	var hit_radius := default_wound_radius if radius <= 0.0 else radius
	var actual_wound_radius := hit_radius * 1.8
	
	paint_wound(region, hit_position, actual_wound_radius, power)

	var damage := (30.0 + power * 0.85) * get_damage_multiplier(region)
	set_damage(region, get_damage(region) + damage)
	_start_bleeding(region, hit_position, 2.4 + clampf(power / 500.0, 0.0, 1.0), clampf(power / 100.0, 0.55, 1.8))
	if NetworkManager.is_server():
		NetworkManager.broadcast_hit(get_parent(), region, hit_position, hit_radius, power, hit_direction)
	
	return get_speed_loss(region, power)

func apply_organ_hit(organ: int, hit_position: Vector2, impulse_direction: Vector2):
	if is_dead:
		return
	is_dead = true

	if impulse_direction.length_squared() == 0.0:
		impulse_direction = Vector2.RIGHT
	died.emit(impulse_direction.normalized(), hit_position)

func apply_network_hit(region: int, hit_position: Vector2, radius: float, penetration: float, hit_direction: Vector2 = Vector2.ZERO):
	if NetworkManager.is_server():
		return
	apply_hit(region, penetration, hit_position, radius, hit_direction)

func apply_sharp_hit(region: int, sharpness: float, impact_speed: float, hit_position: Vector2, radius: float = 5.0, impact_direction: Vector2 = Vector2.ZERO) -> float:
	if is_dead or not has_visible_flesh_at(region, hit_position):
		return 0.0
	var sharpness_value := clampf(sharpness, 0.0, 100.0)
	if impact_direction.is_finite() and impact_direction.length_squared() > 0.001:
		last_hit_direction = impact_direction.normalized()
	var speed_factor := clampf(impact_speed / 500.0, 0.0, 2.0)
	paint_sharp_wound(region, hit_position, radius, sharpness_value, impact_speed)
	var damage := (8.0 + speed_factor * 12.0 + sharpness_value * 0.1) * get_damage_multiplier(region)
	set_damage(region, get_damage(region) + damage)
	var penetration := sharpness_value * clampf(impact_speed / 250.0, 0.25, 2.0)
	_start_bleeding(region, hit_position, 2.0 + sharpness_value * 0.025 + clampf(impact_speed / 1000.0, 0.0, 1.0), clampf(sharpness_value / 40.0 + impact_speed / 650.0, 0.55, 2.8))
	if NetworkManager.is_server():
		NetworkManager.broadcast_sharp_hit(get_parent(), region, hit_position, radius, sharpness_value, impact_speed, impact_direction)
	return get_speed_loss(region, penetration)

func _start_bleeding(region: int, hit_position: Vector2, duration: float, intensity: float):
	if is_dead:
		return
	var skin := get_skin_sprite(region)
	if skin == null:
		return
	var local_position := skin.to_local(hit_position)
	var bleed_duration := clampf(duration, 0.5, 6.0)
	var bleed_intensity := clampf(intensity, 0.4, 3.0)
	var merged := false
	for i in range(bleeding_wounds.size()):
		var wound: Dictionary = bleeding_wounds[i]
		if int(wound.get("region", -1)) != region:
			continue
		var existing_position: Variant = wound.get("local_position", Vector2.ZERO)
		if existing_position is Vector2 and existing_position.distance_to(local_position) <= 7.0:
			wound["remaining"] = maxf(float(wound.get("remaining", 0.0)), bleed_duration)
			wound["intensity"] = maxf(float(wound.get("intensity", 0.0)), bleed_intensity)
			bleeding_wounds[i] = wound
			merged = true
			break
	if not merged:
		if bleeding_wounds.size() >= MAX_BLEEDING_WOUNDS:
			bleeding_wounds.pop_front()
		bleeding_wounds.append({"region": region, "local_position": local_position, "remaining": bleed_duration, "intensity": bleed_intensity})
	var direction := (hit_position - skin.global_position).normalized()
	if direction.length_squared() < 0.001:
		direction = Vector2.UP
	_spawn_blood_particles(hit_position, direction, bleed_intensity)
	if not NetworkManager.is_server_authority():
		return
	bleeding_hit_count += 1
	if bleeding_hit_count < BLEEDING_CALLS_TO_DEATH:
		return
	var death_direction := last_hit_direction
	if death_direction.length_squared() < 0.001:
		death_direction = Vector2.UP
	apply_organ_hit(Organ.HEART, hit_position, death_direction)

func _spawn_blood_particles(world_position: Vector2, direction: Vector2, intensity: float):
	if Args.headless or get_tree().current_scene == null:
		return
	var effect := BLOOD_PARTICLES_SCENE.instantiate() as CPUParticles2D
	if effect == null:
		return
	var spread_direction := direction.normalized()
	if spread_direction.length_squared() < 0.001:
		spread_direction = Vector2.UP
	if effect.has_method("configure"):
		effect.call("configure", spread_direction, intensity)
	get_tree().current_scene.add_child(effect)
	effect.global_position = world_position

func apply_network_sharp_hit(region: int, hit_position: Vector2, radius: float, sharpness: float, impact_speed: float, impact_direction: Vector2 = Vector2.ZERO):
	if NetworkManager.is_server():
		return
	apply_sharp_hit(region, sharpness, impact_speed, hit_position, radius, impact_direction)

func paint_sharp_wound(region: int, hit_position: Vector2, radius: float, sharpness: float, impact_speed: float):
	if region < 0 or region >= mask_images.size():
		return
	var mask: Image = mask_images[region]
	var skin := get_skin_sprite(region)
	if mask == null or skin == null:
		return
	var local_position := skin.to_local(hit_position)
	var texture_size := Vector2(mask.get_width(), mask.get_height())
	var center := local_position + texture_size * 0.5
	var scale_x := skin.global_transform.x.length()
	var scale_y := skin.global_transform.y.length()
	if scale_x <= 0.001 or scale_y <= 0.001:
		return
	var impact_radius := radius * clampf(0.65 + impact_speed / 700.0, 0.65, 1.8)
	var seed_power := sharpness + impact_speed * 0.01
	paint_channel(mask, center, impact_radius, scale_x, scale_y, Layer.SKIN, 1.0, seed_power)
	if sharpness >= 25.0:
		var muscle_depth := clampf((sharpness - 25.0) / 45.0, 0.0, 1.0)
		paint_channel(mask, center, impact_radius * lerpf(0.28, 0.62, muscle_depth), scale_x, scale_y, Layer.MUSCLE, lerpf(0.35, 1.0, muscle_depth), seed_power)
	if sharpness >= 70.0:
		var skeleton_depth := clampf((sharpness - 70.0) / 30.0, 0.0, 1.0)
		paint_channel(mask, center, impact_radius * lerpf(0.12, 0.36, skeleton_depth), scale_x, scale_y, Layer.SKELETON, lerpf(0.2, 0.8, skeleton_depth), seed_power)
	mask_textures[region].update(mask)

func get_speed_loss(region: int, power: float) -> float:
	var penetration_factor := clampf(1.2 - power / 500.0, 0.85, 1.2)
	match region:
		Region.BODY:
			return (base_speed_loss + muscle_speed_loss + skeleton_speed_loss) * penetration_factor
		Region.HEAD:
			return (head_speed_loss+ muscle_speed_loss+ skeleton_speed_loss) * penetration_factor
		Region.LEFT_HAND, Region.RIGHT_HAND:
			return (hand_speed_loss + muscle_speed_loss * 0.5 + skeleton_speed_loss * 0.5) * penetration_factor
	return base_speed_loss

func find_visible_flesh_hit(region: int, from: Vector2, to: Vector2) -> Variant:
	var distance := from.distance_to(to)
	var samples := clampi(ceili(distance / 1.5), 1, 512)

	for i in range(samples + 1):
		var t := float(i) / float(samples)
		var point := from.lerp(to, t)
		if has_visible_flesh_at(region, point):
			return point
	return null

func has_visible_flesh_at(region: int, world_position: Vector2) -> bool:
	if region < 0 or region >= mask_images.size():
		return false
	var skin := get_skin_sprite(region)
	if skin == null or skin.texture == null:
		return false

	var uv := get_hit_uv(region, world_position)
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return false

	var mask: Image = mask_images[region]
	if mask == null:
		return false

	var x := clampi(int(uv.x * mask.get_width()), 0, mask.get_width() - 1)
	var y := clampi(int(uv.y * mask.get_height()), 0, mask.get_height() - 1)
	var damage := mask.get_pixel(x, y)
	var skin_alpha := sample_alpha(skin_images[region], uv)
	var muscle_alpha := sample_alpha(muscle_images[region], uv)

	return skin_alpha * (1.0 - damage.r) > 0.05 or muscle_alpha * (1.0 - damage.g) > 0.05

func sample_alpha(image: Image, uv: Vector2) -> float:
	if image == null:
		return 0.0
	var x := clampi(int(uv.x * image.get_width()), 0, image.get_width() - 1)
	var y := clampi(int(uv.y * image.get_height()), 0, image.get_height() - 1)
	
	return image.get_pixel(x, y).a

func get_hit_uv(region: int, hit_position: Vector2) -> Vector2:
	var sprite := get_skin_sprite(region)
	if sprite == null or sprite.texture == null:
		return Vector2(-1.0, -1.0)
	var local_position := sprite.to_local(hit_position)
	var texture_size := Vector2(sprite.texture.get_width(), sprite.texture.get_height())

	return Vector2(
		local_position.x / texture_size.x + 0.5,
		local_position.y / texture_size.y + 0.5
	)

func get_skin_sprite(region: int) -> Sprite2D:
	match region:
		Region.BODY:
			return body_skin
		Region.HEAD:
			return head_skin
		Region.LEFT_HAND:
			return left_hand_skin
		Region.RIGHT_HAND:
			return right_hand_skin
	return null

func paint_wound(region: int, hit_position: Vector2, radius: float, penetration: float):
	if region >= mask_images.size():
		return

	var mask: Image = mask_images[region]
	var skin := get_skin_sprite(region)

	if mask == null or skin == null:
		return

	var local_position := skin.to_local(hit_position)
	var texture_size := Vector2(mask.get_width(), mask.get_height())
	var center := local_position + texture_size * 0.5
	var scale_x := skin.global_transform.x.length()
	var scale_y := skin.global_transform.y.length()

	if scale_x <= 0.001 or scale_y <= 0.001:
		return

	var power := clampf(penetration / 100.0, 0.0, 2.5)

	paint_channel(
		mask,
		center,
		radius,
		scale_x,
		scale_y,
		Layer.SKIN,
		1.0,
		penetration
	)

	paint_channel(
		mask,
		center,
		radius * 0.64,
		scale_x,
		scale_y,
		Layer.MUSCLE,
		clampf(
			0.35 + power * 0.65,
			0.35,
			1.0
		),
		penetration
	)

	paint_channel(
		mask,
		center,
		radius * 0.38,
		scale_x,
		scale_y,
		Layer.SKELETON,
		clampf(
			0.18 + power * 0.35,
			0.18,
			0.75
		),
		penetration
	)

	mask_textures[region].update(mask)

func paint_channel(mask: Image, center: Vector2, world_radius: float, scale_x: float, scale_y: float, channel: int, strength: float, penetration: float):
	var radius_x := world_radius / scale_x
	var radius_y := world_radius / scale_y

	if radius_x <= 0.0 or radius_y <= 0.0:
		return

	var min_x := maxi(floori(center.x - radius_x), 0)
	var max_x := mini(ceili(center.x + radius_x), mask.get_width() - 1)
	var min_y := maxi(floori(center.y - radius_y), 0)
	var max_y := mini(ceili(center.y + radius_y), mask.get_height() - 1)
	var seed := (center.x * 0.731 + center.y * 1.193 + penetration * 2.17)

	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var dx := (x - center.x) / radius_x
			var dy := (y - center.y) / radius_y
			var distance := sqrt(
				dx * dx
				+ dy * dy
			)

			if distance > 1.0:
				continue
			var angle := atan2(dy, dx)
			var noise_1 := sin(angle * 7.0 + seed) * 0.5 + 0.5
			var noise_2 := sin(angle * 13.0 - seed * 0.37) * 0.5 + 0.5
			var edge := 0.58 + noise_1 * 0.25 + noise_2 * 0.17
			var value := (
				1.0
				- smoothstep(
					edge,
					1.0,
					distance
				)
			) * strength

			if value <= 0.0:
				continue
			var pixel := mask.get_pixel(x, y)
			match channel:
				Layer.SKIN:
					pixel.r = maxf(pixel.r, value)
				Layer.MUSCLE:
					pixel.g = maxf(pixel.g, value)
				Layer.SKELETON:
					pixel.b = maxf(pixel.b, value)
			mask.set_pixel(x, y, pixel)
