extends Node2D
## One-shot void rift with a shard burst. Spawned at both ends of a blink; frees itself.

@onready var _rift: Sprite2D = $Rift


func _ready() -> void:
	var tween: Tween = create_tween()
	tween.tween_property(_rift, "frame", _rift.hframes - 1, 0.4).from(0)
	tween.tween_interval(0.4) ## let the shards finish
	tween.tween_callback(queue_free)
