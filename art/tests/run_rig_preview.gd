extends Node2D
## Deterministic enlarged captures for visual QA of the two-leg run rig.

var state := 1
var facing := 1
var _state_time := 0.0
var _flash := 0.0


func _ready() -> void:
	for frame_index in 8:
		_state_time = float(frame_index) / 20.0 + 0.001
		await get_tree().process_frame
		await get_tree().process_frame
		var capture := get_viewport().get_texture().get_image()
		var capture_path := "res://art/previews/run_rig_v3_frame_%02d.png" % (frame_index + 1)
		var save_error := capture.save_png(ProjectSettings.globalize_path(capture_path))
		if save_error != OK:
			push_error("Could not save %s" % capture_path)
	get_tree().quit()
