extends Node

## Smoke test headless del pipeline de grabacion.
## Correr: godot --headless --path . res://tests/smoke_recording.tscn

const AUDIO := "tests/test_tone.wav"
const TARGETS := [300.0, 700.0, 1100.0, 1500.0, 1900.0]
const MAX_FRAMES := 1200

var _rec: RecordingManager
var _next := 0
var _frames := 0
var _expected: Array[float] = []


func _ready() -> void:
	var abs_path := ProjectSettings.globalize_path("res://").path_join(AUDIO)
	var stream := AudioLoader.load_stream(abs_path)
	if stream == null:
		_fail("no se pudo cargar el WAV: %s" % abs_path)
		return
	print("audio ok, duracion = %.3f s" % stream.get_length())

	_rec = RecordingManager.new()
	add_child(_rec)
	_rec.recording_finished.connect(_on_finished)
	_rec.start(stream, abs_path)


func _process(_d: float) -> void:
	_frames += 1
	if _frames > MAX_FRAMES:
		_fail("timeout: t=%.1f raw=%.1f playing=%s" % [
			_rec.get_time_ms(), _rec.clock.get_raw_audio_time_ms(), _rec.clock.player.playing])
		return
	if not _rec.is_recording():
		return

	var t := _rec.get_time_ms()
	if _next < TARGETS.size() and t >= TARGETS[_next]:
		_expected.append(t)
		var ev := InputEventKey.new()
		ev.physical_keycode = Settings.binding(Settings.SLOT_PRIMARY, _next % Lanes.COUNT)
		ev.pressed = true
		Input.parse_input_event(ev)
		_next += 1
	if t > 2500.0:
		_rec.stop()


func _on_finished(chart: Chart) -> void:
	set_process(false)
	print("notas grabadas: %d (esperadas %d)" % [chart.notes.size(), TARGETS.size()])
	if chart.notes.size() != TARGETS.size():
		_fail("cantidad de notas incorrecta")
		return

	var max_err := 0.0
	for i in chart.notes.size():
		var err: float = absf(float(chart.notes[i].timestamp_ms) - (_expected[i] - Settings.offset_ms))
		max_err = maxf(max_err, err)
		print("  lane %d  t=%d ms  (input a %.1f ms, err %.1f ms)" % [
			chart.notes[i].lane, chart.notes[i].timestamp_ms, _expected[i], err])

	var out := ProjectSettings.globalize_path("res://").path_join("tests/test_tone.normal.chart.json")
	if chart.save_to_file(out) != OK:
		_fail("fallo al guardar el chart")
		return
	var reloaded := Chart.load_from_file(out)
	if reloaded == null or reloaded.notes.size() != chart.notes.size():
		_fail("round-trip JSON roto")
		return
	for i in reloaded.notes.size():
		if reloaded.notes[i].timestamp_ms != chart.notes[i].timestamp_ms \
				or reloaded.notes[i].lane != chart.notes[i].lane:
			_fail("round-trip JSON: nota %d no coincide" % i)
			return

	print("round-trip JSON ok | error max de timestamp: %.1f ms" % max_err)
	print("SMOKE TEST OK")
	get_tree().quit(0)


func _fail(msg: String) -> void:
	push_error("SMOKE TEST FAIL: %s" % msg)
	print("SMOKE TEST FAIL: %s" % msg)
	get_tree().quit(1)
