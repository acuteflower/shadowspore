extends Node
## Global signal hub. Add signals here as systems need to talk to each other.

signal toast_requested(message: String)


func toast(message: String) -> void:
	toast_requested.emit(message)
