class_name WorldTrial
extends Node2D
## Base of every trial of the Wächterin placed in the world (docs/raetsel_konzept.md): what `Puzzles` asks of a trial. A trial is built on every peer
## from its `data/puzzles.json` entry (`setup` before it enters the tree), runs itself host-authoritatively and emits `solved` on the host once;
## `Puzzles` then marks it, saves it and brings the reward chest (`reward_rise`: out of the earth instead of the light).

signal solved(id: String, at: Vector2)

var id: String = ""
var tier: String = "common"
var info: Dictionary = {} ## its entry of data/puzzles.json


func setup(data: Dictionary, _tuning: Dictionary) -> void:
	info = data
	id = String(data.get("id", ""))
	tier = String(data.get("tier", "common"))


## Where a player stands to begin it (dev teleport).
func start_position() -> Vector2:
	return global_position


## Where the reward chest stands.
func end_position() -> Vector2:
	return global_position


## True: the chest breaks out of the earth; false: it comes down in a pillar of light.
func reward_rise() -> bool:
	return false


## Items that go into the reward chest besides its rolled loot (the raven's pawn). Host.
func reward_extra() -> Array:
	return []


## Solved before (save file, snapshot): show the solved look at once.
func set_solved_instant() -> void:
	pass


## Dev: back to the start.
func reset_trial() -> void:
	pass


## What of an unsolved trial outlives a save ({} = nothing). Host.
func export_progress() -> Dictionary:
	return {}


func import_progress(_data: Dictionary) -> void:
	pass


## The living players as the trials see them: [{pos, sneak, loud, peer, player}].
static func living_players() -> Array:
	var out: Array = []
	for p: Player in Player.all:
		if not is_instance_valid(p) or p.health == null or p.health.current <= 0.0:
			continue
		var loud: bool = (p.sprinting and p.velocity.length() > p.max_speed * 1.1) or (p.attack != null and p.attack.is_swinging())
		out.append({"pos": p.global_position, "sneak": p.stealth != null and p.stealth.sneaking, "loud": loud, "peer": p.name.to_int(), "player": p, "speed": p.velocity.length()})
	return out
