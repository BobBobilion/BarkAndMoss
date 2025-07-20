# PlayerSpawner.gd
class_name PlayerSpawner
extends Node

## Spawns and despawns player characters in the main game world.
## This node should be added to the Main scene tree.

@export var human_scene: PackedScene = preload("res://scenes/Player.tscn")
@export var dog_scene: PackedScene = preload("res://scenes/Dog.tscn")

func _ready() -> void:
	# Ensure NetworkManager is ready before connecting signals
	if not is_instance_valid(NetworkManager):
		await get_tree().create_timer(0.1).timeout
	
	# Connect to NetworkManager signals to know when to spawn/despawn players
	NetworkManager.player_list_changed.connect(_on_player_list_changed)
	
	# Initial spawn for any players already present when this scene loads
	_on_player_list_changed()


func _on_player_list_changed() -> void:
	"""
	Called when the list of players in NetworkManager changes.
	It spawns players who are in the list but not in the world,
	and removes players who are in the world but no longer in the list.
	"""
	var players_in_game = NetworkManager.players
	var players_in_scene: Dictionary = {}

	# Get a list of all current player nodes in the scene
	for child in get_children():
		if child.is_in_group("players"):
			# Assuming the player node's name is its ID as a string
			players_in_scene[int(child.name)] = child
	
	# Spawn missing players
	for player_id in players_in_game:
		if not players_in_scene.has(player_id):
			_spawn_player(player_id, players_in_game[player_id])
			
	# Despawn players who have left
	for player_id in players_in_scene:
		if not players_in_game.has(player_id):
			players_in_scene[player_id].queue_free()


func _spawn_player(player_id: int, player_data: Dictionary) -> void:
	"""Instantiates and spawns a player character."""
	var role = player_data.get("role", "unassigned")
	var player_scene: PackedScene
	
	match role:
		"human":
			player_scene = human_scene
		"dog":
			player_scene = dog_scene
		_:
			print("PlayerSpawner: Cannot spawn player %d with unassigned role." % player_id)
			return

	if not player_scene:
		push_error("PlayerSpawner: Player scene for role '%s' is not set!" % role)
		return
		
	var player_instance = player_scene.instantiate()
	player_instance.name = str(player_id)
	
	# The MultiplayerSpawner node will handle synchronizing this instance
	# across all clients. The host adds it to the scene, and it replicates.
	add_child(player_instance)
	
	print("PlayerSpawner: Spawned %s for player %d." % [role, player_id]) 