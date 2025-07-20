# Lobby.gd
extends Control

# --- Constants ---
const MAIN_MENU_SCENE_PATH: String = "res://scenes/MainMenu.tscn"

# --- Node References ---
@onready var back_button: Button = $BackButton
@onready var choose_human_button: Button = $CharacterSelection/HumanCard/VBox/ChooseHumanButton
@onready var choose_dog_button: Button = $CharacterSelection/DogCard/VBox/ChooseDogButton
@onready var human_card: PanelContainer = $CharacterSelection/HumanCard
@onready var dog_card: PanelContainer = $CharacterSelection/DogCard


# --- Engine Callbacks ---

func _ready() -> void:
	# Connect to the NetworkManager's signal
	NetworkManager.player_list_changed.connect(_on_player_list_changed)
	
	# Connect button signals
	back_button.pressed.connect(_on_back_button_pressed)
	choose_human_button.pressed.connect(func(): _on_claim_role("human"))
	choose_dog_button.pressed.connect(func(): _on_claim_role("dog"))
	
	# When a client joins, it needs to tell the server it has arrived.
	if not multiplayer.is_server():
		print("Lobby: Client ready, waiting for connection...")
		# Wait a frame to ensure connection is established
		await get_tree().process_frame
		
		# Check if we're connected
		if multiplayer.has_multiplayer_peer() and multiplayer.get_multiplayer_peer().get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			print("Lobby: Client connected, registering with server...")
			# The server always has ID 1
			NetworkManager.register_player.rpc_id(1, "ClientPlayer")
		else:
			print("Lobby: ERROR - Not connected to server!")
		
	# Initial UI update
	_on_player_list_changed()


# --- Signal Handlers ---

func _on_back_button_pressed() -> void:
	"""Handle back button press to return to main menu."""
	print("Lobby: Back button pressed, returning to main menu...")
	
	# Disconnect from the current multiplayer session
	if NetworkManager:
		NetworkManager.disconnect_from_game()
	
	# Ensure mouse is visible for main menu navigation
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	# Return to main menu
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)


func _on_player_list_changed() -> void:
	"""Updates the entire lobby UI based on the NetworkManager's state."""
	_update_player_list_label()
	_update_role_button_state()


func _on_claim_role(role: String) -> void:
	"""Sends an RPC to the server to claim the selected role and automatically join."""
	# Check if we have a valid multiplayer connection
	if not multiplayer.has_multiplayer_peer() or multiplayer.get_multiplayer_peer().get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		print("Lobby: No valid multiplayer connection for role claim")
		return
	
	# Check if we're registered with the server
	var my_id = multiplayer.get_unique_id()
	if not multiplayer.is_server() and not NetworkManager.players.has(my_id):
		print("Lobby: Not yet registered with server, waiting...")
		# Try again in a moment
		await get_tree().create_timer(0.5).timeout
		if not NetworkManager.players.has(my_id):
			print("Lobby: Still not registered, please try again")
			return
		
	print("Lobby: Claiming role '%s' and joining game..." % role)
	# The server (ID 1) is the authority.
	NetworkManager.claim_role.rpc_id(1, role)
	
	# The NetworkManager will handle loading the game scene automatically


# --- UI Update Logic ---

func _update_player_list_label() -> void:
	"""Updates the player list - keeping for compatibility but no UI element exists."""
	pass


func _update_role_button_state() -> void:
	"""Disables the role selection buttons if the role has already been taken."""
	var human_taken: bool = false
	var dog_taken: bool = false
	var my_role: String = ""
	
	# Check what roles are taken and what role I have
	for id in NetworkManager.players:
		var role: String = NetworkManager.players[id].role
		if role == "human":
			human_taken = true
		elif role == "dog":
			dog_taken = true
		
		# Check if this is my role (only in multiplayer mode)
		if multiplayer.has_multiplayer_peer() and id == multiplayer.get_unique_id():
			my_role = role
	
	# Update button states
	choose_human_button.disabled = human_taken
	choose_dog_button.disabled = dog_taken
	
	# Visual feedback for selected role
	if human_card and dog_card:
		human_card.modulate = Color.WHITE if my_role != "dog" else Color(0.5, 0.5, 0.5, 1.0)
		dog_card.modulate = Color.WHITE if my_role != "human" else Color(0.5, 0.5, 0.5, 1.0)
		
		# Highlight selected card
		if my_role == "human":
			human_card.modulate = Color(1.2, 1.2, 1.2, 1.0)
		elif my_role == "dog":
			dog_card.modulate = Color(1.2, 1.2, 1.2, 1.0)

