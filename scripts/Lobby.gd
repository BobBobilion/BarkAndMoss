# Lobby.gd
extends Control

# --- Node References ---
@onready var player_list_label: Label = $PlayerListLabel
@onready var choose_human_button: Button = $ChooseHumanButton
@onready var choose_dog_button: Button = $ChooseDogButton
@onready var start_game_button: Button = $StartGameButton


# --- Engine Callbacks ---

func _ready() -> void:
	# Connect to the NetworkManager's signal
	NetworkManager.player_list_changed.connect(_on_player_list_changed)
	
	# Connect button signals
	choose_human_button.pressed.connect(func(): _on_claim_role("human"))
	choose_dog_button.pressed.connect(func(): _on_claim_role("dog"))
	start_game_button.pressed.connect(_on_start_game_pressed)
	
	# The start button is only for the host
	start_game_button.visible = multiplayer.is_server()
	
	# When a client joins, it needs to tell the server it has arrived.
	if not multiplayer.is_server():
		# The server always has ID 1
		NetworkManager.register_player.rpc_id(1, "ClientPlayer")
		
	# Initial UI update
	_on_player_list_changed()


# --- Signal Handlers ---

func _on_player_list_changed() -> void:
	"""Updates the entire lobby UI based on the NetworkManager's state."""
	_update_player_list_label()
	_update_role_button_state()


func _on_claim_role(role: String) -> void:
	"""Sends an RPC to the server to claim the selected role."""
	# Check if we have a valid multiplayer connection
	if not multiplayer.has_multiplayer_peer() or multiplayer.get_multiplayer_peer().get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		print("Lobby: No valid multiplayer connection for role claim")
		return
		
	# The server (ID 1) is the authority.
	NetworkManager.claim_role.rpc_id(1, role)


func _on_start_game_pressed() -> void:
	"""Tells the server to start the game for everyone."""
	NetworkManager.request_start_game.rpc_id(1)


# --- UI Update Logic ---

func _update_player_list_label() -> void:
	"""Updates the text label showing the list of connected players and their roles."""
	var player_text: String = "Players Connected:\n"
	for id in NetworkManager.players:
		var p_data: Dictionary = NetworkManager.players[id]
		player_text += "- %s (Role: %s)\n" % [p_data.name, p_data.role if p_data.role else "Choosing..."]
	player_list_label.text = player_text


func _update_role_button_state() -> void:
	"""Disables the role selection buttons if the role has already been taken."""
	var human_taken: bool = false
	var dog_taken: bool = false
	for id in NetworkManager.players:
		var role: String = NetworkManager.players[id].role
		if role == "human":
			human_taken = true
		elif role == "dog":
			dog_taken = true
	
	choose_human_button.disabled = human_taken
	choose_dog_button.disabled = dog_taken
