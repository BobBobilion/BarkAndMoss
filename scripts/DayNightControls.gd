class_name DayNightControls
extends Control

# References to UI elements
@onready var time_label: Label = $Panel/VBoxContainer/TimeLabel
@onready var time_slider: HSlider = $Panel/VBoxContainer/TimeSlider
@onready var speed_label: Label = $Panel/VBoxContainer/SpeedLabel
@onready var speed_slider: HSlider = $Panel/VBoxContainer/SpeedSlider
@onready var toggle_button: Button = $Panel/VBoxContainer/ToggleButton

# Reference to DayNightCycle node
var day_night_cycle: DayNightCycle = null
var cycle_speed: float = 1.0
var is_paused: bool = false


func _ready() -> void:
	"""Initialize the controls."""
	# Find DayNightCycle in the scene
	var main_scene = get_tree().get_root().get_node("Main")
	if main_scene:
		day_night_cycle = main_scene.get_node("DayNightCycle") as DayNightCycle
		
	if not day_night_cycle:
		print("DayNightControls: Warning - Could not find DayNightCycle node")
		return
		
	# Connect UI signals
	time_slider.value_changed.connect(_on_time_slider_changed)
	speed_slider.value_changed.connect(_on_speed_slider_changed)
	toggle_button.toggled.connect(_on_toggle_button_toggled)
	
	# Set initial values
	time_slider.value = day_night_cycle.get_current_time_of_day()
	_update_time_label(time_slider.value)
	
	# Connect to day/night signals
	day_night_cycle.day_started.connect(_on_day_started)
	day_night_cycle.night_started.connect(_on_night_started)
	day_night_cycle.complete_darkness_started.connect(_on_darkness_started)
	day_night_cycle.complete_darkness_ended.connect(_on_darkness_ended)


func _process(_delta: float) -> void:
	"""Update UI based on current time."""
	if not day_night_cycle or is_paused:
		return
		
	# Update time slider to reflect current time
	time_slider.set_value_no_signal(day_night_cycle.get_current_time_of_day())
	_update_time_label(day_night_cycle.get_current_time_of_day())


func _on_time_slider_changed(value: float) -> void:
	"""Handle time slider changes."""
	if day_night_cycle:
		day_night_cycle.set_time_of_day(value)
		_update_time_label(value)


func _on_speed_slider_changed(value: float) -> void:
	"""Handle speed slider changes."""
	cycle_speed = value
	speed_label.text = "Speed: %.1fx" % value
	
	if day_night_cycle:
		# Adjust the cycle duration based on speed
		day_night_cycle.set_process(not is_paused)
		if not is_paused:
			Engine.time_scale = cycle_speed


func _on_toggle_button_toggled(pressed: bool) -> void:
	"""Handle pause/resume toggle."""
	is_paused = pressed
	toggle_button.text = "Resume Cycle" if is_paused else "Pause Cycle"
	
	if day_night_cycle:
		day_night_cycle.set_process(not is_paused)


func _update_time_label(time_value: float) -> void:
	"""Update the time label based on the current time value."""
	# Convert 0-1 to 0-24 hours
	var hours: int = int(time_value * 24.0)
	var minutes: int = int((time_value * 24.0 - hours) * 60.0)
	
	# Get phase of day
	var phase: String = ""
	if day_night_cycle:
		phase = day_night_cycle.get_phase_of_day()
	else:
		# Calculate phase manually if cycle not available
		if time_value < 0.25:
			phase = "night"
		elif time_value < 0.35:
			phase = "dawn"
		elif time_value < 0.45:
			phase = "morning"
		elif time_value < 0.65:
			phase = "day"
		elif time_value < 0.75:
			phase = "evening"
		elif time_value < 0.85:
			phase = "dusk"
		else:
			phase = "night"
	
	time_label.text = "Time: %02d:%02d (%s)" % [hours, minutes, phase.capitalize()]


func _on_day_started() -> void:
	"""Handle day started signal."""
	print("DayNightControls: Day has started!")


func _on_night_started() -> void:
	"""Handle night started signal."""
	print("DayNightControls: Night has started!")


func _on_darkness_started() -> void:
	"""Handle complete darkness started signal."""
	print("DayNightControls: Complete darkness!")


func _on_darkness_ended() -> void:
	"""Handle complete darkness ended signal."""
	print("DayNightControls: Light returns!") 