class_name GC
extends RefCounted

static func destroy(node: Node) -> void:
	if node == null:
		return
	if not is_instance_valid(node):
		return

	node.queue_free()

static func destroy_children(node: Node) -> void:
	if node == null:
		return
	if not is_instance_valid(node):
		return
	for child in node.get_children():
		if is_instance_valid(child):
			child.queue_free()

static func destroy_group(group_name: String, tree: SceneTree) -> void:
	if tree == null:
		return
	for node in tree.get_nodes_in_group(group_name):
		if is_instance_valid(node):
			node.queue_free()
