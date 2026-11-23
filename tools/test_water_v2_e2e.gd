extends Node
## Opaque-box 4-tier E2E test runner for Shadowspore Water System v2 & Left Test Squares.
## Run: /Users/nxye/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . --fixed-fps 60 res://tools/test_water_v2_e2e.tscn

const CTX_SCR: GDScript = preload("res://tools/test_water_v2_e2e_ctx.gd")
const T1_SCR: GDScript = preload("res://tools/test_water_v2_e2e_t1.gd")
const T2_SCR: GDScript = preload("res://tools/test_water_v2_e2e_t2.gd")
const T3_SCR: GDScript = preload("res://tools/test_water_v2_e2e_t3.gd")
const T4_SCR: GDScript = preload("res://tools/test_water_v2_e2e_t4.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var ctx: RefCounted = CTX_SCR.new() as RefCounted
	var tree: SceneTree = get_tree()
	print("=== WATER_V2_E2E START ===")

	await T1_SCR.call(&"run", tree, ctx)
	await T2_SCR.call(&"run", tree, ctx)
	await T3_SCR.call(&"run", tree, ctx)
	await T4_SCR.call(&"run", tree, ctx)

	var tier_checks: Dictionary = ctx.get(&"tier_checks") as Dictionary
	var tier_failures: Dictionary = ctx.get(&"tier_failures") as Dictionary
	var total_checks: int = int(ctx.get(&"checks"))
	var total_failures: int = int(ctx.get(&"failures"))

	print("=== WATER_V2_E2E SUMMARY ===")
	for t_id: String in ["T1", "T2", "T3", "T4"]:
		print("  %s: %d checks, %d failures" % [t_id, int(tier_checks.get(t_id, 0)), int(tier_failures.get(t_id, 0))])
	print("  Total: %d checks, %d failures" % [total_checks, total_failures])
	print("WATER_V2_E2E_OK" if total_failures == 0 else "WATER_V2_E2E_FAILED")
	tree.quit(0 if total_failures == 0 else 1)
