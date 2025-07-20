# DogSyncConfig.gd
# Synchronization configuration for Dog nodes
extends SceneReplicationConfig

func _init() -> void:
	# Sync transform properties
	add_property(NodePath(".:position"))
	add_property(NodePath(".:rotation"))
	
	# Sync velocity for smoother interpolation (CharacterBody3D property)
	add_property(NodePath(".:velocity"))
	
	# Set replication interval for smoother updates (30Hz)
	replication_interval = 1.0 / 30.0