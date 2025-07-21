class_name RabbitCorpse
extends StaticBody3D

# --- Constants ---
const INTERACTION_PROMPT: String = "E: Process | Bite: Grab"

# --- Rabbit Model ---
const RABBIT_SCENE: PackedScene = preload("res://assets/animals/low_poly_rabbit_brown.glb")

# --- Node References ---
@onready var rabbit_corpse_model: Node3D = $RabbitCorpseModel
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var interactable: Area3D = $Interactable

# --- State ---
var is_grabbed: bool = false
var grabber: Node3D = null

# Export for interaction prompt
@export var interaction_prompt: String = INTERACTION_PROMPT


func _ready() -> void:
	"""Initialize the rabbit corpse with proper collision and interaction."""
	# Set up collision layers - corpses are interactable objects
	collision_layer = 16    # Corpse layer
	collision_mask = 0      # Corpses don't need to collide with anything
	
	# Add to interactable group
	add_to_group("interactable")
	add_to_group("corpses")
	
	# Set the corpse to death animation pose (non-looping)
	_setup_death_pose()
	
	# Connect interaction signals
	if interactable:
		interactable.interacted.connect(_on_interacted)


func _on_interacted(player: Node3D) -> void:
	"""Handle interaction with the corpse."""
	if is_grabbed:
		return
	
	# Check if it's a human player with an axe (for processing)
	if player.is_in_group("human_player"):
		_process_corpse(player)
	# Check if it's a dog player (for grabbing)
	elif player.is_in_group("dog_player"):
		_grab_corpse(player)


func _process_corpse(human_player: Node3D) -> void:
	"""Process the corpse to get meat and sinew (human with axe)."""
	# Check if the human has an axe equipped  
	if human_player.has_method("get_equipped_item") and human_player.get_equipped_item() == "Axe":
		print("Processing rabbit corpse for meat and sinew")
		
		# Play processing animation
		if human_player.has_method("start_chopping_animation"):
			human_player.start_chopping_animation()
		
		# Add raw meat and sinew to player's inventory
		var success: bool = true
		if human_player.has_method("add_item_to_inventory"):
			success = human_player.add_item_to_inventory("Raw Meat") and success
			success = human_player.add_item_to_inventory("Sinew") and success
		
		if success:
			print("Rabbit processed: gained Raw Meat and Sinew")
			
			# Sync corpse removal to other players
			if multiplayer.has_multiplayer_peer():
				var corpse_path = get_path()
				_sync_corpse_harvested.rpc(corpse_path)
			
			# Remove the corpse after processing
			queue_free()
		else:
			print("Inventory full - could not process corpse")
	else:
		print("Need an axe to process the corpse")


@rpc("any_peer", "call_remote", "reliable")
func _sync_corpse_harvested(corpse_path: NodePath) -> void:
	"""Sync corpse removal to other players."""
	print("RabbitCorpse: Received corpse harvest sync for ", corpse_path)
	var corpse = get_node_or_null(corpse_path)
	if corpse and corpse == self:
		queue_free()


func _grab_corpse(dog_player: Node3D) -> void:
	"""Allow the dog to grab and drag the corpse."""
	if is_grabbed:
		return
	
	is_grabbed = true
	grabber = dog_player
	
	# The dog will handle positioning the corpse
	# We just need to track that we're being grabbed


func get_interaction_prompt() -> String:
	"""Return the interaction prompt for this corpse."""
	return interaction_prompt


func release() -> void:
	"""Release the corpse from the grabber."""
	if not is_grabbed:
		return
	
	print("Released rabbit corpse")
	is_grabbed = false
	grabber = null


func _process(delta: float) -> void:
	"""Update corpse - no longer need to follow grabber as dog handles positioning."""
	pass








func _setup_death_pose() -> void:
	"""Set the rabbit corpse to the death animation pose."""
	if rabbit_corpse_model:
		var animation_player: AnimationPlayer = _find_animation_player_recursive(rabbit_corpse_model)
		if animation_player:
			# Try to find and play the death animation
			var death_animations: Array[String] = ["Armature_001|Die", "Armature.001|Die", "Armature|Die", "Die", "die", "Death", "death"]
			
			for anim_name in death_animations:
				if animation_player.has_animation(anim_name):
					animation_player.play(anim_name)
					# Stop the animation at the end frame to keep the death pose
					await animation_player.animation_finished
					animation_player.stop()
					break


func _find_animation_player_recursive(node: Node) -> AnimationPlayer:
	"""Recursively search for an AnimationPlayer node in the corpse model."""
	if node is AnimationPlayer:
		return node as AnimationPlayer
	
	for child in node.get_children():
		var result: AnimationPlayer = _find_animation_player_recursive(child)
		if result:
			return result
	
	return null 