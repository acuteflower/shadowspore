class_name AdminCommands
extends RefCounted
## Host-authoritative Admin & Offline-Dev Command System for Shadowspore 2.0.
##
## Security invariants:
##   1. Strict Release builds (`CloudSession.is_strict_release()`): ONLY Nakama-verified `role == "admin"` accounts.
##   2. Online logged-in Debug builds (`CloudSession.is_logged_in()`): ONLY Nakama-verified `role == "admin"` accounts
##      (so non-admin test accounts never receive admin rights even in debug builds).
##   3. Offline Dev mode (`OS.is_debug_build() and not strict and not logged in`): local host (`peer <= 1`) only.
##   4. Remote Co-op peers (`sender > 1`): STRICTLY requires server-verified `NetworkManager.is_peer_admin(sender)`.
##   5. Every command executes on the Host (peer 1) and re-verifies authorization server-side; client-owned player
##      operations (teleport, stamina, speed) are pushed back via host-only `@rpc("authority")` on `Player`.

const COMMANDS: Array[Dictionary] = [
	# --- Spieler & Cheats ---
	{"cmd": "/god", "aliases": [], "cat": "spieler", "usage": "/god [on|off] [Spieler]", "desc": "Unverwundbarkeit umschalten"},
	{"cmd": "/stamina", "aliases": ["/ausdauer"], "cat": "spieler", "usage": "/stamina [on|off] [Spieler]", "desc": "Unendliche Ausdauer"},
	{"cmd": "/heal", "aliases": ["/heilen"], "cat": "spieler", "usage": "/heal [Spieler|all]", "desc": "Voll heilen & Effekte entfernen"},
	{"cmd": "/hp", "aliases": [], "cat": "spieler", "usage": "/hp <Wert> [Spieler]", "desc": "Lebenspunkte setzen"},
	{"cmd": "/speed", "aliases": ["/tempo"], "cat": "spieler", "usage": "/speed <0.25-4|reset> [Spieler]", "desc": "Lauftempo-Multiplikator"},
	{"cmd": "/give", "aliases": ["/item"], "cat": "spieler", "usage": "/give <Item> [Menge|max] [Spieler]", "desc": "Gegenstand verleihen"},
	{"cmd": "/gold", "aliases": ["/geld", "/copper", "/kupfer"], "cat": "spieler", "usage": "/gold <Menge> [Spieler]", "desc": "Gold oder Kupfer geben"},
	{"cmd": "/xp", "aliases": [], "cat": "spieler", "usage": "/xp <Menge> [Spieler]", "desc": "Erfahrung verleihen"},
	{"cmd": "/level", "aliases": ["/lvl"], "cat": "spieler", "usage": "/level <Stufe> [Spieler]", "desc": "Stufe setzen"},
	{"cmd": "/effect", "aliases": ["/effekt"], "cat": "spieler", "usage": "/effect <ID|clear> [Sek] [Spieler]", "desc": "Statuseffekt setzen/löschen"},
	{"cmd": "/kill", "aliases": [], "cat": "spieler", "usage": "/kill [Spieler]", "desc": "Spieler besiegen"},
	{"cmd": "/butcher", "aliases": ["/slay"], "cat": "spieler", "usage": "/butcher [Radius|all]", "desc": "Gegner im Umkreis entfernen"},
	# --- Welt & Zonen ---
	{"cmd": "/tp", "aliases": ["/teleport", "/warp"], "cat": "welt", "usage": "/tp <Zone|Spieler|home|x y>", "desc": "Teleportieren"},
	{"cmd": "/bring", "aliases": ["/summon"], "cat": "welt", "usage": "/bring <Spieler|all>", "desc": "Spieler zu dir holen"},
	{"cmd": "/time", "aliases": ["/zeit"], "cat": "welt", "usage": "/time <tag|nacht|HH:MM|lock|unlock>", "desc": "Uhrzeit steuern"},
	{"cmd": "/day", "aliases": ["/tag"], "cat": "welt", "usage": "/day <Nummer|+1>", "desc": "Spieltag setzen"},
	{"cmd": "/weather", "aliases": ["/wetter"], "cat": "welt", "usage": "/weather <ID|auto>", "desc": "Wetter erzwingen"},
	{"cmd": "/spawn", "aliases": [], "cat": "welt", "usage": "/spawn <Gegner> [Anzahl]", "desc": "Gegner beschwören"},
	{"cmd": "/map", "aliases": ["/karte"], "cat": "welt", "usage": "/map <reveal|reset|atlas>", "desc": "Karte & Atlas steuern"},
	{"cmd": "/save", "aliases": ["/speichern"], "cat": "welt", "usage": "/save", "desc": "Welt sofort speichern"},
	# --- Multiplayer & Moderation ---
	{"cmd": "/players", "aliases": ["/who", "/liste"], "cat": "multiplayer", "usage": "/players", "desc": "Spielerliste & Status"},
	{"cmd": "/kick", "aliases": [], "cat": "multiplayer", "usage": "/kick <Spieler> [Grund]", "desc": "Spieler entfernen"},
	{"cmd": "/announce", "aliases": ["/say", "/broadcast"], "cat": "multiplayer", "usage": "/announce <Text>", "desc": "Ankündigung an alle senden"},
	{"cmd": "/joinmode", "aliases": ["/beitritt"], "cat": "multiplayer", "usage": "/joinmode <open|ask|private>", "desc": "Koop-Beitritt ändern"},
	{"cmd": "/roomcode", "aliases": ["/code"], "cat": "multiplayer", "usage": "/roomcode [Code|new]", "desc": "Raumcode anzeigen/setzen"},
	{"cmd": "/admin", "aliases": ["/ahelp"], "cat": "multiplayer", "usage": "/admin [spieler|welt|multiplayer]", "desc": "Admin-Befehlsübersicht"},
]

const TIME_PRESETS: Dictionary = {
	"morgen": 0.25, "morning": 0.25, "dawn": 0.23, "sonnenaufgang": 0.25,
	"tag": 0.45, "day": 0.45, "mittag": 0.50, "noon": 0.50,
	"abend": 0.77, "dusk": 0.79, "evening": 0.77,
	"nacht": 0.92, "night": 0.92, "mitternacht": 0.0, "midnight": 0.0,
}

const KNOWN_ENEMIES: PackedStringArray = [
	"shadow_spider", "void_listener", "void_crusher", "light_fisher", "quartz_golem",
]


# ------------------------------------------------------------------ Authorization Gates

## True iff the local client may see admin UI cues / dispatch admin commands.
## Still strictly re-verified on the Host before anything mutates state.
static func can_use_local() -> bool:
	if not GameGuard.is_gameplay_allowed():
		return false
	if CloudSession.is_strict_release():
		return CloudSession.is_admin()
	if CloudSession.is_logged_in():
		return CloudSession.is_admin()
	if not OS.is_debug_build():
		return false
	return not NetworkManager.is_multiplayer_session() or NetworkManager.multiplayer.is_server()


## Server-side authority gate. Called by the Host on EVERY admin RPC / local admin command.
static func is_sender_authorized(sender: int) -> bool:
	if not GameGuard.is_gameplay_allowed():
		return false
	if sender <= 1:
		if CloudSession.is_strict_release() or CloudSession.is_logged_in():
			return CloudSession.is_admin()
		return OS.is_debug_build()
	return NetworkManager.is_peer_admin(sender)


## Badge shown delicately in GameChat header ("ADM" online admin, "DEV" offline debug, "" otherwise).
static func mode_badge() -> String:
	if not can_use_local():
		return ""
	if CloudSession.is_admin():
		return "ADM"
	return "DEV"


static func canonical_command(raw_cmd: String) -> String:
	var low: String = raw_cmd.strip_edges().to_lower()
	for spec: Dictionary in COMMANDS:
		if String(spec["cmd"]) == low:
			return low
		var aliases: Array = spec["aliases"] as Array
		for al: Variant in aliases:
			if String(al) == low:
				return String(spec["cmd"])
	return ""


static func is_admin_command(raw_cmd: String) -> bool:
	return not canonical_command(raw_cmd).is_empty()


# ------------------------------------------------------------------ Contextual Autocomplete

static func autocomplete(trimmed: String, tree: SceneTree) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not can_use_local() or not trimmed.begins_with("/"):
		return out
	var parts: PackedStringArray = trimmed.split(" ", true)
	var raw_cmd: String = parts[0].to_lower()

	# 1. Command name completion
	if parts.size() == 1:
		for spec: Dictionary in COMMANDS:
			var c: String = String(spec["cmd"])
			if raw_cmd == "/" or (c.begins_with(raw_cmd) and c != raw_cmd):
				var no_arg: bool = c in ["/players", "/save"]
				out.append({
					"insert": c + ("" if no_arg else " "),
					"label": String(spec["usage"]),
					"desc": String(spec["desc"]),
					"kind": "admin",
				})
		return out

	# 2. Contextual 2nd-argument completion
	var canon: String = canonical_command(raw_cmd)
	if canon.is_empty():
		return out
	var arg_q: String = parts[1].strip_edges().to_lower() if parts.size() >= 2 else ""
	if parts.size() > 2:
		return out

	match canon:
		"/give":
			var items: Dictionary = DataRegistry.table("items")
			for item_id: Variant in items.keys():
				var iid: String = String(item_id)
				var def: Dictionary = items[item_id] as Dictionary
				var title: String = String(def.get("name", iid))
				if arg_q.is_empty() or iid.to_lower().begins_with(arg_q) or title.to_lower().contains(arg_q):
					out.append({"insert": raw_cmd + " " + iid + " ", "label": iid, "desc": title, "kind": "admin"})
		"/tp":
			if arg_q.is_empty() or "home".begins_with(arg_q):
				out.append({"insert": raw_cmd + " home", "label": "home", "desc": "Zuhause / Lager", "kind": "admin"})
			var atlas: Atlas = Atlas.shared()
			if atlas != null:
				for z: Atlas.Zone in atlas.zones_of(&"main"):
					var zid: String = String(z.id)
					if arg_q.is_empty() or zid.to_lower().begins_with(arg_q) or z.name.to_lower().contains(arg_q):
						out.append({"insert": raw_cmd + " " + zid, "label": zid, "desc": z.name, "kind": "admin"})
			_append_player_suggestions(out, raw_cmd, arg_q, false)
		"/bring", "/heal":
			if arg_q.is_empty() or "all".begins_with(arg_q):
				out.append({"insert": raw_cmd + " all", "label": "all", "desc": "Alle Spieler", "kind": "admin"})
			_append_player_suggestions(out, raw_cmd, arg_q, false)
		"/kick", "/kill":
			_append_player_suggestions(out, raw_cmd, arg_q, true)
		"/god", "/stamina":
			for opt: String in ["on", "off"]:
				if arg_q.is_empty() or opt.begins_with(arg_q):
					out.append({"insert": raw_cmd + " " + opt, "label": opt, "desc": "Ein" if opt == "on" else "Aus", "kind": "admin"})
			_append_player_suggestions(out, raw_cmd, arg_q, false)
		"/speed":
			for opt_pair: Array in [["1", "Normal"], ["1.5", "Schnell"], ["2.5", "Sehr schnell"], ["4", "Maximum"], ["reset", "Zurücksetzen"]]:
				var tok: String = String(opt_pair[0])
				if arg_q.is_empty() or tok.begins_with(arg_q):
					out.append({"insert": raw_cmd + " " + tok, "label": tok, "desc": String(opt_pair[1]), "kind": "admin"})
		"/time":
			for preset: Array in [["morgen", "06:00"], ["mittag", "12:00"], ["abend", "18:30"], ["nacht", "22:00"], ["mitternacht", "00:00"], ["+1h", "+1 Stunde"], ["lock", "Uhr anhalten"], ["unlock", "Uhr starten"]]:
				var tok: String = String(preset[0])
				if arg_q.is_empty() or tok.begins_with(arg_q):
					out.append({"insert": raw_cmd + " " + tok, "label": tok, "desc": String(preset[1]), "kind": "admin"})
		"/weather":
			if arg_q.is_empty() or "auto".begins_with(arg_q):
				out.append({"insert": raw_cmd + " auto", "label": "auto", "desc": "Automatisches Wetter", "kind": "admin"})
			var states: Dictionary = DataRegistry.table("weather").get("states", {}) as Dictionary
			for wid: Variant in states.keys():
				var ws: String = String(wid)
				var wname: String = WeatherRules.display_name(ws).capitalize()
				if arg_q.is_empty() or ws.to_lower().begins_with(arg_q) or wname.to_lower().contains(arg_q):
					out.append({"insert": raw_cmd + " " + ws, "label": ws, "desc": wname, "kind": "admin"})
		"/spawn":
			var enemies: Dictionary = DataRegistry.table("enemies")
			for eid: Variant in enemies.keys():
				var es: String = String(eid)
				var ename: String = String((enemies[eid] as Dictionary).get("name", es))
				if arg_q.is_empty() or es.to_lower().begins_with(arg_q) or ename.to_lower().contains(arg_q):
					out.append({"insert": raw_cmd + " " + es + " 1", "label": es, "desc": ename, "kind": "admin"})
		"/effect":
			if arg_q.is_empty() or "clear".begins_with(arg_q):
				out.append({"insert": raw_cmd + " clear", "label": "clear", "desc": "Alle Effekte entfernen", "kind": "admin"})
			var defs: Dictionary = DataRegistry.table("status_effects")
			for eff_id: Variant in defs.keys():
				var es: String = String(eff_id)
				var ename: String = String((defs[eff_id] as Dictionary).get("name", es))
				if arg_q.is_empty() or es.to_lower().begins_with(arg_q) or ename.to_lower().contains(arg_q):
					out.append({"insert": raw_cmd + " " + es + " 30", "label": es, "desc": ename, "kind": "admin"})
		"/map":
			for opt_pair: Array in [["reveal", "Ganze Karte aufdecken"], ["reset", "Nebel wiederherstellen"], ["atlas", "Kontinent & Welt umschalten"]]:
				var tok: String = String(opt_pair[0])
				if arg_q.is_empty() or tok.begins_with(arg_q):
					out.append({"insert": raw_cmd + " " + tok, "label": tok, "desc": String(opt_pair[1]), "kind": "admin"})
		"/joinmode":
			for opt_pair: Array in [["open", "Offen für alle"], ["ask", "Auf Anfrage"], ["private", "Privat / geschlossen"]]:
				var tok: String = String(opt_pair[0])
				if arg_q.is_empty() or tok.begins_with(arg_q):
					out.append({"insert": raw_cmd + " " + tok, "label": tok, "desc": String(opt_pair[1]), "kind": "admin"})
		"/admin":
			for cat_pair: Array in [["spieler", "Spieler & Cheats"], ["welt", "Welt, Zeit & Zonen"], ["multiplayer", "Koop & Moderation"]]:
				var tok: String = String(cat_pair[0])
				if arg_q.is_empty() or tok.begins_with(arg_q):
					out.append({"insert": raw_cmd + " " + tok, "label": tok, "desc": String(cat_pair[1]), "kind": "admin"})
	if tree == null:
		return out
	return out


static func _append_player_suggestions(out: Array[Dictionary], raw_cmd: String, arg_q: String, exclude_host: bool) -> void:
	for entry: Dictionary in NetworkManager.roster():
		if exclude_host and bool(entry.get("is_host", false)):
			continue
		var pname: String = String(entry.get("name", ""))
		if not pname.is_empty() and (arg_q.is_empty() or pname.to_lower().begins_with(arg_q)):
			out.append({"insert": raw_cmd + " " + pname, "label": pname, "desc": "Spieler #%d" % int(entry.get("id", 0)), "kind": "admin"})


# ------------------------------------------------------------------ Host Execution Engine

static func execute_on_server(sender: int, raw_line: String, tree: SceneTree) -> Dictionary:
	if not is_sender_authorized(sender):
		if CloudSession.is_logged_in() and sender > 1:
			CloudSession.report_security_event("ADMIN_CMD_DENIED", "Peer %d tried: %s" % [sender, raw_line.left(80)], "warn")
		return _err("Keine Berechtigung für Admin-Befehle.")

	var clean: String = raw_line.strip_escapes().strip_edges()
	if not clean.begins_with("/"):
		return _err("Ungültiger Befehl.")
	var tokens: PackedStringArray = clean.split(" ", false)
	if tokens.is_empty():
		return _err("Leerer Befehl.")

	var raw_cmd: String = tokens[0].to_lower()
	var canon: String = canonical_command(raw_cmd)
	var args: PackedStringArray = tokens.slice(1)
	var rest: String = clean.substr(tokens[0].length()).strip_edges()

	match canon:
		"/admin":
			return _cmd_admin_help(args)
		"/god":
			return _cmd_god(sender, args, tree)
		"/stamina":
			return _cmd_stamina(sender, args, tree)
		"/heal":
			return _cmd_heal(sender, args, tree)
		"/hp":
			return _cmd_hp(sender, args, tree)
		"/speed":
			return _cmd_speed(sender, args, tree)
		"/give":
			return _cmd_give(sender, args, tree)
		"/gold":
			return _cmd_gold(sender, raw_cmd, args, tree)
		"/xp":
			return _cmd_xp(sender, args, tree)
		"/level":
			return _cmd_level(sender, args, tree)
		"/effect":
			return _cmd_effect(sender, args, tree)
		"/kill":
			return _cmd_kill(sender, args, tree)
		"/butcher":
			return _cmd_butcher(sender, args, tree)
		"/tp":
			return _cmd_tp(sender, args, tree)
		"/bring":
			return _cmd_bring(sender, args, tree)
		"/time":
			return _cmd_time(args)
		"/day":
			return _cmd_day(args)
		"/weather":
			return _cmd_weather(args)
		"/spawn":
			return _cmd_spawn(sender, args, tree)
		"/map":
			return _cmd_map(sender, args, tree)
		"/save":
			return _cmd_save(tree)
		"/players":
			return _cmd_players(tree)
		"/kick":
			return _cmd_kick(sender, args)
		"/announce":
			return _cmd_announce(rest)
		"/joinmode":
			return _cmd_joinmode(args)
		"/roomcode":
			return _cmd_roomcode(args)
		_:
			return _err("Unbekannter Admin-Befehl: %s" % raw_cmd)


# ------------------------------------------------------------------ Helpers: Player & Target Resolution

static func _ok(msg: String) -> Dictionary:
	return {"ok": true, "lines": PackedStringArray([msg])}


static func _ok_lines(lines: PackedStringArray) -> Dictionary:
	return {"ok": true, "lines": lines}


static func _err(msg: String) -> Dictionary:
	return {"ok": false, "lines": PackedStringArray([msg])}


static func _find_player_by_peer(peer_id: int, tree: SceneTree) -> Player:
	for p: Player in Player.all:
		if is_instance_valid(p) and p.is_inside_tree():
			if p.name.to_int() == peer_id or p.get_multiplayer_authority() == peer_id:
				return p
	if tree != null:
		for n: Node in tree.get_nodes_in_group("players"):
			var p2: Player = n as Player
			if p2 != null and (p2.name.to_int() == peer_id or p2.get_multiplayer_authority() == peer_id):
				return p2
	if peer_id <= 1 and not Player.all.is_empty() and is_instance_valid(Player.all[0]):
		return Player.all[0]
	return null


static func _all_players(tree: SceneTree) -> Array[Player]:
	var out: Array[Player] = []
	for p: Player in Player.all:
		if is_instance_valid(p) and p.is_inside_tree() and not out.has(p):
			out.append(p)
	if out.is_empty() and tree != null:
		for n: Node in tree.get_nodes_in_group("players"):
			var p2: Player = n as Player
			if p2 != null and not out.has(p2):
				out.append(p2)
	return out


static func _resolve_peer_by_name(query: String) -> int:
	var q: String = query.strip_edges().to_lower()
	if q.is_empty():
		return -1
	if q.is_valid_int():
		var pid: int = q.to_int()
		for entry: Dictionary in NetworkManager.roster():
			if int(entry.get("id", 0)) == pid:
				return pid
		if pid == 1:
			return 1
	var exact: int = -1
	var prefix: int = -1
	for entry: Dictionary in NetworkManager.roster():
		var ename: String = String(entry.get("name", "")).to_lower()
		var eid: int = int(entry.get("id", 0))
		if ename == q:
			exact = eid
			break
		if prefix < 0 and ename.begins_with(q):
			prefix = eid
	if exact > 0:
		return exact
	if prefix > 0:
		return prefix
	# Offline singleplayer fallback: check local player name
	var local_n: String = String(GameSettings.get_value("player_name")).to_lower()
	if not local_n.is_empty() and (local_n == q or local_n.begins_with(q)):
		return 1
	return -1


static func _resolve_target_player(sender: int, query: String, tree: SceneTree) -> Player:
	if query.is_empty():
		return _find_player_by_peer(sender, tree)
	var peer: int = _resolve_peer_by_name(query)
	if peer < 0:
		return null
	return _find_player_by_peer(peer, tree)


static func _player_label(p: Player) -> String:
	var pid: int = p.name.to_int()
	if pid <= 0:
		pid = p.get_multiplayer_authority()
	return NetworkManager.player_name_for(pid)


static func _send_player_op(p: Player, op: String, arg: Variant) -> void:
	if p == null or not is_instance_valid(p):
		return
	var owner_peer: int = p.get_multiplayer_authority()
	if p.is_multiplayer_authority() or not NetworkManager.is_multiplayer_session() or owner_peer <= 1:
		p.apply_admin_local_op(op, arg)
	elif NetworkManager.rpc_ready(p):
		p.apply_admin_local_op.rpc_id(owner_peer, op, arg)


static func _parse_bool_toggle(tok: String, current: bool) -> Dictionary:
	var low: String = tok.to_lower()
	if low in ["on", "an", "1", "true", "ein"]:
		return {"matched": true, "value": true}
	if low in ["off", "aus", "0", "false"]:
		return {"matched": true, "value": false}
	return {"matched": false, "value": not current}


# ------------------------------------------------------------------ Category A: Player & Cheat Commands

static func _cmd_admin_help(args: PackedStringArray) -> Dictionary:
	var cat: String = args[0].to_lower() if not args.is_empty() else ""
	var out: PackedStringArray = PackedStringArray()
	if cat.is_empty():
		out.append("★ Admin-Befehle (Modus: %s):" % mode_badge())
		out.append("  Spieler: /god · /stamina · /heal · /hp · /speed · /give · /gold · /xp · /level · /effect · /kill · /butcher")
		out.append("  Welt:    /tp · /bring · /time · /day · /weather · /spawn · /map · /save")
		out.append("  Koop:    /players · /kick · /announce · /joinmode · /roomcode")
		out.append("  Details: /admin spieler | /admin welt | /admin multiplayer")
		return _ok_lines(out)
	var matched: bool = false
	for spec: Dictionary in COMMANDS:
		if String(spec["cat"]).begins_with(cat):
			out.append("  %s — %s" % [String(spec["usage"]), String(spec["desc"])])
			matched = true
	if not matched:
		return _err("Kategorie unbekannt. Nutze: /admin spieler | welt | multiplayer")
	return _ok_lines(out)


static func _cmd_god(sender: int, args: PackedStringArray, tree: SceneTree) -> Dictionary:
	var target_q: String = ""
	var explicit: Dictionary = {"matched": false, "value": false}
	if args.size() >= 1:
		explicit = _parse_bool_toggle(args[0], false)
		if bool(explicit["matched"]):
			target_q = args[1] if args.size() >= 2 else ""
		else:
			target_q = args[0]
			if args.size() >= 2:
				explicit = _parse_bool_toggle(args[1], false)
	var p: Player = _resolve_target_player(sender, target_q, tree)
	if p == null or p.health == null:
		return _err("Spieler nicht gefunden.")
	var next_val: bool = bool(explicit["value"]) if bool(explicit["matched"]) else not p.health.god_mode
	p.health.god_mode = next_val
	return _ok("Godmode für %s: %s." % [_player_label(p), "AN" if next_val else "AUS"])


static func _cmd_stamina(sender: int, args: PackedStringArray, tree: SceneTree) -> Dictionary:
	var target_q: String = ""
	var explicit: Dictionary = {"matched": false, "value": false}
	if args.size() >= 1:
		explicit = _parse_bool_toggle(args[0], false)
		if bool(explicit["matched"]):
			target_q = args[1] if args.size() >= 2 else ""
		else:
			target_q = args[0]
			if args.size() >= 2:
				explicit = _parse_bool_toggle(args[1], false)
	var p: Player = _resolve_target_player(sender, target_q, tree)
	if p == null or p.stamina == null:
		return _err("Spieler nicht gefunden.")
	var next_val: bool = bool(explicit["value"]) if bool(explicit["matched"]) else not p.stamina.infinite
	p.stamina.infinite = next_val
	_send_player_op(p, "stamina_infinite", next_val)
	return _ok("Unendliche Ausdauer für %s: %s." % [_player_label(p), "AN" if next_val else "AUS"])


static func _cmd_heal(sender: int, args: PackedStringArray, tree: SceneTree) -> Dictionary:
	var targets: Array[Player] = []
	if not args.is_empty() and args[0].to_lower() in ["all", "alle", "*"]:
		targets = _all_players(tree)
	else:
		var p: Player = _resolve_target_player(sender, args[0] if not args.is_empty() else "", tree)
		if p != null:
			targets.append(p)
	if targets.is_empty():
		return _err("Spieler nicht gefunden.")
	for tp: Player in targets:
		if tp.health != null:
			tp.health.heal_full()
		if tp.effects != null:
			for eff_id: String in tp.effects.active():
				tp.effects.clear(eff_id)
		_send_player_op(tp, "stamina_refill", true)
	if targets.size() > 1:
		return _ok("Alle %d Spieler vollständig geheilt." % targets.size())
	return _ok("%s vollständig geheilt & Ausdauer aufgefüllt." % _player_label(targets[0]))


static func _cmd_hp(sender: int, args: PackedStringArray, tree: SceneTree) -> Dictionary:
	if args.is_empty() or not args[0].is_valid_float():
		return _err("Verwendung: /hp <Wert> [Spieler]")
	var val: float = float(args[0])
	var p: Player = _resolve_target_player(sender, args[1] if args.size() >= 2 else "", tree)
	if p == null or p.health == null:
		return _err("Spieler nicht gefunden.")
	p.health.set_health(val)
	return _ok("Leben von %s auf %d gesetzt." % [_player_label(p), roundi(p.health.current)])


static func _cmd_speed(sender: int, args: PackedStringArray, tree: SceneTree) -> Dictionary:
	if args.is_empty():
		return _err("Verwendung: /speed <0.25-4|reset> [Spieler]")
	var mult: float = 1.0
	if args[0].to_lower() in ["reset", "normal", "default"]:
		mult = 1.0
	elif args[0].is_valid_float():
		mult = clampf(float(args[0]), 0.25, 4.0)
	else:
		return _err("Ungültiger Faktor (0.25 bis 4.0 oder reset).")
	var p: Player = _resolve_target_player(sender, args[1] if args.size() >= 2 else "", tree)
	if p == null:
		return _err("Spieler nicht gefunden.")
	p.admin_speed_scale = mult
	_send_player_op(p, "speed", mult)
	return _ok("Tempo für %s auf %.2f× gesetzt." % [_player_label(p), mult])


static func _cmd_give(sender: int, args: PackedStringArray, tree: SceneTree) -> Dictionary:
	if args.is_empty():
		return _err("Verwendung: /give <item_id> [Menge|max] [Spieler]")
	var query: String = args[0].strip_edges().to_lower()
	var items: Dictionary = DataRegistry.table("items")
	var found_id: String = ""
	if items.has(query):
		found_id = query
	else:
		for key: Variant in items.keys():
			var ks: String = String(key)
			var title: String = String((items[key] as Dictionary).get("name", ks)).to_lower()
			if ks.to_lower() == query or title == query:
				found_id = ks
				break
			if found_id.is_empty() and (ks.to_lower().begins_with(query) or title.begins_with(query)):
				found_id = ks
	if found_id.is_empty():
		return _err("Item '%s' nicht gefunden." % args[0])

	var stack_info: Dictionary = {"id": found_id, "count": 1}
	var max_st: int = maxi(1, Items.max_stack(stack_info))
	var count: int = 1
	var target_q: String = ""
	if args.size() >= 2:
		if args[1].to_lower() == "max":
			count = max_st
			target_q = args[2] if args.size() >= 3 else ""
		elif args[1].is_valid_int():
			count = clampi(args[1].to_int(), 1, 999)
			target_q = args[2] if args.size() >= 3 else ""
		else:
			target_q = args[1]
	var p: Player = _resolve_target_player(sender, target_q, tree)
	if p == null or p.inventory == null:
		return _err("Spieler oder Inventar nicht gefunden.")
	var given: int = p.inventory.give(found_id, count)
	var overflow: int = count - given
	if overflow > 0 and tree != null and tree.get_first_node_in_group("drops") != null:
		DropComponent.spawn_thrown(tree, found_id, overflow, p.global_position, p.facing)
	var title_str: String = Items.title(stack_info)
	if overflow > 0:
		return _ok("%d× %s an %s (%d im Beutel, %d gedroppt)." % [count, title_str, _player_label(p), given, overflow])
	return _ok("%d× %s an %s verliehen." % [count, title_str, _player_label(p)])


static func _cmd_gold(sender: int, raw_cmd: String, args: PackedStringArray, tree: SceneTree) -> Dictionary:
	if args.is_empty() or not args[0].is_valid_int():
		return _err("Verwendung: %s <Menge> [Spieler]" % raw_cmd)
	var amount: int = clampi(args[0].to_int(), 1, 99999)
	var is_copper: bool = raw_cmd in ["/copper", "/kupfer"]
	var copper_total: int = amount if is_copper else amount * Currency.GOLD
	var p: Player = _resolve_target_player(sender, args[1] if args.size() >= 2 else "", tree)
	if p == null or p.progress == null:
		return _err("Spieler nicht gefunden.")
	p.progress.award(copper_total, 0)
	return _ok("+%d %s an %s verliehen." % [amount, "Kupfer" if is_copper else "Gold", _player_label(p)])


static func _cmd_xp(sender: int, args: PackedStringArray, tree: SceneTree) -> Dictionary:
	if args.is_empty() or not args[0].is_valid_int():
		return _err("Verwendung: /xp <Menge> [Spieler]")
	var amount: int = clampi(args[0].to_int(), 1, 1000000)
	var p: Player = _resolve_target_player(sender, args[1] if args.size() >= 2 else "", tree)
	if p == null or p.progress == null:
		return _err("Spieler nicht gefunden.")
	p.progress.award(0, amount)
	return _ok("+%d XP an %s verliehen (Stufe %d)." % [amount, _player_label(p), p.progress.level])


static func _cmd_level(sender: int, args: PackedStringArray, tree: SceneTree) -> Dictionary:
	if args.is_empty() or not args[0].is_valid_int():
		return _err("Verwendung: /level <Stufe> [Spieler]")
	var target_lvl: int = clampi(args[0].to_int(), 1, Levels.max_level())
	var p: Player = _resolve_target_player(sender, args[1] if args.size() >= 2 else "", tree)
	if p == null or p.progress == null:
		return _err("Spieler nicht gefunden.")
	var needed: int = Levels.xp_at(target_lvl) - p.progress.xp
	if needed <= 0:
		return _ok("%s ist bereits mindestens Stufe %d." % [_player_label(p), p.progress.level])
	p.progress.award(0, needed)
	return _ok("%s auf Stufe %d angehoben." % [_player_label(p), p.progress.level])


static func _cmd_effect(sender: int, args: PackedStringArray, tree: SceneTree) -> Dictionary:
	if args.is_empty():
		return _err("Verwendung: /effect <effekt_id|clear> [Sekunden] [Spieler]")
	var eff: String = args[0].to_lower()
	if eff == "clear":
		var p_clr: Player = _resolve_target_player(sender, args[1] if args.size() >= 2 else "", tree)
		if p_clr == null or p_clr.effects == null:
			return _err("Spieler nicht gefunden.")
		for eid: String in p_clr.effects.active():
			p_clr.effects.clear(eid)
		return _ok("Alle Statuseffekte von %s entfernt." % _player_label(p_clr))
	if StatusEffects.definition(eff).is_empty():
		return _err("Statuseffekt '%s' unbekannt." % eff)
	var sec: float = 0.0
	var target_q: String = ""
	if args.size() >= 2:
		if args[1].is_valid_float():
			sec = clampf(float(args[1]), 1.0, 600.0)
			target_q = args[2] if args.size() >= 3 else ""
		else:
			target_q = args[1]
	var p: Player = _resolve_target_player(sender, target_q, tree)
	if p == null or p.effects == null:
		return _err("Spieler nicht gefunden.")
	p.effects.apply(eff, sec)
	return _ok("Effekt '%s' auf %s angewendet." % [eff, _player_label(p)])


static func _cmd_kill(sender: int, args: PackedStringArray, tree: SceneTree) -> Dictionary:
	var p: Player = _resolve_target_player(sender, args[0] if not args.is_empty() else "", tree)
	if p == null or p.health == null:
		return _err("Spieler nicht gefunden.")
	if p.health.god_mode:
		return _err("%s hat Godmode aktiv." % _player_label(p))
	p.health.kill(p.global_position, sender)
	return _ok("%s wurde besiegt." % _player_label(p))


static func _cmd_butcher(sender: int, args: PackedStringArray, tree: SceneTree) -> Dictionary:
	if tree == null:
		return _err("Keine aktive Welt.")
	var all_mode: bool = not args.is_empty() and args[0].to_lower() in ["all", "alle", "*"]
	var radius: float = 480.0
	if not all_mode and not args.is_empty() and args[0].is_valid_float():
		radius = clampf(float(args[0]), 32.0, 10000.0)
	var origin: Vector2 = Vector2.ZERO
	var admin_p: Player = _find_player_by_peer(sender, tree)
	if admin_p != null:
		origin = admin_p.global_position
	var removed: int = 0
	for node: Node in tree.get_nodes_in_group("predators"):
		if not (node is Node2D) or not is_instance_valid(node):
			continue
		if node is Player:
			continue
		var n2: Node2D = node as Node2D
		if not all_mode and admin_p != null and n2.global_position.distance_to(origin) > radius:
			continue
		var hp: HealthComponent = node.get_node_or_null("HealthComponent") as HealthComponent
		if hp != null and hp.current > 0.0:
			hp.kill(origin, sender)
		else:
			node.queue_free()
		removed += 1
	return _ok("%d Gegner entfernt." % removed)


# ------------------------------------------------------------------ Category B: World, Zones & Exploration Commands

static func _zone_target_pos(query: String) -> Dictionary:
	var atlas: Atlas = Atlas.shared()
	if atlas == null:
		return {}
	var q: String = query.strip_edges().to_lower()
	var best: Atlas.Zone = null
	for z: Atlas.Zone in atlas.zones_of(&"main"):
		if String(z.id).to_lower() == q or z.name.to_lower() == q:
			best = z
			break
		if best == null and (String(z.id).to_lower().begins_with(q) or z.name.to_lower().begins_with(q)):
			best = z
	if best == null:
		return {}
	var tile: Vector2 = best.center()
	for lm: Atlas.Landmark in best.landmarks:
		if lm.kind in [&"waystone", &"camp", &"settlement"]:
			tile = lm.pos
			break
	return {"name": best.name, "pos": tile * Atlas.TILE_PX + Vector2(8.0, 8.0)}


static func _cmd_tp(sender: int, args: PackedStringArray, tree: SceneTree) -> Dictionary:
	if args.is_empty():
		return _err("Verwendung: /tp <Zone|Spieler|home|x y>")
	var mover: Player = _find_player_by_peer(sender, tree)
	if mover == null:
		return _err("Kein aktiver Spieler in der Welt.")

	# Case 1: /tp <x> <y>
	if args.size() == 2 and args[0].is_valid_int() and args[1].is_valid_int():
		var dest: Vector2 = Vector2(float(args[0].to_int()) * 16.0 + 8.0, float(args[1].to_int()) * 16.0 + 8.0)
		_send_player_op(mover, "teleport", dest)
		return _ok("%s zu Kachel (%d, %d) teleportiert." % [_player_label(mover), args[0].to_int(), args[1].to_int()])

	# Case 2: /tp <SpielerA> <x> <y>
	if args.size() == 3 and args[1].is_valid_int() and args[2].is_valid_int():
		var subject: Player = _resolve_target_player(sender, args[0], tree)
		if subject == null:
			return _err("Spieler '%s' nicht gefunden." % args[0])
		var dest3: Vector2 = Vector2(float(args[1].to_int()) * 16.0 + 8.0, float(args[2].to_int()) * 16.0 + 8.0)
		_send_player_op(subject, "teleport", dest3)
		return _ok("%s zu Kachel (%d, %d) teleportiert." % [_player_label(subject), args[1].to_int(), args[2].to_int()])

	# Case 3: /tp <SpielerA> <Zone|SpielerB|home>
	var dest_arg: String = args[0]
	if args.size() >= 2:
		var subject2: Player = _resolve_target_player(sender, args[0], tree)
		if subject2 != null:
			mover = subject2
			dest_arg = args[1]

	if dest_arg.to_lower() in ["home", "zuhause", "lager", "spawn"]:
		var world: Node = tree.get_first_node_in_group("world") if tree != null else null
		var home_pos: Vector2 = Vector2.ZERO
		if world != null and world.has_method("spawn_point"):
			home_pos = world.call("spawn_point") as Vector2
		_send_player_op(mover, "teleport", home_pos)
		return _ok("%s zum Ausgangspunkt teleportiert." % _player_label(mover))

	var zone_hit: Dictionary = _zone_target_pos(dest_arg)
	if not zone_hit.is_empty():
		_send_player_op(mover, "teleport", zone_hit["pos"] as Vector2)
		return _ok("%s in Zone %s teleportiert." % [_player_label(mover), String(zone_hit["name"])])

	var target_p: Player = _resolve_target_player(sender, dest_arg, tree)
	if target_p != null:
		_send_player_op(mover, "teleport", target_p.global_position + Vector2(18.0, 0.0))
		return _ok("%s zu %s teleportiert." % [_player_label(mover), _player_label(target_p)])

	return _err("Ziel '%s' (Zone, Spieler oder x y) nicht gefunden." % dest_arg)


static func _cmd_bring(sender: int, args: PackedStringArray, tree: SceneTree) -> Dictionary:
	if args.is_empty():
		return _err("Verwendung: /bring <Spieler|all>")
	var host_p: Player = _find_player_by_peer(sender, tree)
	if host_p == null:
		return _err("Eigener Spieler nicht gefunden.")
	var targets: Array[Player] = []
	if args[0].to_lower() in ["all", "alle", "*"]:
		for p: Player in _all_players(tree):
			if p != host_p:
				targets.append(p)
	else:
		var tp: Player = _resolve_target_player(sender, args[0], tree)
		if tp != null and tp != host_p:
			targets.append(tp)
	if targets.is_empty():
		return _err("Kein anderer Spieler zum Herholen gefunden.")
	for i: int in targets.size():
		var ang: float = float(i) * TAU / float(maxi(targets.size(), 1))
		_send_player_op(targets[i], "teleport", host_p.global_position + Vector2.from_angle(ang) * 24.0)
	return _ok("%d Spieler zu %s geholt." % [targets.size(), _player_label(host_p)])


static func _cmd_time(args: PackedStringArray) -> Dictionary:
	if args.is_empty():
		return _ok("Aktuelle Uhrzeit: %s (Tag %d, %s)." % [TimeManager.clock_text(), TimeManager.day + 1, "gesperrt" if TimeManager.locked else "läuft"])
	var tok: String = args[0].to_lower()
	if tok in ["lock", "stop", "pause", "anhalten"]:
		TimeManager.set_clock_locked(true)
		return _ok("Tageszeit angehalten (%s)." % TimeManager.clock_text())
	if tok in ["unlock", "resume", "start", "weiter"]:
		TimeManager.set_clock_locked(false)
		return _ok("Tageszeit läuft wieder (%s)." % TimeManager.clock_text())
	if tok.begins_with("+") and tok.ends_with("h"):
		var hrs_str: String = tok.trim_prefix("+").trim_suffix("h")
		if hrs_str.is_valid_float():
			TimeManager.set_time(fposmod(TimeManager.time_of_day + float(hrs_str) / 24.0, 1.0))
			return _ok("Uhrzeit vorgestellt auf %s." % TimeManager.clock_text())
	if TIME_PRESETS.has(tok):
		TimeManager.set_time(float(TIME_PRESETS[tok]))
		return _ok("Uhrzeit auf %s gesetzt." % TimeManager.clock_text())
	if tok.contains(":"):
		var hm: PackedStringArray = tok.split(":", false)
		if hm.size() == 2 and hm[0].is_valid_int() and hm[1].is_valid_int():
			var hh: int = clampi(hm[0].to_int(), 0, 23)
			var mm: int = clampi(hm[1].to_int(), 0, 59)
			TimeManager.set_time((float(hh) + float(mm) / 60.0) / 24.0)
			return _ok("Uhrzeit auf %s gesetzt." % TimeManager.clock_text())
	if tok.is_valid_int():
		var h_only: int = clampi(tok.to_int(), 0, 23)
		TimeManager.set_time(float(h_only) / 24.0)
		return _ok("Uhrzeit auf %s gesetzt." % TimeManager.clock_text())
	return _err("Ungültige Zeit. Beispiel: /time nacht, /time 14:30, /time +1h, /time lock")


static func _cmd_day(args: PackedStringArray) -> Dictionary:
	if args.is_empty():
		return _ok("Aktueller Spieltag: Tag %d." % (TimeManager.day + 1))
	var tok: String = args[0]
	var target: int = TimeManager.day
	if tok.begins_with("+") and tok.substr(1).is_valid_int():
		target = TimeManager.day + maxi(tok.substr(1).to_int(), 1)
	elif tok.is_valid_int():
		target = maxi(tok.to_int() - 1, 0)
	else:
		return _err("Verwendung: /day <Tagnummer|+1>")
	TimeManager.set_day_number(target)
	return _ok("Spieltag auf Tag %d gesetzt." % (TimeManager.day + 1))


static func _cmd_weather(args: PackedStringArray) -> Dictionary:
	var weather: WeatherManager = WeatherManager.current
	if weather == null:
		return _err("Kein Wettersystem in dieser Szene aktiv.")
	if args.is_empty():
		return _ok("Wetter: %s." % (weather.override_id if not weather.override_id.is_empty() else "automatisch"))
	var wid: String = args[0].to_lower()
	if wid in ["auto", "reset", "clear_override"]:
		weather.release()
		return _ok("Wetter läuft wieder automatisch.")
	var states: Dictionary = DataRegistry.table("weather").get("states", {}) as Dictionary
	if not states.has(wid):
		return _err("Unbekanntes Wetter '%s'. Nutze TAB für Vorschläge oder 'auto'." % wid)
	weather.force(wid)
	return _ok("Wetter auf %s gesetzt." % WeatherRules.display_name(wid).capitalize())


static func _cmd_spawn(sender: int, args: PackedStringArray, tree: SceneTree) -> Dictionary:
	if args.is_empty():
		return _err("Verwendung: /spawn <gegner_id> [Anzahl 1-10]")
	var world: Node = tree.get_first_node_in_group("world") if tree != null else null
	if world == null or not world.has_method("spawn_species"):
		return _err("In dieser Szene können keine Gegner gespawnt werden.")
	var eid: String = args[0].to_lower()
	var enemies: Dictionary = DataRegistry.table("enemies")
	if not enemies.has(eid) and not KNOWN_ENEMIES.has(eid):
		return _err("Unbekannter Gegner '%s'." % eid)
	var count: int = clampi(args[1].to_int(), 1, 10) if args.size() >= 2 and args[1].is_valid_int() else 1
	var p: Player = _find_player_by_peer(sender, tree)
	var base_pos: Vector2 = p.global_position if p != null else Vector2.ZERO
	var spawned: int = 0
	for i: int in count:
		var ang: float = float(i) * TAU / float(count)
		var pos: Vector2 = base_pos + Vector2.from_angle(ang) * randf_range(56.0, 92.0)
		var res: Variant = world.call("spawn_species", eid, pos, randf() * TAU, 1.0, 1.0, true)
		if res != null:
			spawned += 1
	return _ok("%d× %s beschworen." % [spawned, eid])


static func _cmd_map(sender: int, args: PackedStringArray, tree: SceneTree) -> Dictionary:
	var fog: MapDiscovery = tree.get_first_node_in_group("map_discovery") as MapDiscovery if tree != null else null
	if fog == null:
		return _err("Keine Weltkarte aktiv.")
	var sub: String = args[0].to_lower() if not args.is_empty() else "reveal"
	match sub:
		"reveal", "all", "on":
			fog.reveal_all()
			return _ok("Ganze Karte aufgedeckt.")
		"reset", "fog", "off":
			fog.reset_reveal()
			return _ok("Kartennebel wiederhergestellt.")
		"atlas", "continent", "world":
			var next_u: bool = not fog.is_continent_unlocked()
			fog.set_continent_unlocked(next_u)
			var p: Player = _find_player_by_peer(sender, tree)
			if p != null and p.quests != null:
				if next_u:
					p.quests.set_flag("atlas_continent_unlocked")
				else:
					p.quests.flags.erase("atlas_continent_unlocked")
					p.quests.changed.emit()
			var mw: MapWindow = tree.get_first_node_in_group("map_window") as MapWindow
			if mw != null and mw.has_method("set_continent_unlocked_instant"):
				mw.call("set_continent_unlocked_instant", next_u)
			return _ok("Atlas Kontinent & Welt: %s." % ("FREIGESCHALTET" if next_u else "VERRIEGELT"))
		_:
			return _err("Verwendung: /map reveal | reset | atlas")


static func _cmd_save(tree: SceneTree) -> Dictionary:
	var ok: bool = false
	if CloudSession.is_logged_in() and CloudSession.has_method("save_now"):
		CloudSession.call("save_now")
		ok = true
	elif tree != null and SaveGame.save(tree):
		ok = true
	return _ok("Welt erfolgreich gespeichert.") if ok else _err("Speichern in dieser Szene nicht möglich.")


# ------------------------------------------------------------------ Category C: Multiplayer & Moderation Commands

static func _cmd_players(tree: SceneTree) -> Dictionary:
	var crew: Array[Dictionary] = NetworkManager.roster()
	var lines: PackedStringArray = PackedStringArray()
	if crew.is_empty():
		var solo_p: Player = _find_player_by_peer(1, tree)
		var hp_str: String = "%d/%d HP" % [roundi(solo_p.health.current), roundi(solo_p.health.max_health)] if solo_p != null and solo_p.health != null else "—"
		lines.append("★ 1 Spieler (Lokal): %s · %s [%s]" % [NetworkManager.player_name_for(1), hp_str, mode_badge()])
		return _ok_lines(lines)
	lines.append("★ Aktive Spieler (%d/%d):" % [crew.size(), NetworkManager.active_max_players])
	var world: Node = tree.get_first_node_in_group("world") if tree != null else null
	var director: ZoneDirector = world.call("director") as ZoneDirector if world != null and world.has_method("director") else null
	for entry: Dictionary in crew:
		var pid: int = int(entry.get("id", 0))
		var pname: String = String(entry.get("name", "Spieler"))
		var role_tag: String = "[ADMIN]" if NetworkManager.is_peer_admin(pid) else ("[HOST]" if bool(entry.get("is_host", false)) else "")
		var p: Player = _find_player_by_peer(pid, tree)
		var hp_s: String = "%d/%d" % [roundi(p.health.current), roundi(p.health.max_health)] if p != null and p.health != null else "?"
		var z_s: String = ""
		if director != null:
			var zid: StringName = director.effective_player_zone(pid)
			if zid != &"" and director.atlas != null and director.atlas.zone(zid) != null:
				z_s = " · " + director.atlas.zone(zid).name
		lines.append("  #%d %s %s · HP %s%s" % [pid, pname, role_tag, hp_s, z_s])
	return _ok_lines(lines)


static func _cmd_kick(sender: int, args: PackedStringArray) -> Dictionary:
	if args.is_empty():
		return _err("Verwendung: /kick <Spieler> [Grund]")
	if not NetworkManager.is_multiplayer_session():
		return _err("Keine aktive Koop-Sitzung.")
	var peer: int = _resolve_peer_by_name(args[0])
	if peer < 0:
		return _err("Spieler '%s' nicht in der Gruppe." % args[0])
	if peer <= 1:
		return _err("Der Host kann nicht entfernt werden.")
	if peer == sender:
		return _err("Du kannst dich nicht selbst entfernen.")
	var pname: String = NetworkManager.player_name_for(peer)
	var reason: String = " ".join(args.slice(1)).strip_edges() if args.size() > 1 else ""
	NetworkManager.kick_peer(peer)
	var msg: String = "%s wurde aus der Sitzung entfernt%s." % [pname, (" (%s)" % reason) if not reason.is_empty() else ""]
	Chat.broadcast_system("info", msg)
	return _ok(msg)


static func _cmd_announce(rest: String) -> Dictionary:
	if rest.is_empty():
		return _err("Verwendung: /announce <Nachricht>")
	Chat.broadcast_system("announce", rest)
	return _ok("Ankündigung an alle gesendet.")


static func _cmd_joinmode(args: PackedStringArray) -> Dictionary:
	if args.is_empty():
		var cur: String = NetworkManager.active_join_mode if NetworkManager.is_multiplayer_session() else CloudSession.world_join_mode
		return _ok("Beitrittsmodus: %s." % cur)
	var mode: String = args[0].to_lower()
	if not mode in ["open", "ask", "private"]:
		return _err("Ungültiger Modus. Nutze: open, ask oder private.")
	NetworkManager.set_active_join_mode(mode)
	if CloudSession.is_logged_in():
		CloudSession.set_world_join_mode(mode)
	return _ok("Beitrittsmodus auf '%s' gesetzt." % mode)


static func _cmd_roomcode(args: PackedStringArray) -> Dictionary:
	if not NetworkManager.is_multiplayer_session():
		return _err("Keine aktive Koop-Sitzung.")
	if args.is_empty():
		var cur: String = NetworkManager.active_room_code
		if not cur.is_empty():
			DisplayServer.clipboard_set(cur)
			return _ok("Raumcode: %s (kopiert)." % cur)
		return _ok("Kein Raumcode gesetzt.")
	var raw_c: String = "" if args[0].to_lower() in ["new", "neu", "random"] else args[0]
	var next_c: String = NetworkManager.set_room_code(raw_c)
	DisplayServer.clipboard_set(next_c)
	return _ok("Neuer Raumcode: %s (kopiert)." % next_c)
