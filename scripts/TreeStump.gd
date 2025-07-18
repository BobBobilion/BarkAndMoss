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
	return "Chop Tree"


func take_damage(damage_amount: int, damager: Node3D = null):
	if is_chopped:
		return

	chop_count += damage_amount
	print("Tree chopped ", chop_count, "/", MAX_CHOPS, " times | Damager: ", damager.name if damager else "None")
	
	if chop_count >= MAX_CHOPS:
		print("Tree fully chopped! Calling _chop_tree with damager: ", damager.name if damager else "None")
		_chop_tree(damager)

func _on_interacted(player: Node) -> void:
	"""Handles the interaction event when a player chops the stump."""
	# This is now deprecated in favor of take_damage, but we'll keep it for now.
	pass


# --- Private Methods ---

func _chop_tree(chopper: Node3D = null) -> void:
	"""
	Handles the final chop, disabling the stump and playing a falling and fading animation.
	Rewards the player who chopped it with wood.
	This is the most robust implementation for fading materials.
	"""
	is_chopped = true
	
	# Reward the player who chopped the tree with wood
	print("TreeStump: Attempting to reward wood. Chopper: ", chopper.name if chopper else "None")
	if chopper:
		print("TreeStump: Chopper has add_item_to_inventory method: ", chopper.has_method("add_item_to_inventory"))
		if chopper.has_method("add_item_to_inventory"):
			var wood_reward: int = 2  # Trees give 2 wood when chopped
			for i in range(wood_reward):
				print("TreeStump: Attempting to add Wood #", i+1)
				if chopper.add_item_to_inventory("Wood"):
					print("TreeStump: Successfully gave 1 Wood to ", chopper.name)
				else:
					print("TreeStump: Player inventory full, couldn't give wood")
					break
		else:
			print("TreeStump: ERROR - Chopper doesn't have add_item_to_inventory method!")
	else:
		print("TreeStump: ERROR - No chopper reference passed!")
	
	# Disable interaction and future physics checks immediately to prevent re-triggering.
	if is_instance_valid(interactable):
		# The interactable node is an Area3D, which has these properties directly.
		# We avoid the 'as Interactable' cast that was causing the parser to fail.
		# Use deferred calls to avoid physics signal blocking
		interactable.set_deferred("monitoring", false)
		interactable.set_deferred("monitorable", false)
	# Defer collision shape disabling to avoid physics callback issues
	collision_shape.set_deferred("disabled", true)
	
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
