# GameUtils.gd
# Utility functions and error handling patterns for the Bark & Moss game
# This file contains reusable utility functions to improve code robustness

class_name GameUtils
extends RefCounted

# =============================================================================
# ERROR HANDLING UTILITIES
# =============================================================================

## Safely gets a node with null checking and error logging
static func safe_get_node(base_node: Node, path: String, error_context: String = "") -> Node:
	if not is_instance_valid(base_node):
		push_error("GameUtils: Base node is invalid in context: " + error_context)
		return null
	
	var node = base_node.get_node_or_null(path)
	if not node:
		push_warning("GameUtils: Could not find node at path '%s' in context: %s" % [path, error_context])
	
	return node

## Safely calls a method on a node with existence checking
static func safe_call_method(node: Node, method_name: String, args: Array = []) -> Variant:
	if not is_instance_valid(node):
		push_warning("GameUtils: Cannot call method '%s' - node is invalid" % method_name)
		return null
	
	if not node.has_method(method_name):
		push_warning("GameUtils: Node '%s' does not have method '%s'" % [node.name, method_name])
		return null
	
	match args.size():
		0: return node.call(method_name)
		1: return node.call(method_name, args[0])
		2: return node.call(method_name, args[0], args[1])
		3: return node.call(method_name, args[0], args[1], args[2])
		_: return node.callv(method_name, args)

## Safely connects a signal with duplicate checking
static func safe_connect_signal(source: Object, signal_name: String, target: Object, method_name: String, error_context: String = "") -> bool:
	if not is_instance_valid(source):
		push_error("GameUtils: Source object is invalid for signal connection in context: " + error_context)
		return false
	
	if not is_instance_valid(target):
		push_error("GameUtils: Target object is invalid for signal connection in context: " + error_context)
		return false
	
	if not source.has_signal(signal_name):
		push_error("GameUtils: Source object does not have signal '%s' in context: %s" % [signal_name, error_context])
		return false
	
	if not target.has_method(method_name):
		push_error("GameUtils: Target object does not have method '%s' in context: %s" % [method_name, error_context])
		return false
	
	# Check if already connected to prevent duplicate connections
	if source.is_connected(signal_name, Callable(target, method_name)):
		push_warning("GameUtils: Signal '%s' already connected to '%s' in context: %s" % [signal_name, method_name, error_context])
		return true
	
	var error = source.connect(signal_name, Callable(target, method_name))
	if error != OK:
		push_error("GameUtils: Failed to connect signal '%s' to '%s' (error %d) in context: %s" % [signal_name, method_name, error, error_context])
		return false
	
	return true

## Validates multiplayer authority safely
static func is_local_authority(node: Node, multiplayer_ref: MultiplayerAPI = null) -> bool:
	if not is_instance_valid(node):
		return false
	
	# If no multiplayer reference provided, try to get it from the node
	if not multiplayer_ref:
		var tree = node.get_tree()
		if tree:
			multiplayer_ref = tree.multiplayer
		else:
			return true  # Assume local authority if no tree
	
	# Handle single-player mode or when multiplayer peer is null/freed
	if not multiplayer_ref.has_multiplayer_peer() or not multiplayer_ref.multiplayer_peer:
		return true
	
	return node.is_multiplayer_authority()

# =============================================================================
# SCENE MANAGEMENT UTILITIES
# =============================================================================

## Safely changes scene with error checking
static func safe_change_scene(scene_path: String, scene_tree: SceneTree, error_context: String = "") -> bool:
	if not ResourceLoader.exists(scene_path):
		push_error("GameUtils: Invalid scene path '%s' in context: %s" % [scene_path, error_context])
		return false
	
	if not scene_tree:
		push_error("GameUtils: SceneTree is null in context: %s" % error_context)
		return false
	
	var error = scene_tree.change_scene_to_file(scene_path)
	if error != OK:
		push_error("GameUtils: Failed to change scene to '%s' (error %d) in context: %s" % [scene_path, error, error_context])
		return false
	
	return true

## Safely instantiates a scene with error checking
static func safe_instantiate_scene(scene_path: String, error_context: String = "") -> Node:
	if not ResourceLoader.exists(scene_path):
		push_error("GameUtils: Invalid scene path '%s' in context: %s" % [scene_path, error_context])
		return null
	
	var scene = load(scene_path) as PackedScene
	if not scene:
		push_error("GameUtils: Failed to load scene '%s' in context: %s" % [scene_path, error_context])
		return null
	
	var instance = scene.instantiate()
	if not instance:
		push_error("GameUtils: Failed to instantiate scene '%s' in context: %s" % [scene_path, error_context])
		return null
	
	return instance

# =============================================================================
# ANIMATION UTILITIES
# =============================================================================

## Safely plays an animation with error checking
static func safe_play_animation(animation_player: AnimationPlayer, animation_name: String, blend_time: float = 0.2) -> bool:
	if not is_instance_valid(animation_player):
		push_warning("GameUtils: AnimationPlayer is invalid")
		return false
	
	if not animation_player.has_animation(animation_name):
		push_warning("GameUtils: Animation '%s' not found in AnimationPlayer" % animation_name)
		return false
	
	if animation_player.is_playing() and animation_player.current_animation == animation_name:
		return true  # Already playing the correct animation
	
	animation_player.play(animation_name, blend_time)
	return true

# =============================================================================
# PHYSICS UTILITIES
# =============================================================================

## Sets up collision layers safely with validation
static func setup_collision_layers(body: CollisionObject3D, layer: int, mask: int, error_context: String = "") -> bool:
	if not is_instance_valid(body):
		push_error("GameUtils: CollisionObject3D is invalid in context: " + error_context)
		return false
	
	# Validate layer and mask values (1-32 range for Godot)
	if layer < 1 or layer > 32:
		push_error("GameUtils: Invalid collision layer %d (must be 1-32) in context: %s" % [layer, error_context])
		return false
	
	if mask < 0 or mask > 0xFFFFFFFF:  # 32-bit mask
		push_error("GameUtils: Invalid collision mask %d in context: %s" % [mask, error_context])
		return false
	
	body.collision_layer = layer
	body.collision_mask = mask
	return true

## Gets terrain height safely with fallback
static func get_terrain_height_safe(world_generator: Node, position: Vector3, fallback_height: float = 0.0) -> float:
	if not is_instance_valid(world_generator):
		return fallback_height
	
	if not world_generator.has_method("get_terrain_height_at_position"):
		return fallback_height
	
	return world_generator.get_terrain_height_at_position(position)

# =============================================================================
# INPUT UTILITIES
# =============================================================================

## Safely handles mouse mode changes
static func safe_set_mouse_mode(mode: Input.MouseMode, error_context: String = "") -> bool:
	# Validate the mouse mode before setting
	if mode < Input.MOUSE_MODE_VISIBLE or mode > Input.MOUSE_MODE_CONFINED_HIDDEN:
		push_error("GameUtils: Invalid mouse mode %d in context: %s" % [mode, error_context])
		return false
	
	Input.set_mouse_mode(mode)
	return true

# =============================================================================
# INVENTORY UTILITIES
# =============================================================================

## Safely adds items to inventory with validation
static func safe_add_to_inventory(inventory: Object, item_name: String, quantity: int = 1) -> bool:
	if not is_instance_valid(inventory):
		push_warning("GameUtils: Inventory object is invalid")
		return false
	
	if not inventory.has_method("add_item"):
		push_warning("GameUtils: Inventory object does not have add_item method")
		return false
	
	if item_name.is_empty():
		push_warning("GameUtils: Cannot add empty item name to inventory")
		return false
	
	if quantity <= 0:
		push_warning("GameUtils: Cannot add non-positive quantity (%d) to inventory" % quantity)
		return false
	
	return safe_call_method(inventory, "add_item", [item_name, quantity])

## Safely removes items from inventory with validation
static func safe_remove_from_inventory(inventory: Object, item_name: String, quantity: int = 1) -> bool:
	if not is_instance_valid(inventory):
		push_warning("GameUtils: Inventory object is invalid")
		return false
	
	if not inventory.has_method("remove_item"):
		push_warning("GameUtils: Inventory object does not have remove_item method")
		return false
	
	if item_name.is_empty():
		push_warning("GameUtils: Cannot remove empty item name from inventory")
		return false
	
	if quantity <= 0:
		push_warning("GameUtils: Cannot remove non-positive quantity (%d) from inventory" % quantity)
		return false
	
	return safe_call_method(inventory, "remove_item", [item_name, quantity])

# =============================================================================
# MATH UTILITIES
# =============================================================================

## Safely clamps a value with validation
static func safe_clamp(value: float, min_val: float, max_val: float) -> float:
	if min_val > max_val:
		push_warning("GameUtils: min_val (%f) is greater than max_val (%f), swapping" % [min_val, max_val])
		var temp = min_val
		min_val = max_val
		max_val = temp
	
	return clamp(value, min_val, max_val)

## Gets distance between nodes safely
static func safe_distance_to(node1: Node3D, node2: Node3D) -> float:
	if not is_instance_valid(node1) or not is_instance_valid(node2):
		return INF
	
	return node1.global_position.distance_to(node2.global_position)

# =============================================================================
# STRING UTILITIES
# =============================================================================

## Formats log messages consistently
static func format_log(component: String, message: String, level: String = "INFO") -> String:
	return "[%s] %s: %s" % [level, component, message]

## Safely converts enum to string
static func enum_to_string(enum_dict: Dictionary, value: int, fallback: String = "UNKNOWN") -> String:
	for key in enum_dict:
		if enum_dict[key] == value:
			return key
	return fallback

# =============================================================================
# DEBUGGING UTILITIES
# =============================================================================

## Prints debug info for a node hierarchy
static func debug_node_hierarchy(node: Node, depth: int = 0, max_depth: int = 3) -> void:
	if not is_instance_valid(node) or depth > max_depth:
		return
	
	var indent = "  ".repeat(depth)
	print("%s%s (%s)" % [indent, node.name, node.get_class()])
	
	for child in node.get_children():
		debug_node_hierarchy(child, depth + 1, max_depth)

## Validates node setup for common requirements
static func validate_node_setup(node: Node, required_children: Array[String] = []) -> bool:
	if not is_instance_valid(node):
		push_error("GameUtils: Node is invalid during validation")
		return false
	
	var valid = true
	
	for child_path in required_children:
		var child = node.get_node_or_null(child_path)
		if not child:
			push_error("GameUtils: Required child '%s' not found in node '%s'" % [child_path, node.name])
			valid = false
	
	return valid 