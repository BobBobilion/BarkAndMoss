class_name Player
extends CharacterBody3D

# --- Signals ---
signal hunger_changed(new_hunger: int)

# --- Player Stats ---
@export var hunger: int = 100  # Max hunger is 100
const MAX_HUNGER: int = 100
const HUNGER_DECAY_RATE: float = 2.0  # Decay 1 hunger every 2 seconds

# --- Script Preloads ---
const MovementController = preload("res://scripts/components/movement_controller.gd")
const CameraController = preload("res://scripts/components/camera_controller.gd")
const AnimationController = preload("res://scripts/components/animation_controller.gd")
const InteractionController = preload("res://scripts/components/interaction_controller.gd")
const EquipmentController = preload("res://scripts/components/equipment_controller.gd")

# --- Components ---
@onready var movement_controller: MovementController = $MovementController
@onready var camera_controller: CameraController = $CameraController
@onready var animation_controller: AnimationController = $AnimationController
@onready var interaction_controller: InteractionController = $InteractionController
@onready var equipment_controller: EquipmentController = $EquipmentController

# --- Timers ---
# Remove @onready since we create it manually in _ready()
var hunger_decay_timer: Timer

# --- State ---
var hud_instance: Control
var is_performing_action: bool = false
var pending_interaction_target: Node = null
var chop_timer: Timer = null
var cached_closest_interactable: Node = null  # Cache the closest interactable

# --- Engine Callbacks ---

func _ready() -> void:
	print("=== PLAYER READY STARTED ===")
	print("Player: Node name: ", name)
	print("Player: Scene file path: ", get_tree().current_scene.scene_file_path if get_tree().current_scene else "None")
	
	# Check multiplayer status safely
	var has_multiplayer = multiplayer.has_multiplayer_peer()
	var is_authority = has_multiplayer and is_multiplayer_authority()
	print("Player: Has multiplayer peer: ", has_multiplayer)
	print("Player: Multiplayer authority: ", is_authority if has_multiplayer else "N/A (single player)")

	# Set up hunger decay timer
	hunger_decay_timer = Timer.new()
	add_child(hunger_decay_timer)
	hunger_decay_timer.wait_time = HUNGER_DECAY_RATE
	hunger_decay_timer.timeout.connect(_on_hunger_decay)
	hunger_decay_timer.autostart = true
	print("Player: Hunger decay timer setup - wait_time: ", HUNGER_DECAY_RATE, " autostart: ", hunger_decay_timer.autostart)
	print("Player: Timer started: ", hunger_decay_timer.is_stopped() == false)
	
	# Debug: Force start the timer explicitly to ensure it's running
	hunger_decay_timer.start()
	print("Player: Explicitly started hunger timer. Timer stopped?: ", hunger_decay_timer.is_stopped())
	
	# Wire up controller dependencies - using new camera hierarchy
	var camera_node: Camera3D = $CameraRootOffset/HorizontalPivot/VerticalPivot/SpringArm3D/Camera3D
	var horizontal_pivot: Node3D = $CameraRootOffset/HorizontalPivot
	var vertical_pivot: Node3D = $CameraRootOffset/HorizontalPivot/VerticalPivot
	
	camera_controller.setup(camera_node, self, horizontal_pivot, vertical_pivot)
	animation_controller.setup($AdventurerModel)
	interaction_controller.setup($InteractionArea, self)
	equipment_controller.setup(self, $AdventurerModel, camera_node)

	# Debug interaction setup
	print("Player: InteractionArea collision layer = ", $InteractionArea.collision_layer)
	print("Player: InteractionArea collision mask = ", $InteractionArea.collision_mask)
	print("Player: InteractionArea monitoring = ", $InteractionArea.monitoring)
	print("Player: InteractionArea monitorable = ", $InteractionArea.monitorable)

	# Determine if this is the local player (safe for both multiplayer and single player)
	var is_local_player: bool = not has_multiplayer or is_authority
	print("Player: Is local player: ", is_local_player)
	
	if is_local_player:
		print("Player: Setting up as local player...")
		camera_node.make_current()
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		print("Player: About to call add_hud()")
		call_deferred("add_hud")
		# Add global UI for FPS counter and game code display (shared with dog player)
		call_deferred("add_global_ui")
		if PauseManager:
			PauseManager.register_player(self)
		print("Player: Local player setup complete")
	else:
		print("Player: Setting up as remote player...")
		camera_node.current = false

	add_to_group("human_player")
	print("Player: Added to human_player group")
	
	# Connect signals between controllers
	equipment_controller.action_started.connect(func(): is_performing_action = true)
	equipment_controller.action_finished.connect(func(): is_performing_action = false)
	equipment_controller.aiming_status_changed.connect(camera_controller.set_aiming)
	print("=== PLAYER READY FINISHED ===")

func _physics_process(delta: float) -> void:
	# Only process for local player or in single-player mode
	if multiplayer.has_multiplayer_peer():
		if not is_multiplayer_authority():
			return

	# Movement
	velocity = movement_controller.handle_movement(delta, self, transform)
	move_and_slide()
	
	# Update chunk system with our position
	_update_chunk_position()
	
	# Animation
	if not is_performing_action:
		animation_controller.update_movement_animation(velocity, is_on_floor(), movement_controller.current_speed)

	# Update cached closest interactable every frame
	cached_closest_interactable = interaction_controller.get_closest_interactable()

	# Interaction - check input directly here
	if Input.is_action_just_pressed("interact"):
		handle_interaction()

	# Equipment
	var action_to_perform = equipment_controller.handle_equipment_input(delta, cached_closest_interactable)
	if action_to_perform:
		handle_action(action_to_perform)

func _process(delta: float) -> void:
	# Only process for local player or in single-player mode
	if multiplayer.has_multiplayer_peer():
		if not is_multiplayer_authority():
			return
	camera_controller.process_camera(delta)
	
	# Debug: Check hunger timer status periodically
	if int(Time.get_unix_time_from_system()) % 5 == 0 and Engine.get_process_frames() % 300 == 0:
		print("Player: Debug - Hunger timer stopped?: ", hunger_decay_timer.is_stopped(), " Time left: ", hunger_decay_timer.time_left)

func _unhandled_input(event: InputEvent) -> void:
	# Only process input for local player or in single-player mode
	if multiplayer.has_multiplayer_peer():
		if not is_multiplayer_authority():
			return
	camera_controller._unhandled_input(event)
	
	# Debug: Test hunger decay manually with H key
	if event is InputEventKey and event.pressed and event.keycode == KEY_H:
		print("Player: Manual hunger decay test triggered!")
		_on_hunger_decay()

func handle_interaction() -> void:
	# print("Player: Using InteractionController instance: ", interaction_controller.get_instance_id())  # Too spammy
	# Use the cached closest interactable instead of calling handle_interaction_input
	var interactable = cached_closest_interactable
	# print("Player: handle_interaction called, interactable = ", interactable.name if interactable else "None")  # Too spammy
	if interactable:
		var prompt: String = interaction_controller.get_interaction_prompt(interactable)
		print("Player: Interacting with ", interactable.name, " - Prompt: ", prompt)  # Keep this - it's an action
		# Only block the deprecated tree chopping interaction, not corpse processing
		var is_tree_chop = "Chop Tree" in prompt
		
		if not is_tree_chop:
			# print("Player: Calling interact_with_object on ", interactable.name)  # Redundant with above
			interaction_controller.interact_with_object(interactable, self)

func handle_action(action_name: String) -> void:
	print("Player: handle_action called with action: '", action_name, "'")
	
	if is_performing_action:
		print("Player: Already performing action, ignoring '", action_name, "'")
		return
	
	if action_name == "chop":
		print("Player: Processing chop action")
		# Don't enable hitbox immediately - wait for downstroke
		pass
		
	is_performing_action = true
	pending_interaction_target = interaction_controller.get_closest_interactable()
	print("Player: Playing animation for action: '", action_name, "'")
	animation_controller.play_action(action_name)
	
	var anim_player = animation_controller.get_animation_player()
	if anim_player:
		# Use a timer to wait for the animation to finish
		var anim = anim_player.get_animation(animation_controller.current_animation)
		if anim:
			var duration = anim.length
			
			# For chop action, set up hitbox timing
			if action_name == "chop":
				# Enable hitbox at 1/3 through animation (downstroke)
				var downstroke_start = duration * 0.33
				var downstroke_end = duration * 0.66  # Disable at 66% through animation
				
				# Timer to enable hitbox during downstroke
				var enable_timer = Timer.new()
				add_child(enable_timer)
				enable_timer.wait_time = downstroke_start
				enable_timer.one_shot = true
				enable_timer.timeout.connect(func(): 
					equipment_controller.toggle_axe_hitbox(true)
					enable_timer.queue_free()
				)
				enable_timer.start()
				
				# Timer to disable hitbox after downstroke
				var disable_timer = Timer.new()
				add_child(disable_timer)
				disable_timer.wait_time = downstroke_end
				disable_timer.one_shot = true
				disable_timer.timeout.connect(func(): 
					equipment_controller.toggle_axe_hitbox(false)
					disable_timer.queue_free()
				)
				disable_timer.start()
			
			if chop_timer and is_instance_valid(chop_timer):
				chop_timer.queue_free()

			chop_timer = Timer.new()
			add_child(chop_timer)
			chop_timer.wait_time = duration
			chop_timer.one_shot = true
			chop_timer.timeout.connect(_on_action_animation_finished)
			chop_timer.start()

func _on_action_animation_finished() -> void:
	is_performing_action = false
	
	# Don't disable hitbox here anymore - it's already handled by the downstroke timer
	# equipment_controller.toggle_axe_hitbox(false)
	
	# Remove the deprecated interaction call - the axe hitbox collision already handles damage
	# The pending_interaction_target code was trying to call _on_interacted() which is deprecated
	pending_interaction_target = null

	# Return to idle/movement animation
	animation_controller.update_movement_animation(velocity, is_on_floor(), movement_controller.current_speed)
	
	if chop_timer and is_instance_valid(chop_timer):
		chop_timer.queue_free()
		chop_timer = null

func add_hud() -> void:
	print("Player: add_hud() called")
	
	# Get the root viewport instead of the local tree
	var viewport = get_viewport()
	if not viewport:
		print("Player: ERROR - No viewport available")
		return
		
	# First, check if UILayer already exists
	var ui_layer = viewport.get_node_or_null("UILayer")
	
	if ui_layer:
		print("Player: UILayer already exists, cleaning up old HUD")
		# Remove any existing HUD from this layer
		for child in ui_layer.get_children():
			if child.name == "HUD":
				print("Player: Removing existing HUD")
				child.queue_free()
	else:
		print("Player: Creating new UILayer")
		ui_layer = CanvasLayer.new()
		ui_layer.name = "UILayer"
		viewport.add_child(ui_layer)
		print("Player: UILayer created and added to viewport")
	
	# Now create and add the HUD scene to the UILayer
	print("Player: Loading HUD scene...")
	var hud_scene = load("res://scenes/HUD.tscn")
	if hud_scene:
		hud_instance = hud_scene.instantiate()  # Fixed: assign to class member, not create local variable
		ui_layer.add_child(hud_instance)
		
		# Pass the player reference to the HUD
		if hud_instance.has_method("set_player"):
			hud_instance.set_player(self)
			print("Player: HUD player reference set")
			
		# Pass the hunger value to initialize the HUD
		if hud_instance.has_method("update_hunger"):
			hud_instance.update_hunger(hunger)
			print("Player: HUD hunger initialized to: ", hunger)
		
		# DEBUG: Add world seed label
		var debug_label = Label.new()
		debug_label.name = "WorldSeedDebug"
		debug_label.position = Vector2(10, 40)  # Moved down to avoid overlap with game code display
		debug_label.add_theme_font_size_override("font_size", 14)  # Made slightly smaller
		debug_label.add_theme_color_override("font_color", Color.YELLOW)
		
		# Get the world seed from the chunk manager
		var world_seed_text = "World Seed: UNKNOWN"
		var game_manager = get_tree().get_first_node_in_group("game_manager")
		if game_manager and game_manager.chunk_manager and game_manager.chunk_manager.chunk_generator:
			var seed = game_manager.chunk_manager.chunk_generator.world_seed
			world_seed_text = "World Seed: %d" % seed
			
			# Also get player ID info
			var player_id = get_multiplayer_authority() if multiplayer.has_multiplayer_peer() else 0
			var host_text = " (HOST)" if NetworkManager.is_host else " (CLIENT)"
			world_seed_text += "\nPlayer ID: %d%s" % [player_id, host_text]
		
		debug_label.text = world_seed_text
		ui_layer.add_child(debug_label)
		print("Player: Added world seed debug label: ", world_seed_text)
		
		print("Player: HUD loaded and initialized successfully")
		
		# Give equipment controller access to HUD for hotbar item checking
		equipment_controller.set_hud_reference(hud_instance)
		
		# Connect hotbar and inventory signals after HUD is in scene tree
		call_deferred("_connect_hotbar_signals")
		
		# Add test items for debugging (only in debug builds)
		call_deferred("_add_test_items")
	else:
		print("Player: ERROR - Failed to load HUD scene")

func _connect_hotbar_signals() -> void:
	"""Connect hotbar and inventory signals after the HUD is added to the scene tree."""
	print("Player: Connecting hotbar signals...")
	if is_instance_valid(hud_instance) and hud_instance.has_node("Hotbar"):
		var hotbar = hud_instance.get_node("Hotbar")
		if hotbar and not hotbar.is_connected("selection_changed", equipment_controller.on_hotbar_selection_changed):
			hotbar.connect("selection_changed", equipment_controller.on_hotbar_selection_changed)
			print("Player: Hotbar signals connected successfully")
			
			# Set player reference in hotbar for arrow count display
			if hotbar.has_method("set_player"):
				hotbar.set_player(self)
				print("Player: Set player reference in hotbar")
		else:
			print("Player: Error - Could not connect hotbar signals")
	else:
		print("Player: Error - HUD instance invalid or hotbar not found")
	
	# Connect inventory signals for food consumption
	print("Player: Connecting inventory signals...")
	if is_instance_valid(hud_instance) and hud_instance.has_node("Inventory"):
		var inventory = hud_instance.get_node("Inventory")
		if inventory and not inventory.is_connected("item_used", consume_food):
			inventory.connect("item_used", consume_food)
			print("Player: Inventory signals connected successfully")
		else:
			print("Player: Error - Could not connect inventory signals")
	else:
		print("Player: Error - Inventory not found in HUD")
	
	# Test hunger signal connection
	call_deferred("test_hunger_signal")

func _add_test_items() -> void:
	if not OS.is_debug_build(): return
	if is_instance_valid(hud_instance) and hud_instance.has_node("Inventory"):
		var inventory: Node = hud_instance.get_node("Inventory")
		if inventory.has_method("add_item"):
			# Starting crafting materials for bow
			inventory.add_item("Wood", 2)
			inventory.add_item("Hide", 3)
			inventory.add_item("Sinew", 3)
			
			# Add some feathers and arrows for testing bow
			inventory.add_item("Feather", 1)
			
			# Test items for cooking and hunger testing
			inventory.add_item("Raw Meat", 2)  # For testing cooking system
			inventory.add_item("Cooked Meat", 3)  # For testing hunger system

func add_item_to_inventory(item_name: String) -> bool:
	if is_instance_valid(hud_instance) and hud_instance.has_node("Inventory"):
		var inventory = hud_instance.get_node("Inventory")
		if inventory.has_method("add_item"):
			return inventory.add_item(item_name)
	return false

func get_inventory():
	if is_instance_valid(hud_instance) and hud_instance.has_node("Inventory"):
		return hud_instance.get_node("Inventory")
	return null

func get_interaction_controller() -> InteractionController:
	return interaction_controller

func get_equipped_item() -> String:
	"""Get the currently equipped item from the equipment controller."""
	if equipment_controller:
		return equipment_controller.equipped_item
	return ""

func _exit_tree() -> void:
	# Check if multiplayer peer exists before checking authority to avoid errors during cleanup
	if multiplayer and multiplayer.multiplayer_peer and is_multiplayer_authority() and PauseManager:
		PauseManager.unregister_player(self)

func _update_chunk_position() -> void:
	"""Update our position in the chunk system for loading/unloading chunks."""
	# Find GameManager and update our position
	var game_managers := get_tree().get_nodes_in_group("game_manager")
	if game_managers.size() > 0:
		var game_manager = game_managers[0]
		if game_manager.has_method("update_player_chunk_position"):
			game_manager.update_player_chunk_position(self)

func _on_hunger_decay() -> void:
	"""Handle hunger decay every 2 seconds."""
	if hunger > 0:
		hunger -= 1
		hunger = max(0, hunger)  # Ensure hunger doesn't go below 0
		hunger_changed.emit(hunger)
		if hunger == 0:
			# TODO: Implement starvation effects when hunger reaches 0
			pass
	else:
		pass


func consume_food(food_name: String) -> void:
	"""Handle food consumption and hunger restoration."""
	if food_name == "Cooked Meat":
		var old_hunger: int = hunger
		hunger = min(MAX_HUNGER, hunger + 10)  # Restore 10 hunger, capped at 100
		if hunger != old_hunger:
			hunger_changed.emit(hunger)


func get_hunger() -> int:
	"""Get current hunger level."""
	return hunger


func set_hunger(new_hunger: int) -> void:
	"""Set hunger level (for multiplayer sync)."""
	var old_hunger: int = hunger
	hunger = clamp(new_hunger, 0, MAX_HUNGER)
	if hunger != old_hunger:
		hunger_changed.emit(hunger)

func test_hunger_signal() -> void:
	"""Test if hunger signal connection is working."""
	hunger_changed.emit(hunger)


func add_global_ui() -> void:
	"""Add global UI elements that should be visible to both human and dog players."""
	print("Player: add_global_ui() called")
	
	# Get the root viewport
	var viewport = get_viewport()
	if not viewport:
		print("Player: ERROR - No viewport available")
		return
		
	# Check if GlobalUILayer already exists (might be created by dog player)
	var global_ui_layer = viewport.get_node_or_null("GlobalUILayer")
	
	if global_ui_layer:
		print("Player: GlobalUILayer already exists, skipping creation")
		return
	else:
		print("Player: Creating new GlobalUILayer")
		global_ui_layer = CanvasLayer.new()
		global_ui_layer.name = "GlobalUILayer"
		global_ui_layer.layer = 5  # Lower than HUD (10) but above background
		viewport.add_child(global_ui_layer)
		print("Player: GlobalUILayer created and added to viewport")
	
	# Create FPS counter
	var fps_counter = Label.new()
	fps_counter.name = "FPSCounter"
	fps_counter.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	fps_counter.offset_left = -120
	fps_counter.offset_top = 10
	fps_counter.offset_right = -10
	fps_counter.offset_bottom = 35
	fps_counter.add_theme_font_size_override("font_size", 16)
	fps_counter.add_theme_color_override("font_color", Color(0.918, 0.878, 0.835, 1))
	fps_counter.add_theme_color_override("font_shadow_color", Color(0.137, 0.2, 0.165, 1))
	fps_counter.add_theme_constant_override("shadow_offset_x", 1)
	fps_counter.add_theme_constant_override("shadow_offset_y", 1)
	fps_counter.text = "FPS: 60"
	fps_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fps_counter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fps_counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	global_ui_layer.add_child(fps_counter)
	
	# Create game code display
	var game_code_display = Label.new()
	game_code_display.name = "GameCodeDisplay"
	game_code_display.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	game_code_display.offset_left = 10
	game_code_display.offset_top = 10
	game_code_display.offset_right = 150
	game_code_display.offset_bottom = 35
	game_code_display.add_theme_font_size_override("font_size", 16)
	game_code_display.add_theme_color_override("font_color", Color(0.918, 0.878, 0.835, 1))
	game_code_display.add_theme_color_override("font_shadow_color", Color(0.137, 0.2, 0.165, 1))
	game_code_display.add_theme_constant_override("shadow_offset_x", 1)
	game_code_display.add_theme_constant_override("shadow_offset_y", 1)
	game_code_display.text = "Code: ABC123"
	game_code_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	game_code_display.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	game_code_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	global_ui_layer.add_child(game_code_display)
	
	# Create a script to handle updates
	var global_ui_script = GDScript.new()
	global_ui_script.source_code = """
extends CanvasLayer

var fps_update_timer: float = 0.0
var fps_update_interval: float = 0.5

func _ready():
	_update_game_code_display()
	var timer = Timer.new()
	timer.wait_time = 1.0
	timer.timeout.connect(_update_game_code_display)
	timer.autostart = true
	add_child(timer)

func _process(delta):
	_update_fps_counter(delta)

func _update_fps_counter(delta: float):
	fps_update_timer += delta
	if fps_update_timer >= fps_update_interval:
		fps_update_timer = 0.0
		var current_fps = Engine.get_frames_per_second()
		var fps_counter = get_node_or_null('FPSCounter')
		if fps_counter:
			fps_counter.text = 'FPS: %d' % current_fps

func _update_game_code_display():
	var game_code_display = get_node_or_null('GameCodeDisplay')
	if not game_code_display:
		return
		
	if multiplayer.has_multiplayer_peer():
		var lobby_code = NetworkManager.get_lobby_code()
		if lobby_code != '':
			game_code_display.text = 'Code: %s' % lobby_code
			game_code_display.visible = true
		else:
			game_code_display.visible = false
	else:
		game_code_display.visible = false
"""
	global_ui_layer.set_script(global_ui_script)
	
	print("Player: Global UI created successfully")
