class_name WeaveRules
extends RefCounted
## The rules of the root weave (Wurzelgeflecht, docs/raetsel_konzept.md 6a), pure and deterministic: every peer plays the same presses to the same
## state. Mirror of tools/check_root_weave.py (keep both in step). A weave entry of data/puzzles.json has `cubes` {id: {kind, at, lit, from}} and
## `roots` [[a, b, one_way]]; kinds: "cube", "seed" (lets the cubes whose `from` it is rise the first time it is lit), "thorn" (cannot be touched),
## "heart" and "crown" (never switched). State = two bit masks over the cube ids in sorted order: `lit` and `present`.
## Pressing a touchable present cube switches it and every present cube a root leads to from it (one-way roots only a -> b), then every lit
## present seed whose cubes are not there yet lets them rise in their own start state (repeated). Goal "all": every cube lit; "path": a chain of
## lit cubes along roots links the heart to the crown.

var ids: Array[String] = []
var index: Dictionary = {} ## id -> bit
var kinds: Array[String] = []
var outs: Array = [] ## bit -> Array[int] cubes a press reaches
var links: Array = [] ## bit -> Array[int] every root end (both ways, for the path and the drawing)
var children: Array = [] ## bit -> Array[int] cubes that rise from this seed
var start_lit: Array[bool] = []
var born: Array[int] = [] ## bit -> seed bit it rises from, -1 = there from the start
var goal: String = "all"
var heart: int = -1
var crown: int = -1


func _init(data: Dictionary) -> void:
	var cubes: Dictionary = data.get("cubes", {}) as Dictionary
	for k: Variant in cubes:
		ids.append(String(k))
	ids.sort()
	for i: int in ids.size():
		index[ids[i]] = i
		outs.append([])
		links.append([])
		children.append([])
	for i: int in ids.size():
		var c: Dictionary = cubes[ids[i]] as Dictionary
		var kind: String = String(c.get("kind", "cube"))
		kinds.append(kind)
		start_lit.append(bool(c.get("lit", false)))
		var from: String = String(c.get("from", ""))
		born.append(int(index.get(from, -1)) if from != "" else -1)
		if kind == "heart":
			heart = i
		elif kind == "crown":
			crown = i
	for i: int in ids.size():
		if born[i] >= 0:
			(children[born[i]] as Array).append(i)
	for r: Variant in data.get("roots", []) as Array:
		var ra: Array = r as Array
		var a: int = int(index.get(String(ra[0]), -1))
		var b: int = int(index.get(String(ra[1]), -1))
		if a < 0 or b < 0:
			continue
		var one: bool = ra.size() > 2 and bool(ra[2])
		(links[a] as Array).append(b)
		(links[b] as Array).append(a)
		(outs[a] as Array).append(b)
		if not one:
			(outs[b] as Array).append(a)
	goal = String(data.get("goal", "all"))


func size() -> int:
	return ids.size()


func bit_of(id: String) -> int:
	return int(index.get(id, -1))


func touchable(i: int) -> bool:
	return kinds[i] == "cube" or kinds[i] == "seed"


func switchable(i: int) -> bool:
	return kinds[i] != "heart" and kinds[i] != "crown"


static func has(mask: int, i: int) -> bool:
	return (mask >> i) & 1 == 1


## [lit, present] the moment the heart is put out.
func start() -> PackedInt64Array:
	var lit: int = 0
	var pres: int = 0
	for i: int in ids.size():
		if born[i] < 0:
			pres |= 1 << i
			if start_lit[i]:
				lit |= 1 << i
	return grow(lit, pres, [])


## Lets every lit seed rise its cubes; `risen` collects the bits that came up (in order).
func grow(lit: int, pres: int, risen: Array) -> PackedInt64Array:
	var changed: bool = true
	while changed:
		changed = false
		for i: int in ids.size():
			var ch: Array = children[i] as Array
			if kinds[i] != "seed" or ch.is_empty() or not has(pres, i) or not has(lit, i) or has(pres, int(ch[0])):
				continue
			for c: int in ch:
				pres |= 1 << c
				if start_lit[c]:
					lit |= 1 << c
				risen.append(c)
			changed = true
	return PackedInt64Array([lit, pres])


## The cubes a press of `i` switches (itself first), as present now.
func reach(i: int, pres: int) -> Array[int]:
	var out: Array[int] = [i]
	for j: int in outs[i] as Array:
		if has(pres, j) and switchable(j) and not out.has(j):
			out.append(j)
	return out


## One press: [lit, present] after it (with growth); `risen` gets what came up.
func press(lit: int, pres: int, i: int, risen: Array) -> PackedInt64Array:
	for j: int in reach(i, pres):
		lit ^= 1 << j
	return grow(lit, pres, risen)


## The lit cubes the heart's light reaches along roots (goal "path"; for "all" the same walk shows the sap).
func flow(lit: int, pres: int) -> int:
	if heart < 0:
		return 0
	var seen: int = 1 << heart
	var stack: Array[int] = [heart]
	while not stack.is_empty():
		var a: int = stack.pop_back()
		for b: int in links[a] as Array:
			if has(seen, b) or not has(pres, b):
				continue
			if b == crown or (switchable(b) and has(lit, b)):
				seen |= 1 << b
				if b != crown:
					stack.append(b)
	return seen


func solved(lit: int, pres: int) -> bool:
	if goal == "path":
		return crown >= 0 and has(flow(lit, pres), crown)
	for i: int in ids.size():
		if switchable(i) and not (has(pres, i) and has(lit, i)):
			return false
	return true


## The fewest presses from the start (-1 = no way).
func shortest() -> int:
	var path: Array = solution()
	return path.size() if not path.is_empty() or solved(start()[0], start()[1]) else -1


## Breadth-first search: one shortest list of cube ids to touch ([] = solved already or no way). Tests and the dev check use it.
func solution() -> Array:
	var s: PackedInt64Array = start()
	if solved(s[0], s[1]):
		return []
	var back: Dictionary = {} ## key -> [previous key, bit]
	var seen: Dictionary = {s[0] | (s[1] << 32): 0} ## key: lit in the low, present in the high half (weaves have far fewer than 32 cubes)
	var queue: Array[PackedInt64Array] = [s]
	var head: int = 0
	while head < queue.size():
		var cur: PackedInt64Array = queue[head]
		head += 1
		var d: int = int(seen[cur[0] | (cur[1] << 32)])
		for i: int in ids.size():
			if not has(cur[1], i) or not touchable(i):
				continue
			var n: PackedInt64Array = press(cur[0], cur[1], i, [])
			var key: int = n[0] | (n[1] << 32)
			if seen.has(key):
				continue
			seen[key] = d + 1
			back[key] = [cur[0] | (cur[1] << 32), i]
			if solved(n[0], n[1]):
				var path: Array = []
				var k: int = key
				while back.has(k):
					var step: Array = back[k] as Array
					path.push_front(ids[int(step[1])])
					k = int(step[0])
				return path
			queue.append(n)
	return []
