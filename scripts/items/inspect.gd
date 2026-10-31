extends CanvasLayer

@export var display_time: float = 1.5
@export var fade_time: float = 1.0

@onready var text_label: RichTextLabel = $Text

var player: Node = null
var fade_tween: Tween = null

func _ready():
	player = get_parent()
	text_label.visible = false
	update_position()

func _process(_delta):
	update_position()
	if Input.is_action_just_pressed("inspect"):
		var item: Node = get_item_to_inspect()
		if item != null:
			show_description(item)

func update_position():
	if player == null:
		return

func get_item_to_inspect() -> Node:
	if player == null:
		return null

	var left_item: Node = player.get("left_item")
	var right_item: Node = player.get("right_item")
	var left_active := Input.is_action_pressed("left_click")
	var right_active := Input.is_action_pressed("right_click")

	if left_active and left_item != null:
		return left_item
	if right_active and right_item != null:
		return right_item
	if left_item != null and right_item == null:
		return left_item
	if right_item != null and left_item == null:
		return right_item
	if left_item != null:
		return left_item

	return right_item

func show_description(item: Node):
	var description_node: Node = find_description_node(item)
	if description_node == null:
		return
	var value: Variant = description_node.get("text")
	if typeof(value) != TYPE_STRING:
		return
	var template: String = value
	if template.is_empty():
		return
	var formatted_text: String = format_description(item, template)
	if formatted_text.is_empty():
		return
	if fade_tween != null and fade_tween.is_valid():
		fade_tween.kill()

	text_label.text = ("[center][color=#8a8a8a][i]" + formatted_text + "[/i][/color][/center]")
	text_label.visible = true
	var text_modulate: Color = text_label.modulate
	text_modulate.a = 1.0
	text_label.modulate = text_modulate
	update_position()
	fade_tween = create_tween()
	fade_tween.tween_interval(display_time)
	fade_tween.tween_property(text_label, "modulate:a", 0.0, fade_time)
	fade_tween.tween_callback(
		func():
			text_label.visible = false
	)

func find_description_node(item: Node) -> Node:
	if item == null:
		return null
	var node: Node = item.find_child("Description", true, false)
	
	return node

func format_description(item: Node, template: String) -> String:
	var regex := RegEx.new()
	regex.compile(r"\{([A-Za-z0-9_.]+)\}")
	var result: String = ""
	var last_position: int = 0
	var matches: Array[RegExMatch] = regex.search_all(template)

	for regex_match: RegExMatch in matches:
		var start: int = regex_match.get_start(0)
		var end: int = regex_match.get_end(0)
		result += template.substr(last_position, start - last_position)
		var variable_name: String = regex_match.get_string(1)
		result += resolve_variable(item, variable_name)
		last_position = end
	result += template.substr(last_position)

	return result

func resolve_variable(item: Node, variable_name: String) -> String:
	# example: {GunComponent.ammo}

	if variable_name.contains("."):
		var parts: PackedStringArray = variable_name.split(".")
		if parts.is_empty():
			return ""

		var node_name: String = parts[0]
		var target_node: Node = item.find_child(node_name, true, false)
		if target_node == null:
			return "{" + variable_name + "}"

		var current: Object = target_node
		for i in range(1, parts.size()):
			var property_name: String = parts[i]
			if not has_property(current, property_name):
				return "{" + variable_name + "}"

			var value: Variant = current.get(property_name)
			if i == parts.size() - 1:
				return str(value)
			if value is Object:
				current = value as Object
			else:
				return "{" + variable_name + "}"
		return "{" + variable_name + "}"

	# example: {ammo}
	var direct_value: Variant

	if has_property(item, variable_name):
		direct_value = item.get(variable_name)
		return str(direct_value)
	for child: Node in item.find_children("*", "", true, false):
		if has_property(child, variable_name):
			direct_value = child.get(variable_name)
			return str(direct_value)

	return "{" + variable_name + "}"

func has_property(object: Object, property_name: String) -> bool:
	if object == null:
		return false
	for property_info: Dictionary in object.get_property_list():
		var name_variant: Variant = property_info.get("name")
		if String(name_variant) == property_name:
			return true

	return false
