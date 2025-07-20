# PlayerSyncConfig.gd
# Enhanced synchronization configuration for Player nodes
extends SceneReplicationConfig

func _init() -> void:
	# Sync transform properties with spawn values
	add_property(NodePath(".:position"), true)  # Spawn = true
	add_property(NodePath(".:rotation"), true)  # Spawn = true
	add_property(NodePath(".:scale"), true)     # Spawn = true

	# The replication mode (e.g., Reliable, Unreliable) is not set here in the script.
	# It must be configured in the Inspector on the MultiplayerSynchronizer node that uses this resource.

	# Sync visibility
	add_property(NodePath(".:visible"), true)