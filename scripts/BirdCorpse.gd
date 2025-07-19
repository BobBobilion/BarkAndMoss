class_name BirdCorpse
extends StaticBody3D

# --- Constants ---
const INTERACTION_PROMPT: String = "E: Process | Bite: Grab"

# --- Node References ---
@onready var dove_corpse_model: Node3D = $DoveCorpseModel
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var interactable: Area3D = $Interactable

# --- State ---
var is_grabbed: bool = false
var grabber: Node3D = null

# Export for interaction prompt
@export var interaction_prompt: String = INTERACTION_PROMPT


func _ready() -> void:
	"""Initialize the bird corpse with proper collision and interaction."""
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
	
	# Check if it's a human player with an axe (for processing)
	if player.is_in_group("human_player"):
		_process_corpse(player)
	# Check if it's a dog player (for grabbing)
	elif player.is_in_group("dog_player"):
		_grab_corpse(player)


func _process_corpse(human_player: Node3D) -> void:
	"""Process the corpse to get meat and feathers (human with axe)."""
	# Check if the human has an axe equipped
	if human_player.has_method("get_equipped_item") and human_player.get_equipped_item() == "Axe":
		print("Processing bird corpse for meat and feathers")
		
		# Play processing animation
		if human_player.has_method("start_chopping_animation"):
			human_player.start_chopping_animation()
		
		# Add raw meat and feathers to player's inventory
		var success: bool = true
		if human_player.has_method("add_item_to_inventory"):
			# Add raw meat
			success = human_player.add_item_to_inventory("Raw Meat") and success
			
			# Add 2 feathers
			for i in range(2):
				success = human_player.add_item_to_inventory("Feather") and success
		
		if success:
			print("Bird processed: gained Raw Meat and 2 Feathers")
			# Remove the corpse after processing
			queue_free()
		else:
			print("Inventory full - could not process corpse")
	else:
		print("Need an axe to process the corpse")


func _grab_corpse(dog_player: Node3D) -> void:
	"""Allow the dog to grab and drag the corpse."""
	if is_grabbed:
		return
	
	print("Dog grabbed bird corpse")
	is_grabbed = true
	grabber = dog_player
	
	# The dog will handle positioning the corpse
	# We just need to track that we're being grabbed


func release() -> void:
	"""Release the corpse from the grabber."""
	if not is_grabbed:
		return
	
	print("Released bird corpse")
	is_grabbed = false
	grabber = null


func _process(delta: float) -> void:
	"""Update corpse - no longer need to follow grabber as dog handles positioning."""
	pass 