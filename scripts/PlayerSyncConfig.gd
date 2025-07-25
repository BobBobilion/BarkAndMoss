# PlayerSyncConfig.gd
# Enhanced synchronization configuration for Player nodes
extends SceneReplicationConfig

func _init() -> void:
	# Sync transform properties with spawn values
	add_property(NodePath(".:position"))
	add_property(NodePath(".:rotation"))
	
	# Sync velocity for smoother interpolation (CharacterBody3D property)
	add_property(NodePath(".:velocity"))
	
	# Set replication interval for smoother updates (30Hz)
	replication_interval = 1.0 / 30.0