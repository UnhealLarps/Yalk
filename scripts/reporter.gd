# var rep := Reporter.new("File Name")
#
# rep.info("message")
# rep.debug("message")
# rep.warn("message")
# rep.error("message")

extends RefCounted
class_name Reporter

enum Level {
	DEBUG,
	INFO,
	WARN,
	ERROR
}

var source: String = ""
var file_enabled: bool = true
var file_path: String = "user://smthhappen.log"

func _init(p_source: String = "") -> void:
	source = p_source
	
func debug(message: String) -> void:
	_log(Level.DEBUG, message)
func info(message: String) -> void:
	_log(Level.INFO, message)
func warn(message: String) -> void:
	_log(Level.WARN, message)
func error(message: String) -> void:
	_log(Level.ERROR, message)
	
func _log(level: Level, message: String) -> void:
	var output := _format_message(level, message)
	print(output)
	
	if file_enabled:
		_write(output)

func _format_message(level: Level, message: String) -> String:
	var time := Time.get_time_string_from_system()
	var level_name: String = Level.keys()[level]
	var result := "[%s] [%s]" % [ time, level_name ]
	
	if not source.is_empty():
		result += " [%s]" % source
	result += " " + message
	return result

func _write(message: String) -> void:
	var file := FileAccess.open(file_path, FileAccess.WRITE_READ)
	if file == null:
		push_error("[Reporter] Failed to open log file: %s" % file_path)
		return
		
	file.seek_end()
	file.store_line(message)
	file.close()
