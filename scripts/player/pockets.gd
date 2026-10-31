extends Node2D

@onready var slot1: Marker2D = $Slot1
@onready var slot2: Marker2D = $Slot2
@onready var controller = get_parent()

var slots: Array = [null, null]
var slot1_pressed := false
var slot2_pressed := false

func _ready():
	if NetworkManager.is_networked():
		NetworkManager.server_message.connect(_on_server_message)

func _controller_value(property_name: String, fallback: Variant = null) -> Variant:
	if controller == null or not is_instance_valid(controller):
		return fallback
	for property_info: Dictionary in controller.get_property_list():
		if str(property_info.get("name", "")) == property_name:
			return controller.get(property_name)
	return fallback

func _on_server_message(peer_id: int, message: Dictionary):
	if not NetworkManager.is_server() or peer_id != int(_controller_value("network_player_id", -1)):
		return
	if message.get("kind", "") != "pockets" or message.get("action", "") != "toggle":
		return
	var slot := int(message.get("slot", -1))
	if slot < 0 or slot > 1:
		return
	toggle_slot(slot, message.get("left_active", false) == true, message.get("right_active", false) == true, true)

func _process(_delta):
	var is_local: bool = bool(_controller_value("local_player", false))
	if NetworkManager.is_networked() and not is_local:
		return
	if bool(_controller_value("chat_input_active", false)):
		slot1_pressed = Input.is_key_pressed(KEY_1)
		slot2_pressed = Input.is_key_pressed(KEY_2)
		return
	var key1 := Input.is_key_pressed(KEY_1)
	var key2 := Input.is_key_pressed(KEY_2)
	if key1 and not slot1_pressed:
		if NetworkManager.is_client() and is_local:
			NetworkManager.send_to_server({"kind": "pockets", "action": "toggle", "slot": 0, "left_active": Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT), "right_active": Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)})
		else:
			toggle_slot(0)
	if key2 and not slot2_pressed:
		if NetworkManager.is_client() and is_local:
			NetworkManager.send_to_server({"kind": "pockets", "action": "toggle", "slot": 1, "left_active": Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT), "right_active": Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)})
		else:
			toggle_slot(1)

	slot1_pressed = key1
	slot2_pressed = key2

func toggle_slot(index: int, left_active: bool = false, right_active: bool = false, network_input: bool = false):
	if index < 0 or index >= slots.size():
		return
	if slots[index] != null:
		take_from_slot(index, left_active, right_active, network_input)
		return
	store_to_slot(index, left_active, right_active, network_input)

func store_to_slot(index: int, left_active: bool = false, right_active: bool = false, network_input: bool = false):
	if not network_input:
		left_active = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		right_active = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var item = null

	if left_active and right_active:
		if index == 0:
			item = controller.left_item
		else:
			item = controller.right_item

	elif left_active:
		item = controller.left_item
	elif right_active:
		item = controller.right_item
	else:
		return

	if item == null:
		return
	var slot := get_slot(index)

	if slot == null:
		return

	if item.has_method("store_in_pocket"):
		if item.store_in_pocket(slot):
			slots[index] = item
			if controller.left_item == item:
				controller.left_item = null
			if controller.right_item == item:
				controller.right_item = null

func take_from_slot(index: int, left_active: bool = false, right_active: bool = false, network_input: bool = false):
	var item = slots[index]
	if item == null:
		return
		
	if not network_input:
		left_active = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		right_active = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var hand_marker: Marker2D = null
	var target_hand = null

	if left_active and right_active:
		if index == 0:
			if controller.left_item != null:
				return
			target_hand = controller.left_hand_marker
			hand_marker = controller.left_hand_marker
		else:
			if controller.right_item != null:
				return
			target_hand = controller.right_hand_marker
			hand_marker = controller.right_hand_marker

	elif left_active:
		if controller.left_item != null:
			return
		target_hand = controller.left_hand_marker
		hand_marker = controller.left_hand_marker

	elif right_active:
		if controller.right_item != null:
			return
		target_hand = controller.right_hand_marker
		hand_marker = controller.right_hand_marker
	else:
		return
		
	if target_hand == null or hand_marker == null:
		return
	if item.has_method("take_from_pocket"):
		if item.take_from_pocket(hand_marker):
			slots[index] = null
			if target_hand == controller.left_hand_marker:
				controller.left_item = item
			elif target_hand == controller.right_hand_marker:
				controller.right_item = item


func drop_all():
	for index in range(slots.size()):
		var item: Variant = slots[index]
		slots[index] = null
		if item == null or not is_instance_valid(item):
			continue
		if item.has_method("drop_from_pocket"):
			item.call("drop_from_pocket")
		else:
			GC.destroy(item)

func set_network_slot(index: int, item: Node):
	if index >= 0 and index < slots.size():
		slots[index] = item

func clear_network_item(item: Node):
	for i in slots.size():
		if slots[i] == item:
			slots[i] = null

func get_slot(index: int) -> Marker2D:
	if index == 0:
		return slot1
	if index == 1:
		return slot2

	return null
