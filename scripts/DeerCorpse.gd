class_name DeerCorpse
extends StaticBody3D

# --- Constants ---
const INTERACTION_PROMPT: String = "E: Process | Bite: Grab"

# --- Node References ---
@onready var deer_corpse_model: Node3D = $DeerCorpseModel
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var interactable: Area3D = $Interactable

# --- State ---
var is_grabbed: bool = false
var grabber: Node3D = null

# Export for interaction prompt
@export var interaction_prompt: String = INTERACTION_PROMPT


func _ready() -> void:
	"""Initialize the deer corpse with proper collision and interaction."""
	# Set up collision layers - corpses are interactable objects
	collision_layer = 16    # Corpse layer
	collision_mask = 0      # Corpses don't need to collide with anything
	
	# Add to interactable group
	add_to_group("interactable")
	add_to_group("corpses")
	
	# Connect interaction signals
	if interactable:
		interactable.interacted.connect(_on_interacted)


func _on_interacted(player: Node3D) -> void:
	"""Handle interaction with the corpse."""
	if is_grabbed:
		return
	
	# Check if it's a human player with a hatchet (for processing)
	if player.is_in_group("human_player"):
		_process_corpse(player)
	# Check if it's a dog player (for grabbing)
	elif player.is_in_group("dog_player"):
		_grab_corpse(player)


func _process_corpse(player: Node3D) -> void:
	"""Process the deer corpse into raw meat (human with hatchet)."""
	# Check if the human has a hatchet equipped  
	if player.has_method("get_equipped_item") and player.get_equipped_item() == "Hatchet":
		print("Processing deer corpse for meat")
		
		# Play processing animation
		if player.has_method("start_chopping_animation"):
			player.start_chopping_animation()
		
		# Add multiple raw meat to player's inventory (deer gives more meat)
		var meat_count: int = 2  # Deer gives 2 raw meat
		var success: bool = true
		
		for i in range(meat_count):
			if player.has_method("add_item_to_inventory"):
				success = player.add_item_to_inventory("Raw Meat") and success
			else:
				success = false
				break
		
		if success:
			print("Deer processed: gained %d Raw Meat" % meat_count)
			# Remove the corpse after processing
			queue_free()
		else:
			print("Inventory full - could not process corpse")
	else:
		print("Need a hatchet to process the corpse")


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
	"""Release the deer corpse from being grabbed."""
	is_grabbed = false
	grabber = null
	collision_layer = 16  # Back to corpse layer
	print("Deer corpse released")


func _spawn_raw_meat(count: int) -> void:
	"""Spawn raw meat items when corpse is processed."""
	# This would integrate with the inventory system
	# For now, just print that meat was created
	print("Created ", count, " raw meat from deer corpse")
	
	# TODO: Add meat to player inventory when inventory system is ready
	if grabber and grabber.has_method("add_to_inventory"):
		for i in count:
			grabber.add_to_inventory("raw_meat") 
