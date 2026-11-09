extends "res://src/world/world_level.gd"
## The world of the main menu: the real WorldLevel with nobody in it. Loaded at run time by `MainMenu` (never named in its types: a parse-time reference to
## WorldLevel before TestLevel is compiled makes a dependency cycle), and put on the scene root with set_script after the scene was instantiated.


func _spawn_player(_id: int) -> void:
	pass
