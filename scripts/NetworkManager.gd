# NetworkManager.gd
# This script manages the entire network session, from connection to player data.
extends Node

# --- Signals ---
signal player_list_changed
signal connection_failed(reason: String)

# --- Properties ---
var players: Dictionary = {}
var connection_timeout_timer: Timer
var lobby_code: String = ""
var is_host: bool = false
var lobby_codes: Dictionary = {}  # Store active lobby codes and their hosts

# Reconnection handling
var reconnection_timer: Timer
var last_known_players: Dictionary = {}
var connection_retry_count: int = 0
var max_retry_attempts: int = 3

# NAT traversal
var nat_pmp_enabled: bool = false
var upnp_enabled: bool = false

# Discovery system
var discovery_timeout_counter: int = 0
var discovery_check_counter: int = 0  # For periodic status checks

@export var human_scene: PackedScene = preload("res://scenes/Player.tscn")
@export var dog_scene: PackedScene = preload("res://scenes/Dog.tscn")


# --- Engine Callbacks ---

func _ready() -> void:
	"""Connects multiplayer signals."""
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	# Setup reconnection timer
	reconnection_timer = Timer.new()
	reconnection_timer.wait_time = 5.0  # Try reconnect every 5 seconds
	reconnection_timer.timeout.connect(_attempt_reconnection)
	add_child(reconnection_timer)
	
	# Don't start discovery server automatically - only when hosting
	print("NetworkManager: Ready, instance ID: ", get_instance_id())


# --- Public Methods ---

func host_game() -> void:
	"""Creates a server and sets up the host player."""
	print("NetworkManager: Starting host_game...")
	
	# Try UPnP port forwarding first
	_setup_nat_traversal()
	
	var peer := ENetMultiplayerPeer.new()
	var error: Error = peer.create_server(GameConstants.NETWORK.DEFAULT_PORT, GameConstants.NETWORK.MAX_PLAYERS)
	if error != OK:
		var reason = "Failed to create host. Port %d might be in use." % GameConstants.NETWORK.DEFAULT_PORT
		push_error("NetworkManager: " + reason)
		connection_failed.emit(reason)
		return

	multiplayer.multiplayer_peer = peer
	is_host = true
	
	# Generate unique 6-character lobby code
	lobby_code = _generate_lobby_code()
	print("NetworkManager: Lobby created with code: ", lobby_code)
	print("NetworkManager: Host is ready on port: ", GameConstants.NETWORK.DEFAULT_PORT)
	print("NetworkManager: Starting discovery server...")
	
	# Start discovery server now that we're hosting
	_start_discovery_server()
	
	# The host is player 1.
	_add_player(GameConstants.NETWORK.SERVER_ID, "HostPlayer")
	
	# Note: Role assignment will happen through character selection or lobby


func join_game(ip_address: String) -> void:
	"""Joins an existing server at the given IP address."""
	print("NetworkManager: Attempting to join server at ", ip_address)
	
	var peer := ENetMultiplayerPeer.new()
	var error = peer.create_client(ip_address, GameConstants.NETWORK.DEFAULT_PORT)
	
	if error != OK:
		print("NetworkManager: Failed to create client connection to ", ip_address, " Error: ", error)
		connection_failed.emit("Failed to connect to server")
		return
	
	multiplayer.multiplayer_peer = peer
	is_host = false
	
	print("NetworkManager: Client peer created, status: ", peer.get_connection_status())
	
	# Wait a bit and check status again
	await get_tree().create_timer(0.1).timeout
	print("NetworkManager: After 0.1s, peer status: ", peer.get_connection_status())

func join_game_by_code(code: String) -> void:
	"""Joins a game using a 6-character lobby code."""
	print("NetworkManager: Attempting to join with code: ", code)
	
	# Set discovery timeout
	discovery_timeout_counter = 0
	
	# Try localhost first for development/testing
	if code == "LOCALHOST" or code == "127001" or code == "LOCAL" or code == "TEST":
		print("NetworkManager: Using localhost override")
		join_game("127.0.0.1")
		return
	
	# Add network diagnostic before starting discovery
	print("NetworkManager: Running network diagnostics...")
	_run_network_diagnostics()
	
	# Use UDP discovery for network play
	print("NetworkManager: Starting network discovery for code: ", code)
	_discover_host_by_code(code)

func _try_localhost_connection(code: String) -> bool:
	"""Try connecting to localhost first (for same-machine testing)."""
	print("NetworkManager: Trying localhost connection for code: ", code)
	
	# For same-machine testing, just try to connect directly
	# This avoids UDP discovery issues on the same machine
	print("NetworkManager: Attempting direct localhost connection...")
	join_game("127.0.0.1")
	
	# Wait a moment to see if connection succeeds
	await get_tree().create_timer(1.0).timeout
	
	if multiplayer.has_multiplayer_peer():
		var status = multiplayer.get_multiplayer_peer().get_connection_status()
		print("NetworkManager: Localhost connection status: ", status)
		if status == MultiplayerPeer.CONNECTION_CONNECTED or status == MultiplayerPeer.CONNECTION_CONNECTING:
			return true
	
	print("NetworkManager: Localhost connection failed, will try network discovery")
	return false


func disconnect_from_game() -> void:
	"""Disconnect from the current multiplayer session and clean up."""
	print("NetworkManager: [Instance ", get_instance_id(), "] Disconnecting from game...")
	print("NetworkManager: STACK TRACE: ", get_stack())
	
	# Cleanup NAT traversal
	_cleanup_nat_traversal()
	
	# Stop discovery server if running
	_stop_discovery_server()
	
	# Clear all session data
	print("NetworkManager: Clearing players dictionary, was: ", players.keys())
	players.clear()
	lobby_code = ""
	is_host = false
	lobby_codes.clear()
	connection_retry_count = 0
	
	# Stop reconnection timer
	if reconnection_timer:
		reconnection_timer.stop()
	
	# Close the multiplayer peer connection
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	
	# Emit signal to notify about player list change (now empty)
	player_list_changed.emit()
	
	print("NetworkManager: [Instance ", get_instance_id(), "] Disconnected from game")

func get_lobby_code() -> String:
	"""Returns the current lobby code if hosting."""
	return lobby_code


# --- Signal Handlers ---

func _on_peer_connected(_id: int) -> void:
	"""Handles a new peer connecting to the server."""
	# This runs on the SERVER when a new client connects.
	# We wait for the client to register itself via RPC.
	pass


func _on_peer_disconnected(id: int) -> void:
	"""Handles a peer disconnecting from the server."""
	if players.has(id):
		# Store for potential reconnection
		last_known_players[id] = players[id].duplicate()
		
		players.erase(id)
		player_list_changed.emit()
		
		# Also remove their character from the game world if it exists
		var player_node: Node = get_tree().get_root().find_child("Player_" + str(id), true, false)
		if is_instance_valid(player_node):
			player_node.queue_free()
		
		print("NetworkManager: Player %d disconnected, stored for potential reconnection" % id)


# --- Private Methods ---

func _add_player(id: int, player_name: String) -> void:
	"""Adds a new player to the players dictionary."""
	print("NetworkManager: Adding player ID: ", id, " with name: ", player_name)
	players[id] = {"name": player_name, "role": "unassigned", "ready": false}
	print("NetworkManager: Players dictionary now contains: ", players.keys())
	player_list_changed.emit()


# --- RPCs (Remote Procedure Calls) ---

@rpc("any_peer", "call_local")
func register_player(player_name: String) -> void:
	"""
	[Client->Server] Called by a client on the server to announce its arrival.
	"""
	var id: int = multiplayer.get_remote_sender_id()
	print("NetworkManager: register_player called by ID: ", id, " with name: ", player_name)
	
	if id == 0:  # Local call from server
		print("NetworkManager: Ignoring local register_player call")
		return
	
	# Only server processes this
	if not multiplayer.is_server():
		print("NetworkManager: Non-server ignoring register_player")
		return
		
	print("NetworkManager: Server adding player ID: ", id, " with name: ", player_name)
	_add_player(id, player_name)
	
	# Send updated player list to all clients
	update_player_list.rpc(players)
	
	# If the game is already running (host is playing), tell the new client to show character selection
	var main_scene = get_tree().get_first_node_in_group("main")
	if main_scene:
		print("NetworkManager: Game already running, client %d needs to select character" % id)
		# Client will show lobby/character selection


@rpc("any_peer", "call_local")
func claim_role(role: String) -> void:
	"""
	[Client->Server] Called by a client to claim a role (human or dog).
	The host can also call this locally.
	"""
	var id: int = multiplayer.get_remote_sender_id()
	print("NetworkManager: claim_role called, sender ID: ", id, ", role: ", role)
	
	if id == 0: # ID is 0 if called locally by the host
		id = 1  # Server ID
		print("NetworkManager: Local call detected, using server ID: ", id)
	
	# Only server processes this
	if not multiplayer.is_server():
		print("NetworkManager: Non-server tried to process claim_role")
		return

	print("NetworkManager: Server processing claim_role for ID: ", id)
	print("NetworkManager: Current players: ", players)

	# Validate role
	if role != "human" and role != "dog":
		print("NetworkManager: Invalid role claimed: ", role)
		return

	if not players.has(id):
		print("NetworkManager: Unknown player tried to claim role: ", id)
		print("NetworkManager: Available player IDs: ", players.keys())
		return

	# Check if role is already taken
	for p_id in players:
		if players[p_id].role == role:
			print("NetworkManager: Role already taken: ", role)
			return # Role is taken, do nothing.

	players[id].role = role
	players[id].ready = true  # Auto-ready when role is selected
	print("NetworkManager: Player %d claimed role '%s'" % [id, role])
	
	# Tell everyone about the change
	update_player_list.rpc(players)
	
	# If game is already running and this is a client joining mid-game
	var main_scene = get_tree().get_first_node_in_group("main")
	if main_scene and id != 1 and multiplayer.is_server():  # Only server spawns players
		print("NetworkManager: Auto-spawning client %d with role %s into running game" % [id, role])
		
		# Now that role is assigned, spawn the player
		var game_manager = get_tree().get_first_node_in_group("game_manager")
		if game_manager:
			game_manager.spawn_player_with_role(id)
		
		# Tell the client to load the game scene
		load_main_scene.rpc_id(id)
		# The GameManager will handle spawning when the client's scene is ready


@rpc("any_peer", "call_local")
func update_player_list(new_player_list: Dictionary) -> void:
	"""
	[Server->All] The server sends the complete player list to all clients
	to keep everyone in sync.
	"""
	self.players = new_player_list
	player_list_changed.emit()
		

@rpc("any_peer", "call_local")
func set_player_ready(is_ready: bool) -> void:
	"""
	[Client->Server] Called when a player toggles their ready status.
	"""
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0:  # Local call
		sender_id = multiplayer.get_unique_id()
		
	if sender_id in players:
		players[sender_id]["ready"] = is_ready
		print("NetworkManager: Player ", sender_id, " ready status: ", is_ready)
		
		# Broadcast updated player list
		if multiplayer.is_server():
			update_player_list.rpc(players)


@rpc("authority", "call_local")
func request_start_game() -> void:
	"""
	[Client->Server] The host calls this to start the game for everyone.
	The server validates that all players are ready before proceeding.
	"""
	# Ensure everyone has a role and is ready before starting
	for p_id in players:
		if players[p_id].role == "unassigned":
			print("NetworkManager: Cannot start - player ", p_id, " has no role assigned")
			return
		if not players[p_id].ready:
			print("NetworkManager: Cannot start - player ", p_id, " is not ready")
			return
			
	print("NetworkManager: All players ready, starting game!")
	# If all checks pass, tell everyone to load the main scene
	load_main_scene.rpc()


@rpc("any_peer", "call_local")
func load_main_scene() -> void:
	"""[Server->All] Initiates loading the main game scene for all players."""
	# The host loads the scene directly.
	if multiplayer.is_server():
		# The host needs to initialize the world state before loading the scene,
		# so that the state is ready when clients request it.
		var world_seed = randi() # Or your own seed generation logic
		var world_state_manager = get_node("/root/WorldStateManager")
		world_state_manager.initialize_world_state(world_seed)
		get_tree().change_scene_to_file("res://scenes/Main.tscn")
	# Clients must first get the world state from the host.
	else:
		# We connect a one-shot signal. This function will be called once, then the connection is freed.
		var world_state_manager = get_node("/root/WorldStateManager")
		world_state_manager.world_state_applied.connect(
			_on_world_state_applied, 
			CONNECT_ONE_SHOT
		)
		print("NetworkManager: Client requesting world state from host...")
		# Request the state from the host (server ID is always 1)
		world_state_manager.request_world_state.rpc_id(1)


func _on_world_state_applied() -> void:
	"""Called on the client after the world state has been received."""
	print("NetworkManager: World state applied. Client is now loading Main.tscn.")
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


# --- Private Helper Methods ---

func _generate_lobby_code() -> String:
	"""Generates a random 6-character alphanumeric lobby code."""
	var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	var code = ""
	for i in range(6):
		code += chars[randi() % chars.length()]
	return code

func _discover_host_by_code(code: String) -> void:
	"""Discovers host IP by lobby code using UDP broadcast and local network scan."""
	print("NetworkManager: Starting discovery for code: ", code)
	
	# Try multiple discovery methods for better compatibility
	_try_broadcast_discovery(code)
	_try_local_network_scan(code)
	
	# Start listening for responses
	_start_discovery_listener(code)

func _try_broadcast_discovery(code: String) -> void:
	"""Try UDP broadcast discovery."""
	print("NetworkManager: Trying UDP broadcast discovery...")
	
	var udp := PacketPeerUDP.new()
	
	# Try multiple broadcast addresses for better compatibility
	var broadcast_addresses = ["255.255.255.255", "192.168.1.255", "192.168.0.255", "10.0.0.255"]
	
	for broadcast_addr in broadcast_addresses:
		var connect_result = udp.connect_to_host(broadcast_addr, GameConstants.NETWORK.DISCOVERY_PORT)
		
		if connect_result == OK:
			var request = {"type": "discover", "code": code}
			var json_string = JSON.stringify(request)
			var packet_data = json_string.to_utf8_buffer()
			
			print("NetworkManager: Broadcasting to ", broadcast_addr, ":", GameConstants.NETWORK.DISCOVERY_PORT)
			var send_result = udp.put_packet(packet_data)
			
			if send_result == OK:
				print("NetworkManager: Broadcast sent successfully to ", broadcast_addr)
			else:
				print("NetworkManager: Failed to broadcast to ", broadcast_addr, ", error: ", send_result)
		else:
			print("NetworkManager: Failed to connect for broadcast to ", broadcast_addr, ", error: ", connect_result)
	
	udp.close()

func _try_local_network_scan(code: String) -> void:
	"""Try scanning common local network ranges."""
	print("NetworkManager: Trying local network scan...")
	
	# Get local IP to determine network range
	var local_ips = IP.get_local_addresses()
	
	for local_ip in local_ips:
		if local_ip.begins_with("192.168.") or local_ip.begins_with("10.0.") or local_ip.begins_with("172."):
			print("NetworkManager: Found local IP: ", local_ip)
			_scan_network_range(code, local_ip)
			break

func _scan_network_range(code: String, local_ip: String) -> void:
	"""Scan a network range for hosts."""
	var ip_parts = local_ip.split(".")
	if ip_parts.size() != 4:
		return
	
	var base_ip = ip_parts[0] + "." + ip_parts[1] + "." + ip_parts[2] + "."
	
	# Scan common IP ranges (this is simplified, real implementation would be more thorough)
	var scan_ips = [
		base_ip + "1",   # Router
		base_ip + "100", # Common DHCP range
		base_ip + "101",
		base_ip + "102",
		base_ip + "103",
		base_ip + "104"
	]
	
	for target_ip in scan_ips:
		if target_ip != local_ip:  # Don't scan ourselves
			_send_discovery_to_ip(code, target_ip)

func _send_discovery_to_ip(code: String, target_ip: String) -> void:
	"""Send discovery request to a specific IP."""
	var udp := PacketPeerUDP.new()
	# Bind to any available port for sending
	var bind_result = udp.bind(0)  # Use 0 to get any available port
	if bind_result != OK:
		print("NetworkManager: Failed to bind UDP socket for sending, error: ", bind_result)
		return
		
	var connect_result = udp.connect_to_host(target_ip, GameConstants.NETWORK.DISCOVERY_PORT)
	
	if connect_result == OK:
		var request = {"type": "discover", "code": code}
		var json_string = JSON.stringify(request)
		var send_result = udp.put_packet(json_string.to_utf8_buffer())
		
		if send_result == OK:
			print("NetworkManager: Sent discovery to ", target_ip)
		else:
			print("NetworkManager: Failed to send to ", target_ip, ", error: ", send_result)
	else:
		print("NetworkManager: Failed to connect to ", target_ip, ", error: ", connect_result)
	
	udp.close()

func _start_discovery_listener(code: String) -> void:
	"""Starts listening for discovery responses."""
	print("NetworkManager: Starting discovery listener for code: ", code)
	
	var udp := PacketPeerUDP.new()
	var client_port = GameConstants.NETWORK.DISCOVERY_PORT + 1
	var bind_result = udp.bind(client_port)
	
	if bind_result != OK:
		print("NetworkManager: Failed to bind UDP listener to port ", client_port, ", error: ", bind_result)
		connection_failed.emit("Failed to setup discovery listener")
		return
	
	print("NetworkManager: UDP listener bound to port: ", client_port)
	
	# Reset timeout counter
	discovery_timeout_counter = 0
	
	# Create a timer to check for responses
	var timer = Timer.new()
	timer.wait_time = 0.1
	timer.timeout.connect(_check_discovery_response.bind(udp, code, timer))
	add_child(timer)
	timer.start()
	
	print("NetworkManager: Discovery listener timer started, will timeout after 10 seconds")

func _check_discovery_response(udp: PacketPeerUDP, code: String, timer: Timer) -> void:
	"""Checks for discovery responses from hosts."""
	if udp.get_available_packet_count() > 0:
		print("NetworkManager: Received UDP packet, processing...")
		var packet = udp.get_packet()
		var packet_string = packet.get_string_from_utf8()
		print("NetworkManager: Received packet content: ", packet_string)
		
		var response = JSON.parse_string(packet_string)
		
		if response and response.has("type") and response.type == "response":
			print("NetworkManager: Valid response packet received")
			if response.has("code") and response.code == code:
				# Found the host! Connect to their IP
				var host_ip = udp.get_packet_ip()
				print("NetworkManager: Found host at ", host_ip, " for code ", code)
				join_game(host_ip)
				
				# Cleanup
				timer.queue_free()
				udp.close()
				return
			else:
				print("NetworkManager: Response code mismatch - expected: ", code, ", got: ", response.get("code", "none"))
		else:
			print("NetworkManager: Invalid or non-response packet received")
	
	# Stop listening after 15 seconds (increased from 10)
	discovery_timeout_counter += 1
	if discovery_timeout_counter > 150:  # 15 seconds at 0.1 interval
		print("NetworkManager: Discovery timeout for code ", code, " after ", discovery_timeout_counter * 0.1, " seconds")
		connection_failed.emit("Could not find game with code: " + code)
		timer.queue_free()
		udp.close()

func _start_discovery_server() -> void:
	"""Starts listening for discovery requests from clients."""
	# Only start discovery server if we're not already running one
	if get_children().any(func(child): return child.name == "DiscoveryTimer"):
		print("NetworkManager: Discovery server already running")
		return
		
	print("NetworkManager: Starting discovery server on port: ", GameConstants.NETWORK.DISCOVERY_PORT)
	
	var udp := PacketPeerUDP.new()
	var bind_result = udp.bind(GameConstants.NETWORK.DISCOVERY_PORT)
	
	if bind_result != OK:
		print("NetworkManager: Failed to bind discovery server to port ", GameConstants.NETWORK.DISCOVERY_PORT, ", error: ", bind_result)
		# Try alternative ports
		for alt_port in [8002, 8003, 8004]:
			bind_result = udp.bind(alt_port)
			if bind_result == OK:
				print("NetworkManager: Successfully bound to alternative port: ", alt_port)
				break
			else:
				print("NetworkManager: Failed to bind to alternative port ", alt_port)
		
		if bind_result != OK:
			print("NetworkManager: ERROR - Could not bind to any port for discovery server!")
			return
	
	print("NetworkManager: Discovery server bound successfully to port: ", GameConstants.NETWORK.DISCOVERY_PORT)
	
	# Create a timer to check for requests
	var timer = Timer.new()
	timer.name = "DiscoveryTimer"
	timer.wait_time = 0.1
	timer.timeout.connect(_check_discovery_requests.bind(udp, timer))
	add_child(timer)
	timer.start()
	
	print("NetworkManager: Discovery server timer started")
	
	# Add periodic status check
	var status_timer = Timer.new()
	status_timer.name = "DiscoveryStatusTimer"
	status_timer.wait_time = 5.0  # Check every 5 seconds
	status_timer.timeout.connect(func():
		if is_host and lobby_code != "":
			var packet_count = udp.get_available_packet_count()
			print("NetworkManager: Discovery server status - is_host: ", is_host, ", lobby_code: '", lobby_code, "', UDP bound: ", udp.is_bound(), ", packets waiting: ", packet_count)
			if packet_count == 0:
				print("NetworkManager: No discovery requests received in last 5 seconds")
		else:
			print("NetworkManager: Discovery server stopping - is_host: ", is_host, ", lobby_code: '", lobby_code, "'")
			status_timer.queue_free()
	)
	add_child(status_timer)
	status_timer.start()

func _stop_discovery_server() -> void:
	"""Stop the discovery server."""
	var discovery_timer = get_node_or_null("DiscoveryTimer")
	if discovery_timer:
		print("NetworkManager: [Instance ", get_instance_id(), "] Stopping discovery server")
		discovery_timer.queue_free()

func _check_discovery_requests(udp: PacketPeerUDP, timer: Timer) -> void:
	"""Checks for and responds to discovery requests."""
	# Check if we're still the host and have a valid lobby code
	if not is_host or lobby_code == "":
		# Stop the discovery server if we're no longer hosting
		print("NetworkManager: Stopping discovery server - is_host: ", is_host, ", lobby_code: '", lobby_code, "'")
		timer.queue_free()
		
		# Also stop status timer
		var status_timer = get_node_or_null("DiscoveryStatusTimer")
		if status_timer:
			status_timer.queue_free()
		return
	
	# Check UDP status periodically
	discovery_check_counter += 1
	if discovery_check_counter % 50 == 0:  # Every 5 seconds
		print("NetworkManager: Discovery server check #", discovery_check_counter/10, " - UDP bound: ", udp.is_bound(), ", packets available: ", udp.get_available_packet_count())
	
	if udp.get_available_packet_count() > 0:
		print("NetworkManager: [Instance ", get_instance_id(), "] Received discovery request packet")
		var packet = udp.get_packet()
		var packet_string = packet.get_string_from_utf8()
		print("NetworkManager: [Instance ", get_instance_id(), "] Discovery request content: ", packet_string)
		
		var request = JSON.parse_string(packet_string)
		
		if request and request.has("type") and request.type == "discover":
			print("NetworkManager: [Instance ", get_instance_id(), "] Valid discovery request received")
			print("NetworkManager: [Instance ", get_instance_id(), "] Request code: ", request.get("code", "none"), ", Our lobby code: '", lobby_code, "', Is host: ", is_host)
			print("NetworkManager: [Instance ", get_instance_id(), "] Has multiplayer peer: ", multiplayer.has_multiplayer_peer())
			
			if request.has("code") and request.code == lobby_code and is_host and lobby_code != "":
				# Respond to discovery request
				var client_ip = udp.get_packet_ip()
				print("NetworkManager: [Instance ", get_instance_id(), "] Responding to discovery request from ", client_ip)
				
				var response_udp = PacketPeerUDP.new()
				var connect_result = response_udp.connect_to_host(client_ip, GameConstants.NETWORK.DISCOVERY_PORT + 1)
				
				if connect_result != OK:
					print("NetworkManager: [Instance ", get_instance_id(), "] Failed to connect to client for response, error: ", connect_result)
					return
				
				var response = {"type": "response", "code": lobby_code}
				var json_string = JSON.stringify(response)
				var send_result = response_udp.put_packet(json_string.to_utf8_buffer())
				
				if send_result != OK:
					print("NetworkManager: [Instance ", get_instance_id(), "] Failed to send discovery response, error: ", send_result)
				else:
					print("NetworkManager: [Instance ", get_instance_id(), "] Successfully sent discovery response to ", client_ip)
				
				response_udp.close()
			else:
				print("NetworkManager: [Instance ", get_instance_id(), "] Discovery request rejected - code match: ", (request.get("code") == lobby_code), ", is_host: ", is_host, ", lobby_code empty: ", (lobby_code == ""))
		else:
			print("NetworkManager: [Instance ", get_instance_id(), "] Invalid discovery request packet")

func _on_connection_failed() -> void:
	"""Handle connection failure."""
	print("NetworkManager: Connection failed")
	
	# Clean up current peer
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	
	if not is_host and connection_retry_count < max_retry_attempts:
		print("NetworkManager: Starting reconnection attempts...")
		reconnection_timer.start()
	else:
		connection_failed.emit("Connection failed after %d attempts" % connection_retry_count)

func _on_server_disconnected() -> void:
	"""Handle server disconnection (for clients)."""
	print("NetworkManager: Server disconnected")
	
	# Clean up current peer
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	
	if connection_retry_count < max_retry_attempts:
		print("NetworkManager: Starting reconnection attempts...")
		reconnection_timer.start()
	else:
		connection_failed.emit("Server disconnected after %d reconnection attempts" % connection_retry_count)

func _attempt_reconnection() -> void:
	"""Attempt to reconnect to the server."""
	connection_retry_count += 1
	
	if connection_retry_count > max_retry_attempts:
		print("NetworkManager: Max reconnection attempts reached, giving up")
		reconnection_timer.stop()
		connection_failed.emit("Max reconnection attempts reached")
		return
	
	print("NetworkManager: Reconnection attempt %d/%d" % [connection_retry_count, max_retry_attempts])
	
	# Try to reconnect using stored lobby code
	if lobby_code != "":
		join_game_by_code(lobby_code)
	else:
		print("NetworkManager: No lobby code stored for reconnection")
		reconnection_timer.stop()

func _setup_nat_traversal() -> void:
	"""Setup NAT traversal using UPnP."""
	print("NetworkManager: Setting up NAT traversal...")
	
	# Try UPnP first
	var upnp = UPNP.new()
	var discover_result = upnp.discover()
	
	if discover_result == UPNP.UPNP_RESULT_SUCCESS:
		print("NetworkManager: UPnP device found")
		
		# Try to add port mapping
		var map_result = upnp.add_port_mapping(
			GameConstants.NETWORK.DEFAULT_PORT,
			GameConstants.NETWORK.DEFAULT_PORT,
			"BarkAndMoss_Game", 
			"TCP"
		)
		
		if map_result == UPNP.UPNP_RESULT_SUCCESS:
			upnp_enabled = true
			print("NetworkManager: UPnP port forwarding enabled for port ", GameConstants.NETWORK.DEFAULT_PORT)
			
			# Get external IP
			var external_ip = upnp.query_external_address()
			if external_ip != "":
				print("NetworkManager: External IP: ", external_ip)
		else:
			print("NetworkManager: UPnP port forwarding failed: ", map_result)
	else:
		print("NetworkManager: UPnP device discovery failed: ", discover_result)

func _cleanup_nat_traversal() -> void:
	"""Cleanup NAT traversal port mappings."""
	if upnp_enabled:
		print("NetworkManager: Cleaning up UPnP port mapping...")
		var upnp = UPNP.new()
		if upnp.discover() == UPNP.UPNP_RESULT_SUCCESS:
			upnp.delete_port_mapping(GameConstants.NETWORK.DEFAULT_PORT, "TCP")
		upnp_enabled = false

func _run_network_diagnostics() -> void:
	"""Run basic network diagnostics to help debug discovery issues."""
	print("NetworkManager: === NETWORK DIAGNOSTICS ===")
	
	# Check local network interfaces
	var local_ips = IP.get_local_addresses()
	print("NetworkManager: Local IP addresses: ", local_ips)
	
	# Test UDP socket creation
	var test_udp = PacketPeerUDP.new()
	var bind_result = test_udp.bind(0)  # Bind to any available port
	if bind_result == OK:
		print("NetworkManager: UDP socket creation: SUCCESS")
		var bound_port = test_udp.get_local_port()
		print("NetworkManager: Bound to local port: ", bound_port)
		test_udp.close()
	else:
		print("NetworkManager: UDP socket creation: FAILED (error: ", bind_result, ")")
	
	# Test discovery port availability
	var discovery_test = PacketPeerUDP.new()
	var discovery_bind = discovery_test.bind(GameConstants.NETWORK.DISCOVERY_PORT + 1)
	if discovery_bind == OK:
		print("NetworkManager: Discovery response port (", GameConstants.NETWORK.DISCOVERY_PORT + 1, "): AVAILABLE")
		discovery_test.close()
	else:
		print("NetworkManager: Discovery response port (", GameConstants.NETWORK.DISCOVERY_PORT + 1, "): BLOCKED (error: ", discovery_bind, ")")
	
	print("NetworkManager: === END DIAGNOSTICS ===")
