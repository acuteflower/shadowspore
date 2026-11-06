extends SceneTree
## Bakes the world's coast into assets/world/land_sdf.png (1 pixel per tile): a signed distance to
## the coast, in 1/8 tile steps around 128 (>= 128 land, below void; range about +-16 tiles). The
## game paints and blocks tiles from it and the void-edge shader samples it:
##   Godot --headless --path . --script tools/bake_land_sdf.gd
## then `Godot --headless --import --path .`. Needs data/world_map.json. Takes about a minute.

const FAR: int = 1 << 20

func _init() -> void:
	var map: RegionMap = RegionMap.new(0, JSON.parse_string(FileAccess.get_file_as_string("res://data/world_map.json")) as Dictionary)
	var side: int = RegionMap.WORLD_TILES
	var mask: PackedByteArray = map.tile_land_mask()
	print("mask done")
	var inside: PackedInt32Array = _distance(mask, side, 1)
	var outside: PackedInt32Array = _distance(mask, side, 0)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(side * side)
	for i: int in bytes.size():
		var d: float = (inside[i] / 3.0 - 0.5) if mask[i] == 1 else -(outside[i] / 3.0 - 0.5)
		bytes[i] = clampi(128 + roundi(d * 8.0), 0, 255)
	Image.create_from_data(side, side, false, Image.FORMAT_L8, bytes).save_png("res://assets/world/land_sdf.png")
	print("baked assets/world/land_sdf.png")
	quit()


## Distance (3-4 chamfer, units of a third of a tile) from every cell with `mask == value` to the
## nearest cell with another value; the world's outside counts as void.
func _distance(mask: PackedByteArray, side: int, value: int) -> PackedInt32Array:
	var dist: PackedInt32Array = PackedInt32Array()
	dist.resize(side * side)
	for y: int in side:
		for x: int in side:
			var i: int = y * side + x
			if mask[i] != value:
				dist[i] = 0
			elif value == 1 and (x == 0 or y == 0 or x == side - 1 or y == side - 1):
				dist[i] = 3
			else:
				dist[i] = FAR
	for y: int in side:
		for x: int in side:
			var i: int = y * side + x
			if dist[i] == 0:
				continue
			var best: int = dist[i]
			if x > 0:
				best = mini(best, dist[i - 1] + 3)
			if y > 0:
				best = mini(best, dist[i - side] + 3)
				if x > 0:
					best = mini(best, dist[i - side - 1] + 4)
				if x < side - 1:
					best = mini(best, dist[i - side + 1] + 4)
			dist[i] = best
	for y: int in range(side - 1, -1, -1):
		for x: int in range(side - 1, -1, -1):
			var i: int = y * side + x
			if dist[i] == 0:
				continue
			var best: int = dist[i]
			if x < side - 1:
				best = mini(best, dist[i + 1] + 3)
			if y < side - 1:
				best = mini(best, dist[i + side] + 3)
				if x < side - 1:
					best = mini(best, dist[i + side + 1] + 4)
				if x > 0:
					best = mini(best, dist[i + side - 1] + 4)
			dist[i] = best
	return dist
