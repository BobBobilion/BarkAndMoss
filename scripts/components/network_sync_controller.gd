class_name NetworkSyncController
extends Node

# Network synchronization controller for player movement
# This ensures smooth movement replication between host and clients

@export var sync_position_threshold: float = 0.1  # Minimum movement to trigger sync
@export var sync_rotation_threshold: float = 0.05  # Minimum rotation to trigger sync
@export var interpolation_speed: float = 15.0  # How fast to interpolate to target position

var last_synced_position: Vector3
var last_synced_rotation: Vector3
var target_position: Vector3
var target_rotation: Vector3
var is_local_player: bool = true

func _ready() -> void:
	# Determine if this is the local player
	var parent = get_parent()
	if parent and parent.has_method("is_multiplayer_authority"):
		is_local_player = not parent.multiplayer.has_multiplayer_peer() or parent.is_multiplayer_authority()
	
	# Initialize sync values
	if parent:
		last_synced_position = parent.position
		last_synced_rotation = parent.rotation
		target_position = parent.position
		target_rotation = parent.rotation

func _physics_process(delta: float) -> void:
	var parent = get_parent()
	if not parent:
		return
	
	if is_local_player:
		# Local player: Check if we need to sync our position
		_check_and_sync_transform(parent)
	else:
		# Remote player: Interpolate to received position
		_interpolate_to_target(parent, delta)

func _check_and_sync_transform(parent: Node3D) -> void:
	"""Check if position/rotation changed enough to warrant a sync."""
	var pos_diff = parent.position.distance_to(last_synced_position)
	var rot_diff = parent.rotation.distance_to(last_synced_rotation)
	
	# Only the authority should send updates
	if parent.multiplayer.has_multiplayer_peer() and parent.is_multiplayer_authority():
		if pos_diff > sync_position_threshold or rot_diff > sync_rotation_threshold:
			# Position or rotation changed significantly
			var velocity = Vector3.ZERO
			if parent is CharacterBody3D:
				velocity = parent.velocity
			_sync_transform_rpc.rpc(parent.position, parent.rotation, velocity)
			last_synced_position = parent.position
			last_synced_rotation = parent.rotation

func _interpolate_to_target(parent: Node3D, delta: float) -> void:
	"""Smoothly interpolate remote player to target position."""
	# Use different interpolation for position vs rotation
	parent.position = parent.position.lerp(target_position, interpolation_speed * delta)
	parent.rotation = parent.rotation.lerp(target_rotation, interpolation_speed * delta)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _sync_transform_rpc(pos: Vector3, rot: Vector3, vel: Vector3) -> void:
	"""Receive transform update from remote player."""
	var parent = get_parent()
	if not parent or parent.is_multiplayer_authority():
		return  # Don't process our own updates
	
	# Update target values for interpolation
	target_position = pos
	target_rotation = rot
	
	# If parent is a CharacterBody3D, update velocity for physics prediction
	if parent is CharacterBody3D:
		parent.velocity = vel
