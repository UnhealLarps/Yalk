extends CanvasLayer

@onready var mode_panel: Control = $Root/ModePanel
@onready var role_panel: Control = $Root/RolePanel

var elapsed := 0.0
var mode_offsets := Vector4.ZERO
var role_offsets := Vector4.ZERO
var offsets_ready := false
var music_player: AudioStreamPlayer = null
var music_tween: Tween = null

func _ready():
	call_deferred("_capture_offsets")

func play_presentation_music(stream_path: String, duration: float = 5.0):
	if stream_path.is_empty():
		return
	var stream := ResourceLoader.load(stream_path) as AudioStream
	if stream == null:
		push_warning("Round music could not be loaded: %s" % stream_path)
		return
	if music_player != null and is_instance_valid(music_player):
		music_player.stop()
		music_player.queue_free()
	music_player = AudioStreamPlayer.new()
	music_player.name = "RoundMusic"
	music_player.stream = stream
	music_player.volume_db = -3.0
	add_child(music_player)
	music_player.play()
	var fade_duration := minf(1.25, maxf(duration * 0.25, 0.1))
	var fade_delay := maxf(duration - fade_duration - 0.15, 0.0)
	music_tween = create_tween()
	music_tween.tween_property(music_player, "volume_db", -45.0, fade_duration).set_delay(fade_delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

func _capture_offsets():
	if mode_panel == null or role_panel == null:
		return
	mode_offsets = Vector4(mode_panel.offset_left, mode_panel.offset_top, mode_panel.offset_right, mode_panel.offset_bottom)
	role_offsets = Vector4(role_panel.offset_left, role_panel.offset_top, role_panel.offset_right, role_panel.offset_bottom)
	offsets_ready = true

func _process(delta: float):
	if not offsets_ready:
		return
	elapsed += delta
	var mode_x := sin(elapsed * 17.0) * 1.25 + sin(elapsed * 29.0) * 0.35
	var mode_y := cos(elapsed * 13.0) * 0.9 + sin(elapsed * 23.0) * 0.25
	var role_x := sin(elapsed * 11.0 + 1.4) * 0.9 + cos(elapsed * 19.0) * 0.4
	var role_y := cos(elapsed * 15.0 + 0.8) * 1.2 + sin(elapsed * 25.0) * 0.25
	_apply_offsets(mode_panel, mode_offsets, Vector2(mode_x, mode_y))
	_apply_offsets(role_panel, role_offsets, Vector2(role_x, role_y))

func _apply_offsets(panel: Control, base: Vector4, shake: Vector2):
	panel.offset_left = base.x + shake.x
	panel.offset_right = base.z + shake.x
	panel.offset_top = base.y + shake.y
	panel.offset_bottom = base.w + shake.y

func _exit_tree():
	if music_tween != null and music_tween.is_running():
		music_tween.kill()
	if music_player != null and is_instance_valid(music_player):
		music_player.stop()
