extends Node

const SETTINGS_PATH := "user://settings.json"
const DEFAULTS := {
	"window_mode": "window",
	"master_volume": 100,
	"show_fps": false,
}

var rep := Reporter.new("Settings")
var options: Dictionary = DEFAULTS.duplicate(true)

func _ready() -> void:
	load_settings()
	WindowManager.apply_window_settings()
	
func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		save_settings()
		return
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		rep.error("Failed to open settings file")
		return
		
	var data = JSON.parse_string(file.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		rep.error("Invalid settings file")
		return
	for key in DEFAULTS:
		if data.has(key):
			options[key] = data[key]
			
func save_settings() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		rep.error("Failed to save settings file")
		return
	file.store_string(JSON.stringify(options, "\t"))
	
func check_option(option: String):
	return options.get(option, null)
	
func set_option(option: String, value) -> void:
	if not DEFAULTS.has(option):
		rep.warn("Unknown setting: " + option)
		return
	
	options[option] = value
	save_settings()
	
func reset_settings() -> void:
	options = DEFAULTS.duplicate(true)
	save_settings()
