class_name OpeningGuide
extends Node
## Owner-local narrative/tutorial; actual combo stages are confirmed by the host.
var _player: Player
var _dialogue: DialogueBox
var _knight_dialogue: bool = false

func _ready() -> void:
	_player = get_parent() as Player
	_dialogue = _player._hud.get_node("DialogueBox") as DialogueBox
	_dialogue.finished.connect(_dialogue_finished)
	_player.attack.combo_stage.connect(_combo_stage)

func _process(_delta: float) -> void:
	var quests: QuestComponent = _player.quests
	if quests.has_flag("knight_inspected") and not quests.has_flag("knight_dialogue_done") and not _knight_dialogue and not _dialogue.is_active() and not InputManager.ui_blocking:
		_knight_dialogue = true
		_dialogue.start("knight_sword")
	if quests.has_flag("knight_sword_taken") and String(_player.inventory.equipment.get("main_hand", {}).get("id", "")) == "sword_basic" and not quests.has_flag("knight_sword_equipped"):
		quests.set_flag("knight_sword_equipped")
	if quests.tutorial_combo > 0 and _player.attack.can_attack() and Time.get_ticks_msec() > _player.attack._combo_deadline_msec:
		quests.tutorial_combo = 0
	if _player.attack.held_weapon != "sword_basic": quests.tutorial_combo = 0

func _dialogue_finished() -> void:
	if _knight_dialogue:
		_knight_dialogue = false
		_player.quests.set_flag("knight_dialogue_done")

func _combo_stage(weapon: String, stage: int) -> void:
	var quests: QuestComponent = _player.quests
	if weapon != "sword_basic" or String(quests.current().get("hint", "")) != "combo": return
	if stage == 0: quests.tutorial_combo = 1
	elif stage == quests.tutorial_combo: quests.tutorial_combo += 1
	else: quests.tutorial_combo = 0
	if quests.tutorial_combo == 3: quests.set_flag("sword_combo_done")
