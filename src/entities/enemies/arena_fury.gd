class_name ArenaFury
extends RefCounted
## The arena catches fire (docs/boss_sky_cleaver.md, the start of phase 3): the turquoise light of the floor (`GroundDecal.ignite`) and of every pillar that still
## stands (`ArenaPillar.ignite`) turns into pink-violet fire with flames standing on parts of it. `ignite` / `extinguish` take the seconds the change needs (0 = at once).
## The fight calls it on every peer; the arena is found by the boss's arena id.


static func ignite(boss: SkyCleaver, seconds: float) -> void:
	_each(boss, func(decal: GroundDecal) -> void: decal.ignite(seconds), func(pillar: ArenaPillar) -> void: pillar.ignite(seconds))


static func extinguish(boss: SkyCleaver, seconds: float) -> void:
	_each(boss, func(decal: GroundDecal) -> void: decal.extinguish(seconds), func(pillar: ArenaPillar) -> void: pillar.extinguish(seconds))


static func _each(boss: SkyCleaver, on_floor: Callable, on_pillar: Callable) -> void:
	if boss == null or not boss.is_inside_tree():
		return
	var tree: SceneTree = boss.get_tree()
	for node: Node in tree.get_nodes_in_group("ground_glow"):
		var decal: GroundDecal = node as GroundDecal
		if decal != null and decal.decal_id == boss.arena + "_arena":
			on_floor.call(decal)
	for node: Node in tree.get_nodes_in_group("arena_pillars"):
		var pillar: ArenaPillar = node as ArenaPillar
		if pillar != null and pillar.arena == boss.arena:
			on_pillar.call(pillar)
