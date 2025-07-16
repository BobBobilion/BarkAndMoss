class_name TreeStump
extends StaticBody3D

# --- Scripts ---
const PlayerScript: Script = preload("res://scripts/Player.gd")

# --- Constants ---
const MAX_CHOPS: int = 3
const CHOP_SCALE_FACTOR: float = 0.2
const FADE_OUT_DURATION: float = 1.0

# --- Node References ---
@onready var interactable = $Interactable
@onready var visuals: Node3D = $Visuals
@onready var collision_shape: CollisionShape3D = $CollisionShape

# --- State ---
var chop_count: int = 0
var is_chopped: bool = false


# --- Engine Callbacks ---

func _ready() -> void:
	"""Connects signals and initializes the node."""
	# Add this node to the interactable group so the Player can detect it
	add_to_group("interactable")
	
	# The parser is failing to find the Interactable type, so we resort to duck-typing.
	# We know from the scene setup that this node has the 'interacted' signal.
	if interactable and interactable.has_signal("interacted"):
		interactable.interacted.connect(_on_interacted)


# --- Signal Handlers ---

func get_interaction_prompt() -> String:
	"""Returns the interaction prompt text for this tree."""
	if is_chopped:
		return ""
	return "Chop Tree (Requires Hatchet)"


func _on_interacted(player: Node) -> void:
	"""Handles the interaction event when a player chops the stump."""
	if is_chopped:
		return

	# Check if the interacting node is a player and if they have a hatchet equipped
	# We use duck-typing here (has_method) to avoid the parser error with the "Player" type.
	if player.has_method("get_equipped_item") and player.get_equipped_item() == "Hatchet":
		# Trigger chopping animation on the player
		if player.has_method("start_chopping_animation"):
			player.start_chopping_animation()
		
		chop_count += 1
		print("Tree chopped ", chop_count, "/", MAX_CHOPS, " times")
		
		if chop_count >= MAX_CHOPS:
			_chop_tree()
	else:
		print("Need a hatchet to chop this tree!")


# --- Private Methods ---

func _chop_tree() -> void:
	"""
	Handles the final chop, disabling the stump and playing a falling and fading animation.
	This is the most robust implementation for fading materials.
	"""
	is_chopped = true
	
	# Disable interaction and future physics checks immediately to prevent re-triggering.
	if is_instance_valid(interactable):
		# The interactable node is an Area3D, which has these properties directly.
		# We avoid the 'as Interactable' cast that was causing the parser to fail.
		# Use deferred calls to avoid physics signal blocking
		interactable.set_deferred("monitoring", false)
		interactable.set_deferred("monitorable", false)
	collision_shape.disabled = true
	
	# --- Create a new Tween for the animation ---
	var tween: Tween = create_tween().set_parallel(true)
	
	# 1. Random Fall Animation
	var fall_direction := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
	var rotation_axis: Vector3 = fall_direction.cross(Vector3.UP)
	tween.tween_property(visuals, "rotation", visuals.rotation + rotation_axis * (PI / 2), FADE_OUT_DURATION).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	
	# 2. Fade Out Animation
	# Iterate through all mesh instances, make their materials unique, and fade them out.
	for node in visuals.get_children():
		if node is MeshInstance3D:
			var mesh_instance := node as MeshInstance3D
			if not mesh_instance.mesh:
				continue # Skip if there's no mesh to process.

			# Iterate over every material surface on the mesh.
			for i in range(mesh_instance.mesh.get_surface_count()):
				var material = mesh_instance.get_active_material(i)
				if material is StandardMaterial3D:
					# Duplicate the material to ensure we only affect this one tree.
					var material_instance = material.duplicate() as StandardMaterial3D
					mesh_instance.set_surface_override_material(i, material_instance)
					
					# Set transparency mode. This is crucial for alpha to work.
					material_instance.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					
					# Create the transparent end color and tween to it.
					var end_color := Color(material_instance.albedo_color, 0.0)
					tween.tween_property(material_instance, "albedo_color", end_color, FADE_OUT_DURATION)

	# 3. Queue Free after the entire animation is complete.
	tween.tween_callback(queue_free) 
