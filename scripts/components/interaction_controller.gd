class_name InteractionController
extends Node

# --- Properties ---
var interaction_area: Area3D
var player_body: CharacterBody3D
var overlapping_interactables: Array[Node] = []

# --- Initialization ---
func setup(p_interaction_area: Area3D, p_player_body: CharacterBody3D) -> void:
	self.interaction_area = p_interaction_area
	self.player_body = p_player_body
	if interaction_area:
		interaction_area.area_entered.connect(_on_area_entered)
		interaction_area.area_exited.connect(_on_area_exited)
	else:
		push_error("InteractionController: InteractionArea not assigned.")
	if not player_body:
		push_error("InteractionController: Player CharacterBody3D not assigned.")

# --- Public Methods ---
func handle_interaction_input() -> Node:
	if Input.is_action_just_pressed("interact"):
		print("InteractionController: 'interact' action pressed")
		var closest = get_closest_interactable()
		print("InteractionController: Closest interactable = ", closest.name if closest else "None")
		return closest
	return null

func get_closest_interactable() -> Node:
	# Commented out debug prints - too spammy for every frame
	# print("InteractionController: get_closest_interactable called")
	# print("  overlapping_interactables.size() = ", overlapping_interactables.size())
	# for item in overlapping_interactables:
	# 	print("  - ", item.name if is_instance_valid(item) else "INVALID")
	
	if overlapping_interactables.is_empty():
		return null
	
	var closest: Node = null
	var closest_distance_sq: float = INF
	
	for i in range(overlapping_interactables.size() - 1, -1, -1):
		var interactable = overlapping_interactables[i]
		if not is_instance_valid(interactable):
			overlapping_interactables.remove_at(i)
			continue
			
		var distance_sq: float = player_body.global_position.distance_squared_to(interactable.global_position)
		if distance_sq < closest_distance_sq:
			closest_distance_sq = distance_sq
			closest = interactable
	
	# print("  Returning closest: ", closest.name if closest else "None")  # Too spammy
	return closest

func get_interaction_prompt(interactable: Node) -> String:
	if interactable and interactable.has_method("get_interaction_prompt"):
		return interactable.get_interaction_prompt()
	return ""

func interact_with_object(interactable: Node, instigator: Node) -> void:
	if not interactable:
		return

	if interactable.has_signal("interacted"):
		interactable.emit_signal("interacted", instigator)
	elif interactable.has_method("_on_interacted"):
		interactable._on_interacted(instigator)

# --- Signal Handlers ---
func _on_area_entered(area: Area3D) -> void:
	var interactable: Node = area.get_parent()
	print("InteractionController: Area entered - Area name: '", area.name, "' Parent: '", interactable.name, "'")
	print("  Parent has get_interaction_prompt: ", interactable.has_method("get_interaction_prompt"))
	print("  Parent is in interactable group: ", interactable.is_in_group("interactable"))
	
	# Check if this parent is already in our list to avoid duplicates
	if interactable in overlapping_interactables:
		print("  WARNING: Parent already in overlapping_interactables! Not adding duplicate.")
		return
	
	if interactable.has_method("get_interaction_prompt") or interactable.is_in_group("interactable"):
		overlapping_interactables.append(interactable)
		print("  Added to overlapping_interactables. Count: ", overlapping_interactables.size())

func _on_area_exited(area: Area3D) -> void:
	var interactable: Node = area.get_parent()
	print("InteractionController: Area exited - ", area.name, " Parent: ", interactable.name)
	if interactable in overlapping_interactables:
		overlapping_interactables.erase(interactable)
		print("  Removed from overlapping_interactables. Count: ", overlapping_interactables.size()) 