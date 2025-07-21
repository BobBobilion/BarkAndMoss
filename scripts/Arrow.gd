class_name Arrow
extends RigidBody3D

# --- Constants ---
const ARROW_SPEED: float = 20.0
const ARROW_LIFETIME: float = 10.0
const ARROW_DAMAGE: float = 100.0  # Instant kill for animals
const GRAVITY_SCALE: float = 0.5  # Make arrows slightly less affected by gravity

# --- Node References ---
@onready var arrow_model: Node3D = $ArrowModel
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var area_detector: Area3D = $AreaDetector

# --- State ---
var has_hit: bool = false
var shooter: Node3D = null


func _ready() -> void:
	"""Initialize the arrow projectile with physics and collision detection."""
	# Set up collision layers - arrows should collide with terrain and animals
	collision_layer = 4  # Arrow layer
	collision_mask = 1 | 8  # Collide with terrain (1) and animals (8)
	
	# Configure physics
	gravity_scale = GRAVITY_SCALE
	contact_monitor = true
	max_contacts_reported = 10
	
	# Connect collision signals
	body_entered.connect(_on_body_entered)
	if area_detector:
		area_detector.body_entered.connect(_on_area_body_entered)
		area_detector.area_entered.connect(_on_area_area_entered)
	
	# Auto-destroy after lifetime expires
	var timer: Timer = Timer.new()
	timer.wait_time = ARROW_LIFETIME
	timer.timeout.connect(_destroy_arrow)
	timer.one_shot = true
	add_child(timer)
	timer.start()


func launch(direction: Vector3, speed: float = ARROW_SPEED) -> void:
	"""Launch the arrow in the specified direction with the given speed."""
	# Apply initial velocity
	linear_velocity = direction.normalized() * speed
	
	# Align arrow with its direction of travel - avoid colinear vectors and same position
	var target_look_pos: Vector3 = global_position + direction
	
	# Ensure target position is sufficiently different from current position
	if global_position.distance_to(target_look_pos) > 0.01:
		var up_vector: Vector3 = Vector3.UP
		
		# Check if direction is parallel to up vector (avoid colinear warning)
		if abs(direction.dot(up_vector)) > 0.99:
			up_vector = Vector3.FORWARD  # Use forward as up vector instead
		
		look_at(target_look_pos, up_vector)


func _on_body_entered(body: Node) -> void:
	"""Handle collision with terrain or other solid objects."""
	if has_hit or body == shooter:
		return
	
	_stick_to_surface(body)


func _on_area_body_entered(body: Node3D) -> void:
	"""Handle collision with animal bodies through the area detector."""
	if has_hit or body == shooter:
		return
	
	# Check if this is an animal
	if body.is_in_group("animals"):
		_hit_animal(body)


func _on_area_area_entered(area: Area3D) -> void:
	"""Handle collision with animal areas or other area-based targets."""
	if has_hit:
		return
	
	# Check if this area belongs to an animal
	var parent: Node = area.get_parent()
	if parent and parent.is_in_group("animals"):
		_hit_animal(parent)


func _hit_animal(animal: Node) -> void:
	"""Handle hitting an animal - deal damage and stick arrow."""
	if has_hit:
		return
	
	has_hit = true
	
	# Get animal ID for multiplayer sync
	var animal_id = animal.get_meta("animal_id", -1)
	
	# Only the player who shot the arrow should deal damage
	if shooter and shooter.has_method("get_multiplayer_authority"):
		var shooter_id = shooter.get_multiplayer_authority()
		if multiplayer.get_unique_id() == shooter_id:
			# Deal damage to the animal
			if animal.has_method("take_damage"):
				animal.take_damage(ARROW_DAMAGE)
			elif animal.has_method("die"):
				animal.die()
			
			# Notify other players that this animal was hit
			if multiplayer.has_multiplayer_peer() and animal_id != -1:
				_sync_animal_hit.rpc(animal_id, ARROW_DAMAGE)
	
	# Stop the arrow's physics
	set_freeze_mode(RigidBody3D.FREEZE_MODE_KINEMATIC)
	freeze = true
	
	# Stick the arrow to the animal - use deferred to avoid physics callback issues
	if animal.has_method("add_child"):
		# Reparent the arrow to the animal so it moves with it (deferred)
		var old_transform: Transform3D = global_transform
		var current_parent = get_parent()
		
		# Use call_deferred to safely reparent during physics callback
		call_deferred("_reparent_to_animal", animal, current_parent, old_transform)
	
	print("Arrow hit animal: ", animal.name)


@rpc("any_peer", "call_remote", "reliable")
func _sync_animal_hit(animal_id: int, damage: float) -> void:
	"""Sync animal hit to other players."""
	print("Arrow: Received animal hit sync for ID ", animal_id, " with damage ", damage)


func _stick_to_surface(surface: Node) -> void:
	"""Make the arrow stick to a surface like terrain or trees."""
	if has_hit:
		return
	
	has_hit = true
	
	# Stop the arrow's physics
	set_freeze_mode(RigidBody3D.FREEZE_MODE_KINEMATIC)
	freeze = true
	
	print("Arrow stuck to surface: ", surface.name)


func _destroy_arrow() -> void:
	"""Remove the arrow from the scene."""
	queue_free()


func set_shooter(new_shooter: Node3D) -> void:
	"""Set who shot this arrow to avoid self-collision."""
	shooter = new_shooter


func _reparent_to_animal(animal: Node, current_parent: Node, old_transform: Transform3D) -> void:
	"""Safely reparent the arrow to an animal outside of physics callback."""
	if is_instance_valid(animal) and is_instance_valid(current_parent):
		current_parent.remove_child(self)
		animal.add_child(self)
		global_transform = old_transform 
