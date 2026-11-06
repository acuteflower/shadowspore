class_name RoofPerch
extends Node2D
## A place on a building (a roof's edge, a lamp's arm, a bench's back, a fence post) where a bird may land: the node stands just in front of the piece's feet (so a bird sorts
## in front of the building) and `perch_height` is how many px the bird's feet sit above it. Same contract as a tree for the corvid controller: it asks `is_depleted()`
## (a piece that is still a site, was taken down or is gone has no perch). Data: `perches` [[x, y, height], ...] of a town piece, relative to its feet.

var host: Node
var perch_height: float = 20.0


func _ready() -> void:
	add_to_group("town_perches")


func is_depleted() -> bool:
	if host == null or not is_instance_valid(host) or host.is_queued_for_deletion():
		return true
	return host.has_method("is_done") and not bool(host.call("is_done"))
