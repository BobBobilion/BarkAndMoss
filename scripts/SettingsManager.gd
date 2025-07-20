# =============================================================================
# SHARED SETTINGS MANAGEMENT SYSTEM  
# =============================================================================

## Shared settings management for consistent behavior across menus.
extends RefCounted

static func load_settings() -> Dictionary:
	"""Load all settings from config file."""
	var config = ConfigFile.new()
	var err = config.load("user://settings.cfg")
	
	var settings = {
		"master_volume": 75.0,
		"music_volume": 75.0,
		"sfx_volume": 75.0,
		"fullscreen": false,
		"render_distance": GameConstants.RENDER_DISTANCE.DEFAULT
	}
	
	if err == OK:
		settings.master_volume = config.get_value("audio", "master_volume", 75.0)
		settings.music_volume = config.get_value("audio", "music_volume", 75.0)
		settings.sfx_volume = config.get_value("audio", "sfx_volume", 75.0)
		settings.fullscreen = config.get_value("display", "fullscreen", false)
		settings.render_distance = config.get_value("graphics", "render_distance", GameConstants.RENDER_DISTANCE.DEFAULT)
	
	return settings

static func save_settings(volume: float, fullscreen: bool) -> void:
	"""Save all settings to config file."""
	var config = ConfigFile.new()
	
	# Save volume and fullscreen
	config.set_value("audio", "master_volume", volume)
	config.set_value("display", "fullscreen", fullscreen)
	
	# Save to file
	config.save("user://settings.cfg")

static func apply_master_volume_setting(_value: float) -> void:
	"""Apply master volume setting (for storage, not direct audio)."""
	# Master volume is applied through multiplication in the UI handlers
	pass

static func apply_music_volume_setting(_value: float) -> void:
	"""Apply music volume setting (for storage, not direct audio)."""
	# Music volume is applied through multiplication in the UI handlers
	pass

static func apply_sfx_volume_setting(_value: float) -> void:
	"""Apply SFX volume setting (for storage, not direct audio)."""
	# SFX volume is applied through multiplication in the UI handlers
	pass

static func apply_effective_music_volume(effective_value: float) -> void:
	"""Apply the calculated effective music volume to the Music audio bus."""
	var volume_db: float = linear_to_db(effective_value / 100.0)
	var music_bus_index = AudioServer.get_bus_index("Music")
	if music_bus_index != -1:
		AudioServer.set_bus_volume_db(music_bus_index, volume_db)
	else:
		# Fallback to Master bus if Music bus doesn't exist
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), volume_db)

static func apply_effective_sfx_volume(effective_value: float) -> void:
	"""Apply the calculated effective SFX volume to the SFX audio bus."""
	var volume_db: float = linear_to_db(effective_value / 100.0)
	var sfx_bus_index = AudioServer.get_bus_index("SFX")
	if sfx_bus_index != -1:
		AudioServer.set_bus_volume_db(sfx_bus_index, volume_db)
	else:
		# Fallback to Master bus if SFX bus doesn't exist
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), volume_db)

static func apply_volume_setting(value: float) -> void:
	"""Legacy method for backward compatibility."""
	apply_effective_music_volume(value)
	apply_effective_sfx_volume(value)

static func save_volume_settings(master_volume: float, music_volume: float, sfx_volume: float, fullscreen: bool) -> void:
	"""Save all volume settings and fullscreen to config file."""
	var config = ConfigFile.new()
	
	# Load existing settings first to preserve render distance
	var err = config.load("user://settings.cfg")
	
	# Save all volume settings
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("display", "fullscreen", fullscreen)
	
	# Save to file
	config.save("user://settings.cfg")

static func save_all_settings(master_volume: float, music_volume: float, sfx_volume: float, fullscreen: bool, render_distance: int) -> void:
	"""Save all settings including render distance to config file."""
	var config = ConfigFile.new()
	
	# Save all settings
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("display", "fullscreen", fullscreen)
	config.set_value("graphics", "render_distance", render_distance)
	
	# Save to file
	config.save("user://settings.cfg")

static func apply_render_distance_setting(distance: int) -> void:
	"""Apply render distance setting to the chunk system."""
	# Clamp the value to valid range
	var clamped_distance = clamp(distance, GameConstants.RENDER_DISTANCE.MIN, GameConstants.RENDER_DISTANCE.MAX)
	
	# Find and update PlayerTracker
	var game_managers: Array[Node] = Engine.get_main_loop().get_nodes_in_group("game_manager")
	if game_managers.size() > 0:
		var game_manager = game_managers[0]
		if game_manager.has_method("get_chunk_manager"):
			var chunk_manager = game_manager.get_chunk_manager()
			if chunk_manager and chunk_manager.player_tracker:
				# Check if the distance is actually different to avoid redundant work
				var current_distance = chunk_manager.player_tracker.get_render_distance() if chunk_manager.player_tracker.has_method("get_render_distance") else -1
				if current_distance != clamped_distance:
					chunk_manager.player_tracker.set_render_distance(clamped_distance)
					print("SettingsManager: Applied render distance: ", clamped_distance)
				else:
					print("SettingsManager: Render distance unchanged: ", clamped_distance)
			else:
				print("SettingsManager: ChunkManager or PlayerTracker not found")
		else:
			print("SettingsManager: GameManager has no get_chunk_manager method")
	else:
		print("SettingsManager: No GameManager found")

static func apply_fullscreen_setting(enabled: bool) -> void:
	"""Apply fullscreen setting to display system."""
	if enabled:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED) 