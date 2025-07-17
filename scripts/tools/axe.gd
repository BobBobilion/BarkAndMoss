class_name Axe
extends Node3D

signal hit_something(body: Node3D)

@onready var hitbox: CollisionShape3D = $Hitbox/CollisionShape3D

func _ready() -> void:
	$Hitbox.body_entered.connect(func(body): hit_something.emit(body))
	hitbox.disabled = true # Initially disabled

func set_hitbox_enabled(is_enabled: bool) -> void:
	hitbox.disabled = not is_enabled 