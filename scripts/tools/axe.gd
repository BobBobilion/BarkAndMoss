class_name Axe
extends Node3D

signal hit_something(body: Node3D)

@onready var hitbox: Area3D = $Hitbox
@onready var collision_shape: CollisionShape3D = $Hitbox/CollisionShape3D

# Track bodies already hit during current swing to prevent multiple hits
var bodies_hit_this_swing: Array[Node3D] = []

func _ready() -> void:
	# Connect the body_entered signal to our handler
	if hitbox:
		hitbox.body_entered.connect(_on_hitbox_body_entered)
	# Start with hitbox disabled
	set_hitbox_enabled(false)

func _on_hitbox_body_entered(body: Node3D) -> void:
	# Check if we've already hit this body during this swing
	if body in bodies_hit_this_swing:
		return  # Skip if already hit
	
	# Add to hit list and emit signal
	bodies_hit_this_swing.append(body)
	hit_something.emit(body)

func set_hitbox_enabled(is_enabled: bool) -> void:
	# Enable/disable the collision shape
	if collision_shape:
		collision_shape.disabled = not is_enabled
	# Also set monitoring on the Area3D for extra safety
	if hitbox:
		hitbox.monitoring = is_enabled
	
	# Clear the hit list when enabling (starting a new swing)
	if is_enabled:
		bodies_hit_this_swing.clear()
	# Also clear when disabling to free memory
	else:
		bodies_hit_this_swing.clear() 