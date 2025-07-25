# WorldStateManager.gd
extends Node

## Manages the synchronization of the game world's state between the host and clients.
## This should be configured as an Autoload singleton in Project Settings.

# Emitted on the client after the host's world state has been received and stored.
signal world_state_applied

# The single source of truth for the world state.
var world_state: Dictionary = {
	"world_seed": 0,
	"chopped_trees": [], # Array of Vector3 positions for chopped trees
	"mined_rocks": []    # Array of Vector3 positions for mined rocks
}

func _ready() -> void:
	# The 'name' property is automatically set for Autoload singletons.
	pass

# --- Host-only methods ---

## Initializes the world state. Must be called by the host when a new world is generated.
func initialize_world_state(seed_val: int) -> void:
	if not multiplayer.is_server():
		return
	
	world_state.world_seed = seed_val
	# Clear any previous state from a prior session
	world_state.chopped_trees.clear()
	world_state.mined_rocks.clear()
	print("WorldStateManager: Host initialized world state with seed: ", seed_val)

## Records that a tree has been chopped down. Called by the host.
func record_tree_chopped(tree_position: Vector3) -> void:
	if not multiplayer.is_server():
		return
	if not world_state.chopped_trees.has(tree_position):
		world_state.chopped_trees.append(tree_position)
		# Sync to all connected clients in real-time
		_sync_tree_chopped.rpc(tree_position)

## Records that a rock has been mined. Called by the host.
func record_rock_mined(rock_position: Vector3) -> void:
	if not multiplayer.is_server():
		return
	if not world_state.mined_rocks.has(rock_position):
		world_state.mined_rocks.append(rock_position)
		# Sync to all connected clients in real-time
		_sync_rock_mined.rpc(rock_position)

# --- RPCs for State Sync ---

## [Client->Server] Client calls this to request the full world state from the host.
@rpc("any_peer", "call_remote", "reliable")
func request_world_state() -> void:
	# Only the server should process this request
	if not multiplayer.is_server():
		return
		
	var client_id = multiplayer.get_remote_sender_id()
	print("WorldStateManager: Received world state request from client ", client_id)
	
	# The host sends the current state back to only the requesting client.
	send_world_state.rpc_id(client_id, world_state)
	
## [Server->Client] Host calls this to send the state to a client.
@rpc("authority", "call_remote", "reliable")
func send_world_state(state: Dictionary) -> void:
	# This function only runs on the client that receives the RPC.
	if multiplayer.is_server():
		return # Host should not process its own state send.
		
	print("WorldStateManager: Client received world state from host. Seed: ", state.get("world_seed", "N/A"))
	self.world_state = state
	
	# Now that we have the state, we emit a signal that the NetworkManager is
	# waiting for, which will then trigger loading the main scene.
	world_state_applied.emit()


# --- Real-time sync RPCs ---

## [Server->Client] Host sends this when a tree is chopped
@rpc("authority", "call_remote", "reliable")
func _sync_tree_chopped(tree_position: Vector3) -> void:
	"""Sync a chopped tree to all clients in real-time."""
	print("WorldStateManager: Client received tree chop sync at position ", tree_position)
	
	# Add to local state if not already there
	if not world_state.chopped_trees.has(tree_position):
		world_state.chopped_trees.append(tree_position)
	
	# Find and remove the tree at this position
	_remove_tree_at_position(tree_position)


## [Server->Client] Host sends this when a rock is mined
@rpc("authority", "call_remote", "reliable")
func _sync_rock_mined(rock_position: Vector3) -> void:
	"""Sync a mined rock to all clients in real-time."""
	print("WorldStateManager: Client received rock mine sync at position ", rock_position)
	
	# Add to local state if not already there  
	if not world_state.mined_rocks.has(rock_position):
		world_state.mined_rocks.append(rock_position)
	
	# Find and remove the rock at this position
	_remove_rock_at_position(rock_position)


func _remove_tree_at_position(position: Vector3) -> void:
	"""Find and remove a tree at the given position."""
	# Search all tree nodes in the scene
	var trees = get_tree().get_nodes_in_group("interactable")
	for tree in trees:
		if tree.has_method("_chop_tree_networked") and tree.global_position.distance_to(position) < 1.0:
			print("WorldStateManager: Found and removing tree at ", position)
			tree._chop_tree_networked()
			return


func _remove_rock_at_position(position: Vector3) -> void:
	"""Find and remove a rock at the given position."""
	# Similar to trees but for rocks
	# This would be implemented when rocks have a similar system
	pass
