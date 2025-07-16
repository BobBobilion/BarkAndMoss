extends Area3D
class_name Interactable

# --- Constants ---
const INTERACTION_COLLISION_LAYER: int = 2

# --- Signals ---
signal interacted(player: Node)

# --- Properties ---
@export var interaction_prompt: String = "Press E to Interact"


func _ready() -> void:
	"""
	Called when the node is added to the scene.
	Sets up the collision layer for interaction detection.
	"""
	# Ensure proper collision setup for interaction detection
	collision_layer = INTERACTION_COLLISION_LAYER
	collision_mask = 0   # Don't need to detect anything
	set_deferred("monitoring", false)   # Use deferred to avoid physics signal blocking
	set_deferred("monitorable", true)   # Use deferred to avoid physics signal blocking


func perform_interaction(player: Node) -> void:
	"""
	Emits the 'interacted' signal. This method is the primary way to trigger
	an interaction with this object.
	"""
	if player:
		interacted.emit(player) 
