extends SceneTree
func _initialize() -> void:
	var scene: PackedScene = load("res://src/world/main.tscn")
	root.add_child(scene.instantiate())
	_run()
func _walk(p: Node2D, tag: String) -> void:
	var s: Vector2 = p.global_position
	Input.action_press("move_up")
	for i: int in 60:
		await physics_frame
	Input.action_release("move_up")
	print(tag, " moved ", p.global_position - s, " busy=", p.get("_busy"), " kind=", p.get("_busy_kind"))
func _run() -> void:
	for i: int in 240:
		await process_frame
	var p: Node2D = get_nodes_in_group("players")[0] as Node2D
	var inv: Object = p.get("inventory")
	inv.add_item("potion_leere_1", 3)
	for s: int in 8:
		if String(inv.slots[s].get("id", "")) == "potion_leere_1":
			print("slot ", s)
			inv.call("request", "select", [s])
			p.call("use_slot", s)
			break
	for i: int in 90:
		await physics_frame
	print("busy after ", p.get("_busy"))
	await _walk(p, "after drink")
	quit()
