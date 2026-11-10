class_name Interactable
extends Node2D
## Anything the player can use with E. The local player looks for the nearest one that offers an
## action (`prompt()` not empty) within `INTERACT_RANGE`, it shows the prompt above itself, and
## pressing E calls `interact`. Subclasses decide what happens (and ask the host if it matters).

const INTERACT_RANGE: float = 16.0 ## px beyond the object's own radius

var _prompt_node: InteractPrompt


func _enter_tree() -> void:
	add_to_group("interactables")


## What E does right now ("" = nothing, so no prompt).
func prompt() -> String:
	return ""


## Why E does nothing right now although the prompt shows ("" = it works). A non-empty hint greys the prompt out and shows the reason.
func prompt_hint() -> String:
	return ""


## Distance the player's feet are from the object's edge.
func reach_distance(_from: Vector2) -> float:
	return INF


## Local player only.
func interact(_player: Player) -> void:
	pass


func set_focused(on: bool) -> void:
	if on and _prompt_node == null:
		_prompt_node = InteractPrompt.new()
		_prompt_node.position = prompt_position()
		add_child(_prompt_node)
	if _prompt_node != null:
		_prompt_node.position = prompt_position()
		_prompt_node.show_text(prompt() if on else "", prompt_hint() if on else "")


## Where the prompt hovers, relative to the object.
func prompt_position() -> Vector2:
	return Vector2(0, -24)
