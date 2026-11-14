class_name Player
extends CharacterBody2D
## Owned by the peer whose id is the node name. The owner simulates movement
## and the MultiplayerSynchronizer pushes position, velocity and facing to everyone else.
## Looks toward the mouse cursor when in combat or aiming, otherwise toward the walking direction.

signal wounded_changed(on: bool)
signal bandaged_changed(on: bool)

static var all: Array[Player] = []

const RESPAWN_FALLBACK_SECONDS: float = 90.0 ## a fallen player who never chooses comes back after this long
const SPAWN_POINT: Vector2 = Vector2.ZERO
const HUD_SCENE: PackedScene = preload("res://src/ui/hud.tscn")
const RUN_DUST_MIN_SPEED: float = 40.0 ## px/s
const BODY_CENTER: Vector2 = Vector2(0, -24) ## aim origin, relative to the feet
## Facing sector 0 = east, counting clockwise (screen y points down): E SE S SW W NW N NE.
## Sheet (assets/characters/player.png): one row per sector, rows 8-15 are the crouched copies.
## Columns 0-5 are the walk cycle, 6-11 the sprint cycle (contacts at 0 and 3 of each), 12-15 the idle loop, 16-21 the jog cycle
## (crouched rows: the sneak again). Which cycle plays follows the real speed (`_pick_gait`), so a throttled sprint jogs.
## The sword combo has its own sheet (player_attack.png): one row per sector; per attack (forehand, backhand,
## thrust) 7 leg variants (0 = planted stance, 1-6 = the walk cycle's phases) x 6 keyframes.
const WALK_FRAMES: int = 6
const RUN_COL: int = 6
const IDLE_COL: int = 12
const JOG_COL: int = 16
const GAIT_SETTLE: float = 0.22 ## seconds a stopping stride may take to bring the feet under her before the idle loop
const IDLE_FRAMES: int = 4
const ATTACK_SHEET: Texture2D = preload("res://assets/characters/player_attack.png")
const ATTACK_FRAMES: int = 6
const ATTACK_LEGS: int = 7
const ATTACK_COLS: int = 3 * ATTACK_LEGS * ATTACK_FRAMES
const COMBO_SHEET: Texture2D = preload("res://assets/characters/player_combo.png") ## tools/art_hero_combo.py: the learned 4th and 5th strike (skill upgrades), per sector 2 blocks x 7 leg variants x 6 keys
const COMBO_BLOOD: Texture2D = preload("res://assets/characters/player_combo_blood.png")
const COMBO_COLS: int = 2 * ATTACK_LEGS * ATTACK_FRAMES
const HEAVY_SHEET: Texture2D = preload("res://assets/characters/player_heavy.png") ## tools/art_hero_heavy.py: the sword's heavy blow (charge, chop, recover)
const HEAVY_BLOOD: Texture2D = preload("res://assets/characters/player_heavy_blood.png")
const HEAVY_KEYS: int = 10
const HEAVY_COLS: int = HEAVY_KEYS * ATTACK_LEGS ## per sector row: 7 leg variants x 10 keys
const PICK_SHEET: Texture2D = preload("res://assets/characters/player_pick.png")
const EAT_SHEET: Texture2D = preload("res://assets/characters/player_eat.png")
const TOUCH_SHEET: Texture2D = preload("res://assets/characters/player_touch.png") ## tools/art_hero3d.py touchonly: both palms on a waystone statue
const PULL_SHEET: Texture2D = preload("res://assets/characters/player_pull.png") ## tools/art_hero3d.py pullonly: she heaves a root out of the ground
const FISH_SHEET: Texture2D = preload("res://assets/characters/player_fish.png") ## tools/art_hero_fish.py: the rod's body clips (cast, strike, fight, land, snap, sag)
const FISH_BLOOD: Texture2D = preload("res://assets/characters/player_fish_blood.png")
const SWIM_SHEET: Texture2D = preload("res://assets/characters/player_swim.png") ## tools/art_hero_swim.py: above-water layer (64x72 frames, water line at row 46)
const SWIM_UNDER: Texture2D = preload("res://assets/characters/player_swim_under.png") ## the same frames, only what is below the water line (drawn behind, tinted)
const SWIM_OFFSET: Vector2 = Vector2(0.0, -10.0)
const CLIMB_OFFSET: Vector2 = Vector2(0.0, -29.0) ## 68 px frames with the foot anchor on row 63
const CLIMB_SHEET: int = 15
const SWIM_LEVELS: Array[String] = ["tread", "breast", "crawl"]
const SWIM_SOUNDS: Dictionary = { ## tools/audio_swim.py
	"dive_big": preload("res://assets/audio/steps/swim_dive_1.mp3"), "dive_small": preload("res://assets/audio/swim/dive_small.wav"),
	"stroke_a": preload("res://assets/audio/steps/swim_stroke_1.mp3"), "stroke_b": preload("res://assets/audio/steps/swim_stroke_2.mp3"),
	"kick": preload("res://assets/audio/swim/kick.wav"), "breath": preload("res://assets/audio/swim/breath.wav"),
	"bubble": preload("res://assets/audio/swim/bubble.wav"), "exit": preload("res://assets/audio/swim/exit.wav"),
	"drip": preload("res://assets/audio/swim/drip.wav"), "shake": preload("res://assets/audio/swim/shake.wav"),
}
const STANDBY_SHEET: Texture2D = preload("res://assets/characters/player_standby.png")
const STANDBY_BLOOD: Texture2D = preload("res://assets/characters/player_standby_blood.png")
const STANDBY_FRAMES: int = 24
const STANDBY_CLIPS: int = 4
const NORMAL_STANDBY_CLIPS: int = 3
const HEAT_STANDBY_CLIP: int = 3
const STANDBY_FPS: float = 12.0
const STANDBY_COLS: int = STANDBY_FRAMES * STANDBY_CLIPS
const BLOOD_MAPS: Array[Texture2D] = [ ## the baked blood thresholds of each sheet (main, sword, pick, eat), see hit_flash.gdshader
	preload("res://assets/characters/player_blood.png"), preload("res://assets/characters/player_attack_blood.png"),
	preload("res://assets/characters/player_pick_blood.png"), preload("res://assets/characters/player_eat_blood.png"),
	preload("res://assets/characters/player_pull_blood.png"), preload("res://assets/characters/player_touch_blood.png")]
const EMERGE_BLOOD: Texture2D = preload("res://assets/characters/player_emerge_blood.png")
const FAINT_SHEET: Texture2D = preload("res://assets/characters/player_faint.png") ## tools/art_hero_faint.py: she collapses (side view, facing east)
const SIT_SHEET: Texture2D = preload("res://assets/characters/player_sit.png") ## tools/art_hero_sit.py: she sits down by the fire
const SIT_BLOOD: Texture2D = preload("res://assets/characters/player_sit_blood.png")
const WARDROBE_SHEET: Texture2D = preload("res://assets/characters/player_wardrobe.png") ## tools/art_hero_wardrobe.py: she shuts her wardrobe (north view), the opening of her room
const CARRY_STONE_SHEET: Texture2D = preload("res://assets/characters/player_carry_stone.png") ## tools/art_hero_carry_stone.py: she carries a moonstone (8 facings: lift 0-7, walk 8-15)
const CARRY_STONE_ID: int = 41 ## `_sheet` while she carries a stone
const CARRY_SPEED: float = 0.62 ## of her walking speed while she carries a stone
const CARRY_LIFT_FPS: float = 12.0
const CARRY_WALK_FPS: float = 10.0
const CARRY_SHEET: Texture2D = preload("res://assets/characters/player_carry.png") ## tools/art_hero_carry.py: she carries a board (side view, facing east)
const FAINT_BLOOD: Texture2D = preload("res://assets/characters/player_faint_blood.png")
const STUMBLE_SHEET: Texture2D = preload("res://assets/characters/player_stumble.png") ## tools/art_hero_stumble.py: 8 views, she trips and gets up
const STUMBLE_BLOOD: Texture2D = preload("res://assets/characters/player_stumble_blood.png")
const STUMBLE_SOUNDS: Dictionary = {
	"gasp": preload("res://assets/audio/intro/gasp.wav"),
	"thud": preload("res://assets/audio/intro/body_thud.wav"),
	"cough": preload("res://assets/audio/intro/cough.wav"),
}
const EAT_VARIANTS: int = 7 ## the eat sheet repeats every frame per leg variant (0 planted, 1-6 the walk cycle's phases), like the attack sheet
const PICK_FRAMES: int = 12 ## the one-second action animations (picking, eating): 12 frames, sampled at (i + 0.5) / 12
const PICK_SECONDS: float = 1.0
const PICK_GRAB_TIME: float = 0.34 ## picking: the hand closes around the berries here
const TOUCH_TIME: float = 0.45 ## touching a statue: the palms lie on the stone here (the statue wakes)
const TOUCH_HOLD_AT: float = 0.52 ## and stay there until `release_touch`
const FEED_SHEET: Texture2D = preload("res://assets/characters/player_feed.png") ## tools/art_hero3d.py feedonly: she crouches and holds food out to a wild bird
const FEED_BLOOD: Texture2D = preload("res://assets/characters/player_feed_blood.png")
const FEED_REACH_TIME: float = 0.5 ## feeding: the hand is out and stays (frame 6) until the bird has decided (`release_feed`)
const FEED_HOLD_MAX: float = 5.0 ## and drops by itself after this long
const PULL_GRAB_TIME: float = 0.52 ## pulling a root: it gives here and she is thrown back
const EAT_USE_TIME: float = 0.48 ## eating: the berry reaches her mouth (EatEffect.BITE) and takes effect
const DRINK_SHEET_ID: int = 16 ## `_use_sheet` number of the potion sheet (15 is the wall climb)
const DRINK_SHEET: Texture2D = preload("res://assets/characters/player_drink.png") ## tools/art_hero3d.py drinkonly: a potion in one draught, 12 frames x 7 leg variants
const DRINK_BLOOD: Texture2D = preload("res://assets/characters/player_drink_blood.png")
## The void blink (Space, BlinkComponent, play_blink/_try_blink, blink_fx) is ARCHIVED: replaced by the shadow step (Alt), the void branch's
## first ability. Its code, effects and sounds stay; set this to true to bring it back.
const BLINK_ENABLED: bool = false
const STEP_SHEET_ID: int = 17 ## `_use_sheet` number of the shadow step
const STEP_SHEET: Texture2D = preload("res://assets/characters/player_step.png") ## tools/art_hero_step.py: 8 frames per sector, both arms baked
const STEP_BLOOD: Texture2D = preload("res://assets/characters/player_step_blood.png")
const STEP_FRAMES: int = 8
const STEP_GONE: float = 0.1 ## the shadow step's clock: fully dissolved here (frames 0-3 before), and she is moved to the far end
const STEP_BACK: float = 0.13 ## ... she starts to condense out of the rift (frames 4-7 after)
const STEP_FORM: float = 0.08 ## ... and needs this long to be whole again
const STEP_END: float = 0.32 ## ... back in her own animation
const CAST_SHEET_ID: int = 18 ## `_use_sheet` number of the casting sheet (docs/magie_konzept.md)
const CAST_SHEET_PATH: String = "res://assets/characters/player_cast.png" ## tools/art_hero_cast.py: 8 sectors x 12 frames per clip (CAST_CLIPS)
const CAST_BLOOD_PATH: String = "res://assets/characters/player_cast_blood.png"
const CAST_CLIPS: Array[String] = ["light", "root", "ember", "veil", "maw"]
const STAFF_REST: Vector3 = Vector3(0.32, 0.28, 1.0) ## how she holds a staff (forward, side, lift in her own frame): upright beside her
const STAFF_RUN: Vector3 = Vector3(-0.5, 0.35, 0.55) ## leaning back while she sprints
const STAFF_KEYS: Dictionary = { ## the staff through a cast: [time share, pose]
	"light": [[0.0, Vector3(0.32, 0.28, 1.0)], [0.3, Vector3(0.04, 0.06, 1.0)], [0.46, Vector3(0.16, 0.1, 1.0)], [0.78, Vector3(0.18, 0.12, 1.0)], [1.0, Vector3(0.32, 0.28, 1.0)]],
	"root": [[0.0, Vector3(0.32, 0.28, 1.0)], [0.28, Vector3(-0.45, 0.38, 0.8)], [0.48, Vector3(1.0, -0.05, 0.3)], [0.76, Vector3(1.0, -0.05, 0.36)], [1.0, Vector3(0.32, 0.28, 1.0)]],
	"ember": [[0.0, Vector3(0.32, 0.28, 1.0)], [0.3, Vector3(-0.55, 0.42, 0.8)], [0.42, Vector3(1.0, -0.02, 0.14)], [0.7, Vector3(1.0, -0.02, 0.2)], [1.0, Vector3(0.32, 0.28, 1.0)]],
	"veil": [[0.0, Vector3(0.32, 0.28, 1.0)], [0.22, Vector3(0.12, -0.08, 1.0)], [0.4, Vector3(0.05, 0.05, 1.0)], [0.52, Vector3(0.6, 0.22, 0.7)], [0.76, Vector3(0.55, 0.22, 0.75)], [1.0, Vector3(0.32, 0.28, 1.0)]],
	"maw": [[0.0, Vector3(0.32, 0.28, 1.0)], [0.24, Vector3(0.1, 0.3, 1.0)], [0.4, Vector3(-0.1, 0.3, 1.0)], [0.54, Vector3(0.9, 0.05, -0.45)], [0.78, Vector3(0.9, 0.05, -0.4)], [1.0, Vector3(0.32, 0.28, 1.0)]],
}
const DRINK_SECONDS: float = 0.6 ## drinking is quick (docs/alchemie_konzept.md): the 12 frames play in 0.6 s
const DRINK_USE_TIME: float = 0.30 ## the draught: the potion takes effect (DrinkEffect.EFFECT)
const DRINK_BREAK_KNOCKBACK: float = 100.0 ## only a blow this heavy knocks the vial from her lips (the potion is kept)
const IDLE_FPS: float = 3.5 ## idle frames per second (breathing, hair)
const WOUND_ENTER: float = 0.10 ## wounded at this share of the maximum health or less ...
const WOUND_LEAVE: float = 0.13 ## ... and recovered above this share (so regeneration does not flicker it)
const WOUND_SPEED: float = 0.58 ## walking speed while wounded
const WOUND_PALE_FROM: float = 0.8 ## the blood loss starts to show below this share of health
const SHEET_COLS: int = 22

@export var max_speed: float = 62.0 ## px/s
@export var acceleration: float = 700.0 ## px/s²
@export var friction: float = 900.0 ## px/s²
@export var walk_fps: float = 13.0 ## walk frames per second at max_speed (6 frames = 1 cycle = 2 steps)
@export var jog_fps: float = 15.0 ## sprint-cycle frames per second at sprint_speed
@export var trot_fps: float = 14.0 ## jog-cycle frames per second halfway between max_speed and sprint_speed
@export var jog_from: float = 1.12 ## the jog starts above this share of max_speed ...
@export var sprint_from: float = 0.86 ## ... and turns into the sprint above this share of sprint_speed (a throttled sprint jogs)
@export var sneak_speed: float = 42.0 ## px/s while sneaking (Ctrl or C)
@export_group("Shadow step")
@export var step_range: float = 54.0 ## px the shadow step carries her (Alt; stops short at walls)
@export var step_stamina: float = 14.0 ## base stamina of one step; `step_cost()` adds 1 per level (not enough: no step)
@export var step_grace: float = 0.26 ## seconds from the push-off no blow can touch her (dissolved and condensing; damage over time still ticks)
@export_group("Sprint")
@export var sprint_speed: float = 124.0 ## px/s while sprinting
@export var burst_speed: float = 260.0 ## px/s right after pressing sprint, decays into sprint_speed
@export var burst_cost: float = 20.0 ## stamina, paid once on press
@export var sprint_cost_per_sec: float = 12.0 ## stamina while sprinting

var facing: Vector2 = Vector2.DOWN ## synced

var _walk_time: float = 0.0
var _gait: int = 0 ## 0 walk, 1 jog, 2 sprint: the cycle on screen (all share `_walk_time`, so a change never breaks the stride)
var _gait_hold: float = 0.0 ## a new gait must be asked for this long before it shows (no flicker at a speed border)
var _cadence: float = 0.0 ## cycle frames per second, eased so a change of pace or gait never jumps
var _settle: float = 0.0 ## time spent finishing a stride after stopping
var _step_t: float = -1.0 ## the running shadow step's clock, -1 when none
var _step_from: Vector2
var _step_to: Vector2
var _step_dir: Vector2 = Vector2.RIGHT
var _step_moved: bool = false
var _step_heard: bool = false
var stepper: ShadowStepComponent ## the shadow step's cooldown (created in _ready; the HUD's skill crystal shows it)
var _step_carry: float = 0.0 ## the speed she had going in: with a direction held she comes out of the void at it (a sprint goes on)
var _idle_time: float = 0.0
var _standby_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _standby_wait: float = -1.0
var _standby_clip: int = -1
var _standby_last: int = -1
var _standby_time: float = 0.0
var _rig_standby_shoulder: PackedVector2Array
var _rig_standby_hand: PackedVector2Array
var _rig_combo_shoulder: PackedVector2Array
var _rig_combo_hand: PackedVector2Array
var _rig_heavy_shoulder: PackedVector2Array
var _rig_heavy_hand: PackedVector2Array
var _swim_rig: Dictionary = {} ## hero_rig.json "swim": clips (start/count/fps) and hand points
var _swim_under: Sprite2D
var _swim_level: int = 0 ## which technique is drawn now (0 tread, 1 breast, 2 crawl); transitions step through them
var _swim_time: float = 0.0 ## seconds inside the current looping clip
var _swim_trans: String = "" ## a transition clip that is playing ("enter", "t2b", "b2c")
var _swim_trans_t: float = 0.0
var _swim_trans_dir: int = 1
var _swim_was: int = 0
var _swim_water: SwimWater
var _swim_last_local: int = -1
var _swim_drip: float = 0.0
var _swim_stir: float = 0.0
var _swim_wake: float = 0.0
var _swim_slot_on: bool = false
var _swim_shake_t: float = -1.0 ## >= 0 while the shake-off clip plays after a swim
var _swim_swum: float = 0.0 ## seconds spent swimming (a short dip does not need shaking off)
var _swim_dive: bool = false
var _wet: float = 0.0
var _wet_drip: float = 0.0
var _swim_exit_t: float = -1.0 ## >= 0 while the enter clip plays backwards after she left the water
var _rig_shoulder: PackedVector2Array ## per sheet frame, relative to the feet (data/hero_rig.json)
var _rig_hand: PackedVector2Array
var _rig_attack_shoulder: PackedVector2Array ## the same for the attack sheet
var _rig_attack_hand: PackedVector2Array
var _rig_pick_shoulder: PackedVector2Array ## and for the picking sheet
var _rig_pick_hand: PackedVector2Array
var _rig_pull_shoulder: PackedVector2Array ## and for the pulling sheet
var _rig_pull_hand: PackedVector2Array
var _rig_touch_shoulder: PackedVector2Array ## and for the touching sheet
var _rig_touch_hand: PackedVector2Array
var touch_hold: bool = false ## the palms stay on the stone (frozen at the end of the reach) until `release_touch`
var _touch_wait: float = 0.0
var feed_hold: bool = false ## the hand with the food stays out until `release_feed`
var _feed_item: String = ""
var _feed_fx: FeedFx
var _rig_feed_shoulder: PackedVector2Array ## and for the feeding sheet
var _rig_feed_hand: PackedVector2Array
var _rig_eat_shoulder: PackedVector2Array ## and for the eating sheet
var _rig_eat_hand: PackedVector2Array
var _rig_eat_mouth: PackedVector2Array
var _eat_fx: EatEffect
var _drink_fx: DrinkEffect ## the vial, the potion's light and the shattering vial (docs/alchemie_konzept.md)
var _rig_drink_shoulder: PackedVector2Array ## the potion sheet's rig (like eating: 7 leg variants)
var _rig_drink_hand: PackedVector2Array
var _rig_drink_mouth: PackedVector2Array
var fishing: FishingComponent ## the rod (docs/fishing.md)
var spells: SpellComponent ## the magic staff and its crystals (docs/magie_konzept.md)
var _cast_target: Vector2 = Vector2.ZERO ## where the running cast aims (world px), for the staff's pose
var _rig_cast_shoulder: PackedVector2Array ## the casting sheet's rig (tools/art_hero_cast.py: 12 frames x 2 clips, legs planted)
var _rig_cast_hand: PackedVector2Array
var _cast_sheet: Texture2D
var _cast_blood: Texture2D
var effects: StatusEffects ## burning and the like (data/status_effects.json)
var _main_sheet: Texture2D
var _sheet: int = 0 ## which sheet the sprite shows: 0 main, 1 sword swing, 2 picking, 3 eating, 4 pulling a root
var _busy_kind: String = "pick" ## which one-second action runs while `_busy`
var _busy: bool = false ## synced by RPC: she is picking and stands still
var _busy_time: float = 0.0
var _sector: int = 2
var sprinting: bool = false ## synced
var carry_stone: int = 0 ## > 0 while she carries a moonstone of the star mirror (set on every peer by `StarMirror`: `start_carry` / `end_carry`)
var _carry_anim: float = -1.0 ## seconds into lifting it (or setting it down); -1 = neither
var _carry_dir: int = 1 ## 1 lifting, -1 setting down
var _carry_walk: float = 0.0
var swim: int = 0 ## synced: SwimRules.NONE / TREAD / BREAST / CRAWL (docs/schwimmen_konzept.md)
var swimmer: SwimComponent
const SWIM_SUBMERGE: float = 17.0 ## px of water over her body while swimming (stand-in until the swim sheet exists)

var _surface: Dictionary = {} ## terrain.json entry under the feet
var _last_step: int = -1 ## walk-cycle frame of the previous tick, -1 while standing
var _sink: float = 0.0 ## px the sprite sits lower in water
var _idle_ripple_timer: float = 0.0
var _shake: float = 0.0 ## camera shake in px, decays
var view_shift: Vector2 = Vector2.ZERO ## the camera looks this far (world px) beside her: shops frame the person she talks to on the left (BoardWindow)
var _was_dead: bool = false
var _slows: Dictionary = {} ## instance id of whatever slows her (a bush) -> speed factor
var _focus: Interactable ## what E would use right now
var _hotbar: Hotbar ## the local HUD's hotbar: which slot E eats from
var quests: QuestComponent ## the owner's quests (null on other peers)
var tracked: TrackedQuests ## story quest + taken quest-board notices as one list for the HUD branch and the map (null on other peers)
var wounded: bool = false ## at 10 % health or less (until 13 %): slow, limping, no sprint, a red border on the HUD, on every peer
var _wound: float = 0.0 ## how much blood she has lost, 0..1, drives her look (eased towards the health)
var _limp_dip: float = 0.0
var _drip_timer: float = 2.0
var _hud: Node ## the local HUD
var stumbling: bool = false ## she is tripping, lying and getting up (the stumble sheet, see `begin_stumble`)
var _stumble_time: float = 0.0
var _stumble_phase: int = 0
var _stumble_wait: float = 0.0
var _stumble_cough_at: float = 1.4
var _stumble_prompt: InteractPrompt
var _stumble_fired: Dictionary = {}
const INTERACT_SCAN_SECONDS: float = 0.2 ## how often the interactables group is searched for the prompt (a press always searches)
var _scan_clock: float = 0.0
var _candidate: Interactable = null ## the nearest usable thing of the last scan, re-checked every frame
var fainting: bool = false ## the faint sheet is shown (AmbushScene drives the frames)
var _respawn_asked: bool = false
var story_lock: bool = false ## a cutscene holds her still (she still animates, the HUD stays)
var auto_walk: Vector2 = Vector2.INF ## while `story_lock`: a cutscene walks her slowly to this point (her limp and all)
var auto_walk_factor: float = -1.0 ## share of her top speed for that walk (< 0: the slow wounded walk)
var intro: Node ## while a story scene owns her (IntroScene, WakeScene) she cannot move or act
var bandaged: bool = false ## the rescuer dressed the wound: no blood, no red border, no heartbeat any more (she still limps while her health is low)

@onready var stamina: StaminaComponent = $StaminaComponent
@onready var blink: BlinkComponent = $BlinkComponent
@onready var stealth: StealthComponent = $StealthComponent
@onready var health: HealthComponent = $HealthComponent
@onready var progress: ProgressComponent = $ProgressComponent
@onready var inventory: InventoryComponent = $InventoryComponent
@onready var attack: AttackComponent = $AttackComponent
@onready var talismans: TalismanComponent = $TalismanComponent
@onready var appearance: AppearanceComponent = $AppearanceComponent
@onready var climb: WallClimb = $WallClimb
@onready var _camera: Camera2D = $Camera2D
@onready var _sprite: Sprite2D = $Sprite2D
@onready var _dash_dust: CPUParticles2D = $DashDust
@onready var _run_dust: CPUParticles2D = $RunDust
@onready var _footsteps: FootstepComponent = $FootstepComponent
@onready var _ripples: WaterRipples = $WaterRipples
@onready var _water: WaterOverlay = $WaterOverlay


func _enter_tree() -> void:
	if not all.has(self):
		all.append(self)
	set_multiplayer_authority(name.to_int())


func _exit_tree() -> void:
	all.erase(self)


func _ready() -> void:
	add_to_group("players")
	stepper = ShadowStepComponent.new()
	stepper.name = "ShadowStepComponent"
	add_child(stepper)
	_standby_rng.randomize()
	_load_rig()
	var rest: RestComponent = RestComponent.new()
	rest.name = "RestComponent"
	add_child(rest)
	swimmer = SwimComponent.new()
	swimmer.name = "SwimComponent"
	add_child(swimmer)
	swimmer.setup(self)
	fishing = FishingComponent.new()
	fishing.name = "FishingComponent"
	fishing.set_multiplayer_authority(get_multiplayer_authority()) ## a child made in _ready does not inherit the owner (its own _ready needs it)
	add_child(fishing)
	spells = SpellComponent.new()
	spells.name = "SpellComponent"
	spells.set_multiplayer_authority(get_multiplayer_authority())
	spells.setup(self)
	add_child(spells)
	effects = StatusEffects.new()
	effects.name = "Effects"
	effects.set_multiplayer_authority(get_multiplayer_authority())
	add_child(effects)
	_eat_fx = EatEffect.new()
	add_child(_eat_fx)
	_drink_fx = DrinkEffect.new()
	_drink_fx.name = "DrinkEffect"
	add_child(_drink_fx)
	_feed_fx = FeedFx.new()
	add_child(_feed_fx)
	_main_sheet = _sprite.texture
	_sprite.add_child(TalismanLayer.new()) ## the worn necklace and earrings
	(_sprite.material as ShaderMaterial).set_shader_parameter("blood_map", BLOOD_MAPS[0])
	health.damaged.connect(_on_damaged)
	health.ticked.connect(_on_ticked)
	health.changed.connect(_update_wounded)
	var world: Node = get_tree().get_first_node_in_group("world")
	if world != null and world.has_method("starting_health_ratio"):
		health.current = maxf(1, health.max_health * float(world.call("starting_health_ratio")))
		sync_wound_visuals()
		_shake = 0.0
	_update_wounded(health.current, health.max_health)
	health.healed.connect(_on_healed)
	if multiplayer.is_server():
		health.died.connect(_respawn_after_delay)
	_camera.enabled = is_multiplayer_authority()
	_camera.reset_smoothing()
	if is_multiplayer_authority():
		var free_cam: FreeCam = FreeCam.new()
		free_cam.name = "FreeCam"
		add_child(free_cam) ## L: the free camera (dev tool)
		quests = QuestComponent.new()
		quests.name = "QuestComponent"
		add_child(quests)
		tracked = TrackedQuests.new()
		tracked.name = "TrackedQuests"
		add_child(tracked)
		tracked.setup(self, quests)
		quests.story_event.connect(func(event_name: String) -> void:
			var story_world: Node = get_tree().get_first_node_in_group("world")
			if event_name == "ambush:crossroad" and story_world is WorldLevel:
				(story_world as WorldLevel).start_ambush(self)
			elif event_name == "wake:hut" and story_world is WorldLevel:
				(story_world as WorldLevel).start_wake(self)
			elif event_name == "meet:knight" and story_world is WorldLevel:
				(story_world as WorldLevel).start_knight_meet(self)
			elif event_name == "follow:knight" and story_world is WorldLevel:
				(story_world as WorldLevel).start_knight_walk(self)
			elif event_name.begins_with("story:") and story_world is WorldLevel:
				(story_world as WorldLevel).play_story_dialogue(self, event_name.trim_prefix("story:"))
			elif event_name == "finale:hut" and story_world is WorldLevel:
				(story_world as WorldLevel).start_hut_finale(self)
			elif event_name == "cabin:fight" and story_world is WorldLevel:
				(story_world as WorldLevel).start_cabin_spider(self)
			elif event_name == "wagon:fight" and story_world is WorldLevel:
				(story_world as WorldLevel).start_gustav_rescue(self, "fight")
			elif event_name == "wagon:meet" and story_world is WorldLevel:
				(story_world as WorldLevel).start_gustav_rescue(self, "meet")
			elif event_name == "escort:gustav" and story_world is WorldLevel:
				(story_world as WorldLevel).start_gustav_escort(self)
			elif event_name == "welcome:gustav" and story_world is WorldLevel:
				(story_world as WorldLevel).start_gustav_welcome(self))
		var hud: Node = HUD_SCENE.instantiate()
		_hud = hud
		add_child(hud)
		hud.call("bind", self)
		if world != null and world.has_method("starting_health_ratio"):
			var guide: OpeningGuide = OpeningGuide.new()
			guide.name = "OpeningGuide"
			add_child(guide)
			var stumbles: StumbleGuide = StumbleGuide.new()
			stumbles.name = "StumbleGuide"
			add_child(stumbles)
		_hotbar = hud.get_node("Hotbar") as Hotbar
		_hotbar.use_requested.connect(use_slot)
		inventory.changed.connect(_on_inventory_changed)
		health.changed.connect(_on_health_changed)
		attack.lunged.connect(func(impulse: Vector2) -> void: velocity += impulse)
		attack.hit_landed.connect(func(strength: float) -> void: _shake = maxf(_shake, strength))
		_on_inventory_changed()


## The camera, for windows that frame a scene (zoom and `view_shift`).
func view_camera() -> Camera2D:
	return _camera


func _process(delta: float) -> void:
	## the camera looks a little ahead of where she walks: the smoothing alone lets her drift towards the edge she is heading for
	var lead_goal: Vector2 = velocity * CAMERA_LEAD if is_multiplayer_authority() and intro == null and not story_lock and health.current > 0.0 else Vector2.ZERO
	_lead = _lead.lerp(lead_goal, 1.0 - exp(-CAMERA_LEAD_EASE * delta))
	_camera.offset = view_shift + _lead + ((Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake * GameSettings.shake_factor()).round() if _shake > 0.0 else Vector2.ZERO)
	_shake = move_toward(_shake, 0.0, 14.0 * delta)


const CAMERA_LEAD: float = 0.22 ## seconds of her velocity the camera looks ahead (the smoothing lags about 0.14 s, so she stays near the middle with a little view ahead)
const CAMERA_LEAD_EASE: float = 2.6 ## how quickly that look-ahead follows a change of direction (1/s)
const TURN_BOOST: float = 1.5 ## acceleration factor while she pushes against her own motion: a turn-around bites at once instead of sliding
const SPRINT_RECOVER: float = 15.0 ## stamina she needs back before a sprint run dry starts again (or let go of the key)
const DIAGONAL_GRACE: float = 0.06 ## seconds a diagonal facing survives one of its two keys: letting go of both never ends on a sideways flick
var _lead: Vector2 = Vector2.ZERO
var _winded: bool = false ## the sprint ran dry while the key is still held
var _face_dir: Vector2 = Vector2.DOWN ## the walking direction her facing follows
var _face_hold: float = 0.0
var _last_surface_tile: Vector2i = Vector2i(1 << 30, 1 << 30)
var _last_surface_result: Dictionary = {}
var heat_amount: float = 0.0 ## 0..1 continuous Sonnenquarz-Öde midday heat pressure (local & deterministic on every peer)


## True while desert midday heat is pressing on her (`ERHITZT` or >= threshold).
func is_heated() -> bool:
	return heat_amount >= DesertHeat.HEAT_THRESHOLD or (effects != null and effects.has("sun_heat"))


## Host & local cooling relief (eating cooling desert fruits or oasis plunge): clears `sun_heat` and grants `refreshed`.
func cool_down(seconds: float = DesertHeat.OASIS_REFRESH_SECONDS) -> void:
	heat_amount = 0.0
	if multiplayer.is_server():
		if effects != null:
			effects.clear("sun_heat")
			effects.apply("refreshed", seconds)
		if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty():
			_rpc_reset_heat.rpc()


@rpc("authority", "call_local", "reliable")
func _rpc_reset_heat() -> void:
	heat_amount = 0.0


func _update_desert_heat(delta: float) -> void:
	if health.current <= 0.0 or intro != null:
		heat_amount = 0.0
		return
	if DesertHeat.is_in_cooling_water(self):
		heat_amount = 0.0
		return
	if effects != null and effects.has("refreshed"):
		heat_amount = move_toward(heat_amount, 0.0, DesertHeat.COOL_REFRESHED_RATE * delta)
		return
	var drive: float = DesertHeat.heat_drive(get_tree(), global_position)
	heat_amount = clampf(heat_amount + drive * delta, 0.0, 1.0)

func _physics_process(delta: float) -> void:
	var tile_pos: Vector2i = Vector2i((global_position / 16.0).floor())
	if tile_pos != _last_surface_tile:
		_last_surface_tile = tile_pos
		_surface = Terrain.surface_data(Terrain.surface_at(global_position))
		for patch: Node in Terrain.patches:
			if patch is WorldRivers:
				_surface = (patch as WorldRivers).wade_data(global_position, _surface)
		_last_surface_result = _surface
	else:
		_surface = _last_surface_result
	var down: bool = health.current <= 0.0
	_sprite.self_modulate = Color(0.35, 0.25, 0.5, 0.55) if down else Color.WHITE.lerp(Color(1.5, 1.9, 1.55), _eat_glow())
	if climb.active():
		climb.step(delta)
		_set_focus(null)
	elif down:
		velocity = Vector2.ZERO
		_set_focus(null)
		climb.hide_prompt()
	elif launch_left > 0.0 and is_multiplayer_authority():
		_step_launch(delta)
		_set_focus(null)
		climb.hide_prompt()
	elif intro != null or story_lock:
		velocity = Vector2.ZERO ## the intro owns her: it places her and shows the frames
		if story_lock and intro == null and auto_walk != Vector2.INF and is_multiplayer_authority():
			var to_goal: Vector2 = auto_walk - global_position
			if to_goal.length() > 2.0:
				velocity = to_goal.normalized() * max_speed * (auto_walk_factor if auto_walk_factor > 0.0 else WOUND_SPEED * 0.8)
				facing = to_goal.normalized()
				move_and_slide()
		_set_focus(null)
		climb.hide_prompt()
	elif stumbling:
		velocity = velocity.move_toward(Vector2.ZERO, 260.0 * delta) ## she slides on a little
		if is_multiplayer_authority():
			move_and_slide()
		_set_focus(null)
		climb.hide_prompt()
		_update_stumble(delta)
	elif is_multiplayer_authority():
		_move(delta)
		_update_interact()
	else:
		position += velocity * delta ## remote player: the synchronizer sends at 20 Hz, so carry on with the synced velocity until the next packet
	attack.visible = not down and intro == null and not fainting and not stumbling and not climb.active() and carry_stone == 0
	_wound = move_toward(_wound, _wound_target(), delta * 0.5)
	(_sprite.material as ShaderMaterial).set_shader_parameter("wound", _wound)
	attack.wound = _wound
	attack.facing = facing
	if intro == null and not fainting and not stumbling:
		_animate(delta)
	else:
		_cancel_standby()
	_update_run_dust()
	_update_water(delta)
	_update_desert_heat(delta)


## Dust shoots out behind the player at the moment of the dash. Runs on every peer.
@rpc("authority", "call_local", "reliable")
func play_burst(dir: Vector2) -> void:
	if _is_submerged():
		return
	_dash_dust.direction = -dir
	_dash_dust.restart()


## Void blink effects (rifts, silhouette trail, flash). Runs on every peer.
@rpc("authority", "call_local", "reliable")
func play_blink(from: Vector2, to: Vector2) -> void:
	blink.play_effects(_sprite, from, to)
	talismans.note_blink() ## Rissfeder: the next blow within a few seconds dives in harder


## Jumps toward the facing direction, at most `blink_range` and not past the cursor.
## Stops at obstacles.
func _try_blink() -> void:
	var start: Vector2 = global_position
	var distance: float = blink.blink_range
	if InputManager.using_mouse:
		distance = minf(distance, InputManager.aim_world_position().distance_to(start + BODY_CENTER))
	move_and_collide(facing * distance)
	if global_position.distance_to(start) < blink.min_distance:
		global_position = start ## wall right in front: cancelled, no cooldown spent
		return
	blink.start_cooldown()
	play_blink.rpc(start, global_position)


## Alt: a short straight step through the void, the way she is walking, or towards the cursor (or where she looks) when she stands.
## Stops short at walls; too short a way is no step at all. True when it started.
func _try_shadow_step(input_dir: Vector2) -> bool:
	var way: Vector2 = input_dir.normalized()
	if way == Vector2.ZERO:
		way = InputManager.aim_vector(global_position + BODY_CENTER).normalized() if InputManager.using_mouse else facing.normalized()
	if way == Vector2.ZERO:
		way = facing.normalized()
	var hit: KinematicCollision2D = move_and_collide(way * step_range, true)
	var travel: Vector2 = way * step_range if hit == null else hit.get_travel()
	if travel.length() < 12.0:
		return false
	if not stamina.spend(step_cost()):
		return false ## out of breath: the void does not take her
	stepper.start_cooldown()
	attack.cancel_action() ## out of the swing or the charge, no blow lands
	_step_carry = velocity.length() ## a sprint is not broken: she keeps it through the void
	facing = way
	velocity = Vector2.ZERO
	play_shadow_step.rpc(global_position, global_position + travel, way)
	return true


## Stamina one shadow step costs: 14 + 1 per level (level 1 = 15), increased up to +15 % under desert midday heat.
func step_cost() -> float:
	return (step_stamina + float(progress.level)) * (1.0 + DesertHeat.STAMINA_COST_PENALTY * heat_amount)


## The shadow step on every peer: she dips, pushes off, dissolves into the void from her leading edge, is put down at `to` and condenses
## out of the same void (`_animate_step`, `ShadowStepFx`, `hit_flash.gdshader` step_*).
@rpc("authority", "call_local", "reliable")
func play_shadow_step(from: Vector2, to: Vector2, way: Vector2) -> void:
	_cancel_standby()
	_busy = false ## picking, eating, drinking: broken off, their moment never comes
	_step_t = 0.0
	_step_from = from
	_step_to = to
	_step_dir = way.normalized() if way != Vector2.ZERO else Vector2.RIGHT
	_step_moved = false
	_step_heard = false
	if multiplayer.is_server():
		health.grant_grace(step_grace) ## the host decides hits: while she is in the void nothing reaches her
	talismans.note_blink() ## Rissfeder: the next blow within a few seconds dives in harder (it was the blink's perk)
	var fx: ShadowStepFx = ShadowStepFx.new()
	get_tree().current_scene.add_child(fx)
	fx.setup(from, to, _step_dir, STEP_GONE, STEP_BACK)
	Sfx.at(self, "step_out", from, -3.0)


## One frame of the shadow step: her sheet frame, the dissolve / condense in the shader, a little slide along the step, the move itself.
func _animate_step(delta: float) -> void:
	_step_t += delta
	var t: float = _step_t
	var material: ShaderMaterial = _sprite.material as ShaderMaterial
	if t >= STEP_END or (t >= STEP_BACK + STEP_FORM and velocity.length() > 5.0): ## every peer: moving on (synced velocity) skips the landing
		_finish_step()
		return
	_sector = posmod(roundi(_step_dir.angle() / (PI / 4.0)), 8)
	var i: int
	if t < STEP_GONE:
		i = clampi(int(t / STEP_GONE * 4.0), 0, 3)
	elif t < STEP_BACK:
		i = 3
	else:
		i = clampi(4 + int((t - STEP_BACK) / (STEP_END - STEP_BACK) * 4.0), 4, 7)
	_use_sheet(STEP_SHEET_ID)
	_sprite.frame = _sector * STEP_FRAMES + i
	if t < STEP_BACK:
		material.set_shader_parameter("step_mode", 1)
		material.set_shader_parameter("step_amt", clampf((t - 0.012) / (STEP_GONE - 0.012), 0.0, 1.0))
	elif t < STEP_BACK + STEP_FORM:
		material.set_shader_parameter("step_mode", 2)
		material.set_shader_parameter("step_amt", clampf((t - STEP_BACK) / STEP_FORM, 0.0, 1.0))
	else:
		material.set_shader_parameter("step_mode", 0)
	material.set_shader_parameter("step_dir", _step_dir)
	material.set_shader_parameter("step_seed", floorf(t * 30.0))
	var slide: Vector2
	if t < STEP_BACK:
		var k: float = clampf(t / STEP_GONE, 0.0, 1.0)
		slide = _step_dir * 8.0 * k * k ## the push carries her into the rift
	else:
		var k: float = clampf((t - STEP_BACK) / 0.12, 0.0, 1.0)
		slide = -_step_dir * 7.0 * (1.0 - k) * (1.0 - k) ## she comes out of it still moving and settles
	_sprite.position = (Vector2(0.0, _sink) + slide).round()
	if not _step_moved and t >= STEP_GONE:
		_step_moved = true
		global_position = _step_to ## every peer: hidden in the void, so the jump is never seen (the synchronizer agrees a moment later)
	if not _step_heard and t >= STEP_BACK - 0.03:
		_step_heard = true
		Sfx.at(self, "step_in", _step_to, -3.0)
	_set_step_extras(false)


## The step is over: shader clean, sprite back in place, arm and jewellery shown again.
func _finish_step() -> void:
	if _step_t < 0.0:
		return
	_step_t = -1.0
	if not _step_moved:
		_step_moved = true
		global_position = _step_to
	(_sprite.material as ShaderMaterial).set_shader_parameter("step_mode", 0)
	_sprite.position = Vector2(0.0, _sink)
	_set_step_extras(true)


## The game-drawn sword arm and the worn jewellery cannot dissolve with her: they are hidden for the step (the sheet carries both arms).
func _set_step_extras(on: bool) -> void:
	attack.set_arm_shown(on)
	for child: Node in _sprite.get_children():
		if child is TalismanLayer:
			(child as CanvasItem).visible = on


## Dev menu: jumps to a place (the owner moves herself; the synchronizer tells the others).
func request_teleport(to: Vector2) -> void:
	climb.before_teleport()
	if swimmer != null:
		swimmer.reset() ## she lands on foot; the next step decides again
		swim = SwimRules.NONE
	global_position = to
	velocity = Vector2.ZERO
	_lead = Vector2.ZERO
	reset_physics_interpolation() ## a jump, not a move: without this she is drawn streaking across the world for one tick
	_camera.reset_smoothing()


## A boss throws her across the floor: she slides from where she stands to `target` in `seconds` (fast at first, slowing down, stopped by anything solid on
## the way); she cannot act meanwhile. Sent to the one who owns her (`launch`), who moves her.
var launch_left: float = 0.0
var launch_total: float = 1.0
var launch_from: Vector2 = Vector2.ZERO
var launch_to: Vector2 = Vector2.ZERO


func launch(target: Vector2, seconds: float) -> void:
	climb.interrupt()
	_rpc_launch.rpc_id(get_multiplayer_authority(), target, seconds)


@rpc("any_peer", "call_local", "reliable")
func _rpc_launch(target: Vector2, seconds: float) -> void:
	if multiplayer.get_remote_sender_id() > 1:
		return
	_busy = false
	_cancel_standby()
	launch_from = global_position
	launch_to = target
	launch_total = maxf(seconds, 0.05)
	launch_left = launch_total


func _step_launch(delta: float) -> void:
	launch_left = maxf(launch_left - delta, 0.0)
	var k: float = clampf(1.0 - launch_left / launch_total, 0.0, 1.0)
	var want: Vector2 = launch_from.lerp(launch_to, 1.0 - pow(1.0 - k, 3.0))
	velocity = (want - global_position) / maxf(delta, 0.0001)
	move_and_slide()
	if launch_left <= 0.0:
		velocity = Vector2.ZERO


## Cheat menu: full health (the host decides, so a client asks) and full stamina.
func request_heal() -> void:
	stamina.refill()
	if multiplayer.is_server():
		health.heal_full()
	else:
		_rpc_heal.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_heal() -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		health.heal_full()


func _on_inventory_changed() -> void:
	var in_hand: Dictionary = inventory.active_stack()
	attack.held_weapon = String(in_hand.get("id", "")) ## a selected tool replaces the weapon
	attack.held_refine = Items.refine(in_hand)


## Everyone sees the hit; the owner also gets knocked back and shaken.
func _on_damaged(amount: float, from: Vector2, knockback: float) -> void:
	climb.interrupt()
	if not (_drinking() and knockback < DRINK_BREAK_KNOCKBACK): ## only a heavy blow knocks the vial from her lips
		_busy = false ## a hit interrupts picking
	_cancel_standby()
	if is_multiplayer_authority():
		attack.interrupt_charge() ## ... and the charge of a heavy blow
	var away: Vector2 = (global_position - from).normalized()
	var flash: ShaderMaterial = _sprite.material as ShaderMaterial
	flash.set_shader_parameter("flash", 1.0)
	create_tween().tween_property(flash, "shader_parameter/flash", 0.0, 0.2)
	DamageNumber.spawn(get_tree().current_scene, global_position + Vector2(0, -50), amount, away, Color("ff5a6a"))
	if health.current > 0.0:
		Sfx.at_any(self, ["ellie_hurt_a", "ellie_hurt_b"], global_position, -2.0, 0.04) ## a grunt for every hit she survives
	if is_multiplayer_authority():
		velocity += away * knockback
		_shake = maxf(_shake, 3.0)


## Everyone sees a small number in the colour of the burning (a tick of damage over time).
func _on_ticked(amount: float) -> void:
	DamageNumber.spawn_text(get_tree().current_scene, global_position + Vector2(randf_range(-6.0, 6.0), -46), str(roundi(amount)), Color("ff6ad8"))


## Everyone sees the green number.
func _on_healed(amount: float) -> void:
	var over: bool = health.current > health.max_health ## overheal is white, health green
	DamageNumber.spawn_text(get_tree().current_scene, global_position + Vector2(0, -50), "+%d" % roundi(amount), Color("f4f0ff") if over else Color("9af0a8"))


func _on_health_changed(current: float, _maximum: float) -> void:
	if _was_dead and current > 0.0: ## respawned
		var level: TestLevel = get_parent().get_parent() as TestLevel ## players hang under the level's `Players` node
		global_position = level.spawn_point() if level else SPAWN_POINT
		velocity = Vector2.ZERO
		_camera.reset_smoothing()
		sync_wound_visuals()
	_was_dead = current <= 0.0


## Host: after a fall the player waits for the choice on her death screen (`request_respawn`); a player who never answers
## (gone, stuck) is brought back after `RESPAWN_FALLBACK_SECONDS` anyway.
func _respawn_after_delay() -> void:
	_respawn_asked = false
	var left: float = RESPAWN_FALLBACK_SECONDS
	while not _respawn_asked and left > 0.0 and health.current <= 0.0:
		await get_tree().create_timer(0.25).timeout
		if not is_inside_tree():
			return
		left -= 0.25
	_respawn_asked = false
	if health.current > 0.0:
		return
	var world: Node = get_tree().get_first_node_in_group("world")
	if world is WorldLevel and not (world as WorldLevel).opening_over: ## still in the opening: she comes back wounded
		health.set_health(health.max_health * (world as WorldLevel).starting_health_ratio())
	else:
		health.heal_full()


## The death screen's ZURÜCKKEHREN: the host brings her back (a client asks).
func request_respawn() -> void:
	if multiplayer.is_server():
		_respawn_asked = true
	else:
		_rpc_respawn.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_respawn() -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		_respawn_asked = true


func _is_submerged() -> bool:
	return float(_surface.get("submerge", 0.0)) > 0.0


## Owner: runs the swim rules for this frame and publishes the technique in `swim` (synced). The ban only keeps her from starting to swim.
func _update_swim(delta: float, dir: Vector2) -> int:
	var allowed: bool = health.current > 0.0 and not story_lock and intro == null and not _busy and not fainting and not stumbling and not attack.is_swinging()
	swim = swimmer.step(delta, float(_surface.get("depth_amount", 0.0)), bool(_surface.get("water", false)), allowed, dir != Vector2.ZERO, InputManager.sprint_held(), stamina, wounded)
	return swim


func _update_water(delta: float) -> void:
	var submerge: float = float(_surface.get("submerge", 0.0))
	if swim > 0 or _swim_exit_t >= 0.0:
		submerge = 0.0 ## the swim sheet carries its own waterline (step 3 adds the water in front)
	_water.submerge = submerge
	_update_swim_slot()
	_update_wet(delta)
	_sink = move_toward(_sink, roundf(submerge / 2.5), 20.0 * delta)
	if bool(_surface.get("ripples", false)) and velocity.length() < 5.0: ## ripples while standing still
		_idle_ripple_timer -= delta
		if _idle_ripple_timer <= 0.0:
			_ripples.add(global_position)
			_idle_ripple_timer = 0.9


## A one-shot swim sound at her feet (every peer plays its own; positional).
func _swim_sound(sound_name: String, db: float, pitch: float = 1.0) -> void:
	var cfg: Dictionary = SwimRules.cfg().get("sounds", {}) as Dictionary
	var sound: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
	sound.stream = SWIM_SOUNDS[sound_name] as AudioStream
	sound.volume_db = db + (float(cfg.get("dive_db", -6.0)) if sound_name.begins_with("dive") else 0.0)
	sound.pitch_scale = pitch * randf_range(0.93, 1.07)
	sound.max_distance = float(cfg.get("range", 320.0))
	add_child(sound)
	sound.finished.connect(sound.queue_free)
	sound.play()


## The river carries her a little (docs/schwimmen_konzept.md 4.4): at most 18 % of the walking speed, none while crawling.
func _swim_drift(state: int) -> Vector2:
	if state == SwimRules.CRAWL or fishing == null:
		return Vector2.ZERO
	var cfg: Dictionary = SwimRules.cfg().get("current", {}) as Dictionary
	return fishing.current_at(global_position) * max_speed * float(cfg.get("max_drift", 0.18))


## Swimming against the stream is slower (breaststroke up to 15 %).
func _against_current(dir: Vector2, state: int) -> float:
	if state != SwimRules.BREAST or fishing == null:
		return 1.0
	var flow: Vector2 = fishing.current_at(global_position)
	if flow == Vector2.ZERO:
		return 1.0
	var cfg: Dictionary = SwimRules.cfg().get("current", {}) as Dictionary
	return 1.0 - float(cfg.get("against", 0.15)) * clampf(-dir.dot(flow.normalized()) * flow.length(), 0.0, 1.0)


## Soaked after a swim (0..1): the shader darkens her, prints on dry ground turn dark, drops fall from hair and coat; dries over about 25 s.
func _update_wet(delta: float) -> void:
	var target: float = 0.0
	if swim > 0:
		_swim_swum += delta
		target = 1.0
	elif float(_surface.get("submerge", 0.0)) > 6.0:
		target = 0.45
	var was: float = _wet
	var rained_on: float = 0.0 ## the weather (docs/wetter_konzept.md 9): rain soaks her slowly, under a crown or a roof she stays dry
	if swim == 0 and WeatherManager.current != null and target == 0.0:
		rained_on = clampf(WeatherManager.current.exposure_at(global_position) * 0.85, 0.0, 0.8)
	if target > _wet:
		_wet = move_toward(_wet, target, 2.5 * delta)
	elif rained_on > _wet:
		_wet = move_toward(_wet, rained_on, delta / 9.0)
	else:
		_wet = move_toward(_wet, rained_on if target == 0.0 else target, delta / 25.0)
	if _wet != was:
		(_sprite.material as ShaderMaterial).set_shader_parameter("soak", _wet)
	if _wet > 0.3 and swim == 0 and _swim_water != null:
		_wet_drip -= delta
		if _wet_drip <= 0.0:
			_wet_drip = 0.9 / _wet
			_swim_water.splash(global_position + Vector2(randf_range(-4.0, 4.0), randf_range(-1.0, 1.0)), 1, 0.2, false, 10.0 + randf() * 8.0)


## Tells the river surface where a swimmer is so the water rings around her (WorldRivers.set_swimmer, shader river_water).
func _update_swim_slot() -> void:
	var on: bool = swim > 0 and swimmer != null
	if not on and not _swim_slot_on:
		return
	for patch: Node in Terrain.patches:
		if patch is WorldRivers:
			var slot: Vector4 = Vector4(roundf(global_position.x), roundf(global_position.y), 9.0, 0.0)
			if on:
				slot.w = clampf(0.25 + (_swim_water.energy if _swim_water != null else 0.2), 0.2, 1.0)
			(patch as WorldRivers).set_swimmer(get_instance_id(), slot)
	_swim_slot_on = on


## Called at every footfall (also for remote players, driven by the walk animation).
func _on_step() -> void:
	_footsteps.step(_surface, velocity, stealth.sneaking, _wet, 0 if carry_stone != 0 else _gait)
	if (wounded or _wound > 0.55) and not bandaged:
		BloodSplat.drop(get_tree().current_scene, global_position + Vector2(randf_range(-3.0, 3.0), randf_range(-1.0, 2.0)), 1 + int(randf() < 0.4))
	if bool(_surface.get("ripples", false)):
		_ripples.add(_footsteps.contact_position(velocity), clampf(velocity.length() / 65.0, 0.35, 1.5))


func _update_run_dust() -> void:
	var running: bool = sprinting and velocity.length() > RUN_DUST_MIN_SPEED and not _is_submerged()
	_run_dust.emitting = running
	if running:
		_run_dust.direction = -velocity.normalized()


func _move(delta: float) -> void:
	if _step_t >= 0.0: ## the shadow step owns her until she has condensed again ...
		var held: Vector2 = InputManager.move_vector()
		if _step_t < STEP_BACK + STEP_FORM or held == Vector2.ZERO:
			velocity = Vector2.ZERO
			return
		_finish_step() ## ... then, with a direction held, she runs straight on at the speed she had (the landing pose is skipped)
		velocity = held.normalized() * maxf(_step_carry, max_speed * (WOUND_SPEED if wounded else 1.0))
	if carry_stone != 0: ## a moonstone in her arms: slow, no sprint, no swing, no dodge (she sets it down with E)
		_move_carrying(delta)
		return
	## Alt breaks everything she is doing (a swing in any phase, a charge, picking, eating, a gesture): a real dodge
	if InputManager.shadow_step_pressed() and stepper.is_ready() and swim == 0 and not (fishing != null and fishing.locks_movement()) and bool(_surface.get("allow_blink", true)):
		if _try_shadow_step(InputManager.move_vector()):
			return
	var eating: bool = _busy and (_busy_kind == "eat" or _busy_kind.begins_with("drink")) ## eating and drinking, unlike picking, go on while she walks
	if fishing != null and fishing.locks_movement(): ## a fish is on the line: she braces and stands still
		velocity = velocity.move_toward(Vector2.ZERO, friction * 2.0 * delta)
		move_and_slide()
		return
	if _busy and not eating: ## she stands still while she picks
		velocity = velocity.move_toward(Vector2.ZERO, friction * 2.0 * delta)
		move_and_slide()
		return
	var charging: bool = _update_charge()
	_update_alt()
	var dir: Vector2 = InputManager.move_vector()
	if attack.is_heavy_swing():
		dir = Vector2.ZERO ## the heavy blow is struck planted
	var swimming: int = _update_swim(delta, dir)
	var can_sprint: bool = bool(_surface.get("allow_sprint", true)) and not wounded ## wounded: no sprinting
	var want_sprint: bool = InputManager.sprint_held() and can_sprint and dir != Vector2.ZERO and not attack.is_swinging() and not _busy and not charging
	if not InputManager.sprint_held() or stamina.current >= SPRINT_RECOVER:
		_winded = false
	if swimming > 0:
		sprinting = swimming == SwimRules.CRAWL ## the crawl is the sprint of the water (it pays its own stamina)
	elif want_sprint and not _winded and stamina.current > 0.0:
		sprinting = stamina.drain(sprint_cost_per_sec * stamina.sprint_scale(), delta)
		_winded = not sprinting ## out of breath: no one-frame sprint blips every time a crumb of stamina comes back
	else:
		sprinting = false

	if BLINK_ENABLED and InputManager.blink_pressed() and blink.is_ready() and not _busy and swimming == 0 and bool(_surface.get("allow_blink", true)):
		_try_blink()

	stealth.sneaking = InputManager.sneak_held() and not sprinting and not _busy and not charging and swimming == 0

	if dir == Vector2.ZERO:
		velocity = velocity.move_toward(_swim_drift(swimming) if swimming > 0 else Vector2.ZERO, friction * delta)
	elif swimming > 0:
		velocity = velocity.move_toward(dir * swimmer.speed(wounded) * _against_current(dir, swimming) + _swim_drift(swimming), acceleration * 0.5 * delta) ## water gives way slowly
	else:
		var base_speed: float = sprint_speed if sprinting else (sneak_speed if stealth.sneaking else max_speed)
		var speed: float = base_speed * float(_surface.get("speed", 1.0)) * _slow_factor() * (WOUND_SPEED if wounded else 1.0) * attack.charge_move_factor()
		velocity = velocity.move_toward(dir * speed, acceleration * (TURN_BOOST if velocity.dot(dir) < 0.0 else 1.0) * delta)
	move_and_slide()

	if dir != Vector2.ZERO:
		var heading: Vector2 = dir.normalized()
		var was_diagonal: bool = absf(_face_dir.x) > 0.3 and absf(_face_dir.y) > 0.3
		var now_straight: bool = absf(heading.x) < 0.05 or absf(heading.y) < 0.05
		if was_diagonal and now_straight and heading.dot(_face_dir) > 0.6 and _face_hold < DIAGONAL_GRACE:
			_face_hold += delta ## one key of a diagonal was let go: the other usually follows within a frame or two
		else:
			_face_hold = 0.0
			_face_dir = heading
	else:
		_face_hold = 0.0

	if attack.is_swinging():
		facing = attack.aim_dir ## locked toward the swing
		return
	if charging:
		facing = attack.aim_dir ## follows the cursor while the blow is charged
		return
	var in_combat: bool = attack.is_in_combat(1.5)
	if in_combat and InputManager.using_mouse:
		var look_mouse: Vector2 = InputManager.aim_vector(global_position + BODY_CENTER)
		if look_mouse != Vector2.ZERO:
			facing = look_mouse
	elif dir != Vector2.ZERO:
		facing = _face_dir
	if InputManager.attack_pressed() and spells != null and spells.staff_held and attack.holds_staff() and not _busy and swimming == 0:
		var aim_at: Vector2 = InputManager.aim_world_position() if InputManager.using_mouse else global_position + facing * 60.0
		if spells.try_cast(aim_at): ## a staff in her hand: the left button casts its crystal (docs/magie_konzept.md)
			sprinting = false
	if InputManager.secondary_held() and spells != null and spells.staff_held and spells.prongs > 1 and attack.holds_staff() and not _busy and swimming == 0:
		var aim_right: Vector2 = InputManager.aim_world_position() if InputManager.using_mouse else global_position + facing * 60.0
		if spells.try_cast(aim_right, 1): ## the Bleichgabel: the right button casts the crystal of its second prong (docs/magie_konzept.md 17)
			sprinting = false
	if InputManager.attack_pressed() and attack.can_attack() and not _busy and swimming == 0:
		if InputManager.using_mouse:
			var attack_aim: Vector2 = InputManager.aim_vector(global_position + BODY_CENTER)
			if attack_aim != Vector2.ZERO:
				facing = attack_aim
		sprinting = false ## swinging while sprinting drops her into a walk
		attack.attack(facing)


## Owner, every physics frame: the right mouse button charges the weapon's secondary attack (the sword's heavy blow) and
## lets it go on release. A menu taking the input, a dodge, a cutscene or a fall drops the charge. True while charging.
func _update_charge() -> bool:
	if not is_multiplayer_authority():
		return false
	var blocked: bool = _busy or stumbling or fainting or intro != null or story_lock or health.current <= 0.0 or swim > 0
	if attack.is_charging():
		if blocked or InputManager.shadow_step_pressed():
			attack.cancel_charge()
			return false
		var aim: Vector2 = InputManager.aim_vector(global_position + BODY_CENTER) if InputManager.using_mouse else Vector2.ZERO
		var still: bool = attack.charge_input(InputManager.secondary_held(), InputManager.secondary_down(), aim, get_physics_process_delta_time())
		return still and attack.is_charging()
	if blocked or not InputManager.secondary_pressed() or not attack.can_charge():
		return false
	var start_aim: Vector2 = InputManager.aim_vector(global_position + BODY_CENTER) if InputManager.using_mouse else facing
	sprinting = false ## the charge drops a sprint into a walk
	attack.begin_charge(start_aim)
	return attack.is_charging()


## Owner, every physics frame: the right mouse button on a weapon whose right click is a chain of slashes (the Himmelsriss) starts the first slash, a second press
## shortly after the second one. Pressed during the first slash it is kept until that has ended.
func _update_alt() -> void:
	if not is_multiplayer_authority() or not InputManager.secondary_pressed():
		return
	if _busy or stumbling or fainting or intro != null or story_lock or health.current <= 0.0 or swim > 0 or attack.is_charging():
		return
	if not attack.can_alt() and not attack.is_swinging():
		return
	var aim: Vector2 = InputManager.aim_vector(global_position + BODY_CENTER) if InputManager.using_mouse else facing
	if aim != Vector2.ZERO and not attack.is_swinging():
		facing = aim
	if not attack.is_swinging():
		sprinting = false ## swinging while sprinting drops her into a walk
	attack.alt_press(aim)


## Something owns her: a cutscene, an action, a fall (the rod cannot be cast then).
## Owner: walking with a moonstone in both arms. While it is lifted or set down she stands still.
func _move_carrying(delta: float) -> void:
	sprinting = false
	stealth.sneaking = false
	var dir: Vector2 = InputManager.move_vector() if _carry_anim < 0.0 and not _busy else Vector2.ZERO
	var speed: float = max_speed * CARRY_SPEED * float(_surface.get("speed", 1.0)) * _slow_factor() * (WOUND_SPEED if wounded else 1.0)
	velocity = velocity.move_toward(dir * speed, acceleration * delta) if dir != Vector2.ZERO else velocity.move_toward(Vector2.ZERO, friction * 2.0 * delta)
	move_and_slide()
	if dir != Vector2.ZERO:
		facing = dir.normalized()


## Every peer (the star mirror calls it for the player who took a stone): she stoops and lifts it.
func start_carry() -> void:
	carry_stone = 1
	_carry_anim = 0.0
	_carry_dir = 1
	_carry_walk = 0.0
	sprinting = false


## Every peer: she sets the stone down (the lift backwards), then the normal sheet comes back.
func end_carry() -> void:
	if carry_stone == 0:
		return
	_carry_anim = 0.0
	_carry_dir = -1


## Seconds the lift (or the set-down) takes.
static func carry_lift_time() -> float:
	return 8.0 / CARRY_LIFT_FPS


func _animate_carry(delta: float) -> void:
	if _sheet != CARRY_STONE_ID:
		_sheet = CARRY_STONE_ID
		(_sprite.material as ShaderMaterial).set_shader_parameter("blood_map", null)
		_sprite.texture = CARRY_STONE_SHEET
		_sprite.hframes = int(CARRY_STONE_SHEET.get_width() / 72.0)
		_sprite.vframes = 8
		_sprite.offset = Vector2(0.0, -13.0)
		_sprite.flip_h = false
		_sprite.position = Vector2.ZERO
		_sprite.skew = 0.0
	var sector: int = posmod(roundi(facing.angle() / (PI / 4.0)), 8)
	var col: int = 7
	if _carry_anim >= 0.0:
		_carry_anim += delta
		var k: int = clampi(int(_carry_anim * CARRY_LIFT_FPS), 0, 7)
		col = k if _carry_dir > 0 else 7 - k
		if _carry_anim >= carry_lift_time():
			_carry_anim = -1.0
			if _carry_dir < 0:
				carry_stone = 0
				_sheet = -1 ## the next _animate puts the normal sheet back
				_sprite.offset = Vector2(0.0, -23.0)
				return
	elif velocity.length() > 5.0:
		var prev_carry_step: int = int(_carry_walk)
		_carry_walk = fposmod(_carry_walk + CARRY_WALK_FPS * clampf(velocity.length() / (max_speed * CARRY_SPEED), 0.4, 1.4) * delta, 8.0)
		var carry_step: int = int(_carry_walk)
		col = 8 + carry_step
		if carry_step != prev_carry_step and carry_step % 4 == 0:
			_on_step()
	else:
		_carry_walk = 0.0
	_sprite.frame_coords = Vector2i(col, sector)


func is_busy() -> bool:
	return _busy or climb.active() or stumbling or fainting or intro != null or story_lock or attack.is_swinging() or attack.is_charging() or swim > 0


## Local player: picks toward `dir` (about a second, she stands still, the weapon is put away);
## `on_grab` runs at the moment the hand closes, when the reward should appear.
func begin_pick(dir: Vector2, on_grab: Callable) -> void:
	_begin_action("pick", dir, on_grab, PICK_GRAB_TIME)


## Local player: pulls a root out of the ground toward `dir`; `on_grab` runs when it gives (and she stumbles back).
func begin_pull(dir: Vector2, on_grab: Callable) -> void:
	_begin_action("pull", dir, on_grab, PULL_GRAB_TIME)


## Local player: lays both palms on something (a waystone statue) toward `dir`; `on_touch` runs when they lie on it. She keeps the hands there until
## `release_touch()` (the statue's light runs over it), then draws back. Hit or stopped: the hold ends by itself after 14 s.
func begin_touch(dir: Vector2, on_touch: Callable) -> void:
	_begin_action("touch", dir, on_touch, TOUCH_TIME)


## Ends the hold of `begin_touch` (any peer may call it for the local player; it is replicated).
func release_touch() -> void:
	if is_multiplayer_authority():
		_play_release_touch.rpc()


@rpc("authority", "call_local", "reliable")
func _play_release_touch() -> void:
	touch_hold = false


## Local player: crouches and holds `item` out toward `dir` (a wild bird that came close). `on_reach` runs when the hand is out; the hold goes on until
## `release_feed()` (the host has answered) or `FEED_HOLD_MAX` seconds.
func begin_feed(dir: Vector2, item: String, on_reach: Callable) -> void:
	_feed_item = item
	_begin_action("feed", dir, on_reach, FEED_REACH_TIME)


## Ends the hold of `begin_feed` (any peer may call it for the local player; it is replicated).
func release_feed() -> void:
	if is_multiplayer_authority():
		_play_release_feed.rpc()


@rpc("authority", "call_local", "reliable")
func _play_release_feed() -> void:
	feed_hold = false


## Local player: eats what is in hotbar slot `slot` (a consumable), if that would do anything. The
## berry is used up when it reaches her mouth (EAT_USE_TIME); being hit before that stops it.
func use_slot(slot: int) -> void:
	if carry_stone != 0 or _busy or climb.active() or stumbling or swim > 0 or attack.is_swinging() or attack.is_charging() or health.current <= 0.0 or slot < 0 or slot >= InventoryComponent.HOTBAR_SIZE:
		return
	var stack: Dictionary = inventory.slots[slot]
	var def: Dictionary = Items.definition(stack)
	var kind: String = String(def.get("kind", ""))
	if stack.is_empty() or (kind != "consumable" and kind != "potion"):
		return
	if not InventoryComponent.usable(self, def):
		get_tree().call_group("hotbar", "deny", slot) ## nothing to heal, or the pause after the last berry / healing potion still runs: keep it
		return
	if kind == "potion":
		var info: Dictionary = AlchemyRules.of(stack)
		_begin_action("drink_%s_%d" % [String(info.get("type", "heal")), int(info.get("tier", 1))], Vector2.ZERO, func() -> void:
			inventory.request("use", [slot, 0])
			_shake = maxf(_shake, 0.8), DRINK_USE_TIME)
		return
	_begin_action("eat", Vector2.ZERO, func() -> void:
		inventory.request("use", [slot, 0])
		_shake = maxf(_shake, 1.2), EAT_USE_TIME)


## Nebelschleier (docs/magie_konzept.md): while the mist veils her, shadow creatures can neither pick her as a target nor keep her as one.
func veiled() -> bool:
	return effects != null and effects.has("veil")


## True while she drinks a potion (busy kind "drink_<type>_<tier>").
func _drinking() -> bool:
	return _busy and (_busy_kind.begins_with("drink") or _busy_kind.begins_with("cast_")) ## a cast, like a draught, only breaks under a heavy blow


## How long the running action lasts: the one-second actions, a potion in 0.6 s.
func _busy_length() -> float:
	if _busy_kind.begins_with("cast_"):
		return SpellRules.cast_timing(_cast_motion()).x
	return DRINK_SECONDS if _busy_kind.begins_with("drink") else PICK_SECONDS


## Local player, magic (docs/magie_konzept.md): the cast motion `cast` ("light": the staff raised and struck on the ground; "root": swept towards
## `target`) toward `dir`; `on_release` runs at `release_time` when the magic leaves the staff. She stands still while she casts. False when she
## cannot start now.
func begin_cast(cast: String, dir: Vector2, target: Vector2, on_release: Callable, release_time: float) -> bool:
	if _busy or climb.active() or swim > 0 or attack.is_swinging() or attack.is_charging() or not is_multiplayer_authority() or health.current <= 0.0:
		return false
	_cast_target = target
	_begin_action("cast_" + cast, dir, on_release, release_time)
	return true


## The cast motion of the running action ("light", "root", "ember", "veil", "maw"); the prong of a forked staff rides after an "@".
func _cast_motion() -> String:
	return _busy_kind.trim_prefix("cast_").get_slice("@", 0)


## Which prong the running cast comes from (0, or 1 for the Bleichgabel's right prong), -1 when she does not cast.
func cast_prong() -> int:
	if not _busy or not _busy_kind.begins_with("cast_"):
		return -1
	return 1 if _busy_kind.ends_with("@1") else 0


## 0..1 the flare of the staff while a cast releases its magic (StaffCrystals), on every peer; with `prong` only for that prong's crystal.
func cast_glow(prong: int = -1) -> float:
	if prong >= 0 and cast_prong() != prong:
		return 0.0
	if not _busy or not _busy_kind.begins_with("cast_"):
		return 0.0
	var release: float = SpellRules.cast_timing(_cast_motion()).y
	return clampf(1.0 - absf(_busy_time - release) / 0.25, 0.0, 1.0) + clampf(_busy_time / maxf(release, 0.01), 0.0, 1.0) * 0.35


## The staff's pose (forward, side, lift in her own frame) for AttackComponent.rod_pose: upright beside her, leaning back in a sprint,
## and through a cast along STAFF_KEYS.
func _staff_pose(moving: bool) -> Vector3:
	if _busy and _busy_kind.begins_with("cast_"):
		var keys: Array = STAFF_KEYS.get(_cast_motion(), []) as Array
		var share: float = clampf(_busy_time / _busy_length(), 0.0, 1.0)
		for k: int in range(1, keys.size()):
			var a: Array = keys[k - 1] as Array
			var b: Array = keys[k] as Array
			if share <= float(b[0]):
				var f: float = (share - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001)
				return (a[1] as Vector3).lerp(b[1] as Vector3, f * f * (3.0 - 2.0 * f))
		return STAFF_REST
	if moving and _gait == 2:
		return STAFF_RUN
	return STAFF_REST


func _begin_action(kind: String, dir: Vector2, on_moment: Callable, moment_time: float) -> void:
	if _busy or climb.active() or swim > 0 or attack.is_swinging() or attack.is_charging() or not is_multiplayer_authority():
		return
	_set_focus(null)
	_play_action.rpc(kind, dir)
	await get_tree().create_timer(moment_time).timeout
	if _busy and _busy_kind == kind and is_inside_tree() and on_moment.is_valid():
		on_moment.call()


@rpc("authority", "call_local", "reliable")
func _play_action(kind: String, dir: Vector2) -> void:
	_busy = true
	_busy_kind = kind
	_busy_time = 0.0
	touch_hold = kind == "touch"
	feed_hold = kind == "feed"
	_touch_wait = 0.0
	sprinting = false
	if dir != Vector2.ZERO:
		facing = dir
	if kind.begins_with("cast_"):
		SpellZone.sound(self, kind.get_slice("@", 0), global_position, -2.0) ## cast_light / cast_root / cast_ember / cast_veil / cast_maw (tools/audio_magic.py)
	if kind.begins_with("drink"):
		var parts: PackedStringArray = kind.split("_")
		_drink_fx.begin(parts[1] if parts.size() > 1 else "heal", int(parts[2]) if parts.size() > 2 else 1)
	elif kind != "eat":
		_walk_time = 0.0


## The camera shakes for a moment (a tree hits the ground nearby).
func add_shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


## 0..1: she glows a moment when the berry takes effect.
func _eat_glow() -> float:
	if not _busy or _busy_kind != "eat":
		return 0.0
	var k: float = (_busy_time - EAT_USE_TIME) / 0.4
	return sin(k * PI) if k > 0.0 and k < 1.0 else 0.0


## Something (a bush) slows her while she is in it; the slowest one counts. Local machine only.
func set_slow(source: Object, factor: float) -> void:
	_slows[source.get_instance_id()] = factor


func clear_slow(source: Object) -> void:
	_slows.erase(source.get_instance_id())


func _slow_factor() -> float:
	var factor: float = 1.0
	for value: float in _slows.values():
		factor = minf(factor, value)
	if effects != null and effects.has("hallucinated"):
		factor *= 0.7 ## hallucinating: 30 % slower
	return factor


## The nearest thing within reach that E can use gets the prompt; E uses it. The group is scanned five times a second; in between the stored
## candidate is only re-checked (still there, usable, in reach), and a press scans again first, so E always uses what is current.
func _update_interact() -> void:
	if _busy:
		climb.hide_prompt()
		return
	var pressed: bool = InputManager.interact_pressed()
	_scan_clock -= get_physics_process_delta_time()
	if _scan_clock <= 0.0 or pressed:
		_scan_clock = INTERACT_SCAN_SECONDS
		_candidate = _scan_interact()
	elif not is_instance_valid(_candidate) or not _candidate_usable(_candidate):
		_candidate = null
	_set_focus(_candidate)
	if _focus != null:
		climb.hide_prompt()
		if pressed:
			_focus.interact(self)
		return
	var direction: Vector2 = InputManager.move_vector()
	if not climb.offer(facing if direction == Vector2.ZERO else direction, pressed) and pressed and _hotbar != null:
		use_slot(_hotbar.selected) ## nothing to use here: E eats from the selected hotbar slot


## The full scan of the interactables group (what `_update_interact` picks up).
func _scan_interact() -> Interactable:
	var best: Interactable = null
	var best_distance: float = Interactable.INTERACT_RANGE
	if InputManager.ui_blocking:
		return null
	for node: Node in get_tree().get_nodes_in_group("interactables"):
		var item: Interactable = node as Interactable
		if item == null:
			continue
		if absf(item.global_position.x - global_position.x) > 48.0 or absf(item.global_position.y - global_position.y) > 48.0:
			continue
		if item.prompt() == "":
			continue
		var distance: float = item.reach_distance(global_position)
		if distance < best_distance:
			best_distance = distance
			best = item
	return best


## The cheap per-frame check of the stored candidate: same rules as `_scan_interact`, for one item.
func _candidate_usable(item: Interactable) -> bool:
	if InputManager.ui_blocking or not item.is_in_group("interactables"):
		return false
	if absf(item.global_position.x - global_position.x) > 48.0 or absf(item.global_position.y - global_position.y) > 48.0:
		return false
	if item.prompt() == "":
		return false
	return item.reach_distance(global_position) < Interactable.INTERACT_RANGE


func _set_focus(item: Interactable) -> void:
	if item == _focus:
		return
	if is_instance_valid(_focus):
		_focus.set_focused(false)
	_focus = item
	if _focus != null:
		_focus.set_focused(true)


## The sword arm is drawn by AttackComponent from these per-frame points (see tools/art_hero3d.py).
func _load_rig() -> void:
	var rig: Dictionary = DataRegistry.table("hero_rig")
	_swim_rig = rig.get("swim", {}) as Dictionary
	_rig_shoulder = _points(rig.get("shoulder", []))
	_rig_hand = _points(rig.get("hand", []))
	_rig_attack_shoulder = _points(rig.get("attack_shoulder", []))
	_rig_attack_hand = _points(rig.get("attack_hand", []))
	_rig_combo_shoulder = _points(rig.get("combo_shoulder", []))
	_rig_combo_hand = _points(rig.get("combo_hand", []))
	_rig_heavy_shoulder = _points(rig.get("heavy_shoulder", []))
	_rig_heavy_hand = _points(rig.get("heavy_hand", []))
	_rig_pick_shoulder = _points(rig.get("pick_shoulder", []))
	_rig_pick_hand = _points(rig.get("pick_hand", []))
	_rig_pull_shoulder = _points(rig.get("pull_shoulder", []))
	_rig_pull_hand = _points(rig.get("pull_hand", []))
	_rig_touch_shoulder = _points(rig.get("touch_shoulder", []))
	_rig_touch_hand = _points(rig.get("touch_hand", []))
	_rig_feed_shoulder = _points(rig.get("feed_shoulder", []))
	_rig_feed_hand = _points(rig.get("feed_hand", []))
	_rig_eat_shoulder = _points(rig.get("eat_shoulder", []))
	_rig_eat_hand = _points(rig.get("eat_hand", []))
	_rig_eat_mouth = _points(rig.get("eat_mouth", []))
	_rig_drink_shoulder = _points(rig.get("drink_shoulder", []))
	_rig_drink_hand = _points(rig.get("drink_hand", []))
	_rig_drink_mouth = _points(rig.get("drink_mouth", []))
	var standby: Dictionary = rig.get("standby", {}) as Dictionary
	_rig_standby_shoulder = _points(standby.get("shoulder", []))
	_rig_standby_hand = _points(standby.get("hand", []))
	_rig_cast_shoulder = _points(rig.get("cast_shoulder", []))
	_rig_cast_hand = _points(rig.get("cast_hand", []))
	if not _rig_cast_hand.is_empty() and ResourceLoader.exists(CAST_SHEET_PATH):
		_cast_sheet = load(CAST_SHEET_PATH) as Texture2D
		_cast_blood = load(CAST_BLOOD_PATH) as Texture2D if ResourceLoader.exists(CAST_BLOOD_PATH) else null


## A list of `[x, y]` pairs from data/hero_rig.json as points.
static func _points(pairs: Variant) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for point: Array in pairs:
		out.append(Vector2(float(point[0]), float(point[1])))
	return out


@rpc("authority", "call_local", "reliable")
func _start_standby(clip: int) -> void:
	if clip < 0 or clip >= STANDBY_CLIPS:
		return
	_standby_clip = clip
	_standby_last = clip
	_standby_time = 0.0
	_standby_wait = -1.0


@rpc("authority", "call_local", "reliable")
func _stop_standby() -> void:
	_standby_clip = -1
	_standby_time = 0.0
	_standby_wait = -1.0


func _cancel_standby() -> void:
	if _standby_clip >= 0 and is_multiplayer_authority() and multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty():
		_stop_standby.rpc()
	else:
		_stop_standby()


func _update_standby(delta: float, moving: bool) -> void:
	var blocked: bool = moving or (fishing != null and fishing.anim != "") or health.current <= 0.0 or stealth.sneaking or _busy or story_lock or intro != null or fainting or stumbling or _is_submerged() or attack.is_in_combat(AttackComponent.OUT_OF_COMBAT)
	if is_multiplayer_authority() and (InputManager.ui_blocking or InputManager.map_open or (InputManager.skills_open or InputManager.progress_open) or InputManager.move_vector() != Vector2.ZERO):
		blocked = true
	if blocked:
		_cancel_standby()
		return
	if _standby_clip >= 0:
		_standby_time += delta * (0.65 if wounded else 1.0)
		if _standby_time >= float(STANDBY_FRAMES) / STANDBY_FPS:
			_stop_standby()
			_idle_time = 0.0
		return
	if not is_multiplayer_authority() or _rig_standby_hand.size() != 8 * STANDBY_COLS or _rig_standby_shoulder.size() != 8 * STANDBY_COLS:
		return
	if _standby_wait < 0.0:
		_standby_wait = _standby_rng.randf_range(4.5, 8.5) if is_heated() else _standby_rng.randf_range(8.0, 16.0)
	_standby_wait = maxf(_standby_wait - delta, 0.0)
	if _standby_wait > 0.0 or int(_idle_time) != 0:
		return
	var clip: int = 0
	if is_heated() and HEAT_STANDBY_CLIP < STANDBY_CLIPS and _standby_last != HEAT_STANDBY_CLIP:
		clip = HEAT_STANDBY_CLIP ## heated in the sun: she wipes the sweat from her brow
	else:
		var pool_n: int = NORMAL_STANDBY_CLIPS
		var prev_normal: int = _standby_last if (_standby_last >= 0 and _standby_last < pool_n) else -1
		clip = _standby_rng.randi_range(0, pool_n - 1) if prev_normal < 0 else _standby_rng.randi_range(0, pool_n - 2)
		if prev_normal >= 0 and clip >= prev_normal:
			clip += 1 ## each next gesture differs from the previous one
	if multiplayer.has_multiplayer_peer() and not multiplayer.get_peers().is_empty():
		_start_standby.rpc(clip)
	else:
		_start_standby(clip)


## Swimming has its own sheet (13): looping tread / breaststroke / crawl, the clips between them and the way into the water, which plays
## backwards when she climbs out. Returns true while the swim sheet is drawn.
func _animate_swim(delta: float) -> bool:
	var clips: Dictionary = _swim_rig.get("clips", {}) as Dictionary
	var total: int = int(_swim_rig.get("total", 0))
	if clips.is_empty() or total <= 0:
		return false
	var enter: Dictionary = clips["enter"] as Dictionary
	var idx: int = -1
	var start: int = 0
	if swim > 0:
		_swim_exit_t = -1.0
		var want: int = swim - 1
		if _swim_was == 0:
			_swim_level = 0
			_swim_time = 0.0
			_swim_dive = velocity.length() > max_speed * 1.2 ## a run into the water: a head-first dive instead of wading in
			_swim_trans = "dive" if _swim_dive else "enter"
			_swim_trans_t = 0.0
			_swim_trans_dir = 1
			_swim_shake_t = -1.0
			_use_sheet(13)
			_swim_water.splash(global_position, 18 if _swim_dive else 10, 1.8 if _swim_dive else 1.3, true)
			_swim_sound("dive_big" if _swim_dive else "dive_small", 0.0)
			if _swim_dive:
				_shake = maxf(_shake, 1.5)
			if is_multiplayer_authority():
				get_tree().call_group("hint_card", "notify_swim")
		elif _swim_trans == "" and want != _swim_level:
			var up: bool = want > _swim_level
			_swim_trans = "t2b" if (_swim_level if up else _swim_level - 1) == 0 else "b2c"
			_swim_trans_dir = 1 if up else -1
			var tc: Dictionary = clips[_swim_trans] as Dictionary
			_swim_trans_t = 0.0 if up else float(tc["count"]) / float(tc["fps"]) - 0.0001
		_swim_was = swim
	elif _swim_was > 0:
		_swim_was = 0
		_swim_trans = ""
		_swim_exit_t = 0.0
		if _swim_water != null:
			_swim_water.splash(global_position, 6, 1.0, true)
			_swim_sound("exit", 0.0)
	if swim == 0:
		if _swim_shake_t >= 0.0:
			var sc: Dictionary = clips["shake"] as Dictionary
			var before: int = int(_swim_shake_t * float(sc["fps"]))
			_swim_shake_t += delta
			var at: int = int(_swim_shake_t * float(sc["fps"]))
			if velocity.length() > 8.0 or at >= int(sc["count"]):
				_swim_shake_t = -1.0
				_wet_drip = 0.0
				return false
			if at != before and at in [3, 6, 8]: ## the head and the coat throw water
				_swim_sound("shake" if at == 3 else "drip", -2.0 if at == 3 else -6.0)
				_swim_water.splash(global_position + Vector2(randf_range(-6.0, 6.0), 0.0), 5, 0.9, false, 18.0)
			idx = int(sc["start"]) + at
			_use_sheet(13)
			_swim_under.visible = false
			_sprite.frame = _sector * total + idx
			_sprite.skew = 0.0
			_sprite.position.y = 0.0
			return true
		if _swim_exit_t < 0.0:
			return false
		_swim_exit_t += delta
		var n: int = int(enter["count"])
		var back: int = n - 1 - int(_swim_exit_t * float(enter["fps"]) * 2.0) ## twice as fast as the way in
		if back < 0:
			_swim_exit_t = -1.0
			if _swim_swum > 2.0 and velocity.length() < 8.0:
				_swim_shake_t = 0.0 ## she stands: shake the water off
			_swim_swum = 0.0
			return false
		idx = int(enter["start"]) + back
	elif _swim_trans != "":
		var c: Dictionary = clips[_swim_trans] as Dictionary
		var span: float = float(c["count"]) / float(c["fps"])
		_swim_trans_t += float(_swim_trans_dir) * delta
		if (_swim_trans_dir > 0 and _swim_trans_t >= span) or (_swim_trans_dir < 0 and _swim_trans_t <= 0.0):
			if _swim_trans_dir > 0:
				_swim_level = 0 if _swim_trans in ["enter", "dive"] else (1 if _swim_trans == "t2b" else 2)
			else:
				_swim_level = 0 if _swim_trans == "t2b" else 1
			_swim_trans = ""
			_swim_time = 0.0
		else:
			idx = int(c["start"]) + clampi(int(_swim_trans_t * float(c["fps"])), 0, int(c["count"]) - 1)
	if idx < 0:
		var loop: Dictionary = clips[SWIM_LEVELS[_swim_level]] as Dictionary
		_swim_time += delta
		start = int(loop["start"])
		idx = start + int(_swim_time * float(loop["fps"])) % int(loop["count"])
	_use_sheet(13)
	_sprite.frame = _sector * total + idx
	_swim_under.frame = _sprite.frame
	_swim_effects(delta, clips, idx, total)
	_sprite.skew = 0.0
	_sprite.position.y = 0.0
	return true


## Water effects of the swim frames: arms and kicks throw drops at the events of the rig, the crawl blows bubbles at the mouth, the wake leaves rings.
func _swim_effects(delta: float, clips: Dictionary, idx: int, total: int) -> void:
	var level: float = float(swimmer.blend) if swim > 0 else maxf(0.0, 1.0 - _swim_exit_t * 3.0)
	var hard: float = 1.0 if swim == SwimRules.CRAWL else (0.5 if swim == SwimRules.BREAST else 0.15)
	_swim_water.energy = lerpf(_swim_water.energy, hard, minf(1.0, 6.0 * delta))
	_swim_water.intensity = level
	_swim_water.moving = swim > 1 and velocity.length() > 5.0
	if velocity.length() > 5.0:
		_swim_water.heading = velocity.normalized()
	(_swim_under.material as ShaderMaterial).set_shader_parameter("energy", _swim_water.energy)
	if swim == 0 or _swim_trans != "":
		_swim_last_local = -1
		return
	var clip_name: String = SWIM_LEVELS[_swim_level]
	var loop: Dictionary = clips[clip_name] as Dictionary
	var local: int = idx - int(loop["start"])
	var points: Dictionary = _swim_rig.get("points", {}) as Dictionary
	if local != _swim_last_local:
		_swim_last_local = local
		var events: Dictionary = (_swim_rig.get("events", {}) as Dictionary).get(clip_name, {}) as Dictionary
		for side: String in ["l", "r"]:
			if local in (events.get("enter_" + side, []) as Array):
				var arr: Array = ((points.get("hand_" + side, []) as Array)[_sector] as Array)
				if idx < arr.size():
					var hp: Array = arr[idx] as Array
					_swim_water.splash(global_position + Vector2(float(hp[0]), float(hp[1]) * 0.3), 3 + int(3.0 * _swim_water.energy), 0.7 + _swim_water.energy * 0.6)
					_swim_sound("stroke_a" if side == "l" else "stroke_b", float((SwimRules.cfg().get("sounds", {}) as Dictionary).get("stroke_db", -14.0)) + 4.0 * _swim_water.energy, 1.0 + 0.25 * _swim_water.energy)
					if swim == SwimRules.TREAD:
						_ripples.add(global_position + Vector2(float(hp[0]), 2.0), 0.5)
	_swim_stir -= delta
	if _swim_stir <= 0.0 and (not multiplayer.has_multiplayer_peer() or multiplayer.is_server()):
		_swim_stir = 1.5
		FishingComponent.add_pressure(global_position, 0.14 if swim == SwimRules.CRAWL else (0.07 if swim == SwimRules.BREAST else 0.02)) ## fish do not like swimmers
	_swim_wake -= delta
	if _swim_wake <= 0.0 and velocity.length() > 5.0:
		_swim_wake = 0.32 - 0.14 * _swim_water.energy
		_ripples.add(global_position - velocity.normalized() * 6.0, 0.55 + 0.6 * _swim_water.energy)
	_swim_drip -= delta
	if swim == SwimRules.CRAWL and _swim_drip <= 0.0:
		_swim_drip = 0.55
		var mouth: Array = ((points.get("mouth", []) as Array)[_sector] as Array)
		if idx < mouth.size():
			var mp: Array = mouth[idx] as Array
			_swim_water.bubble(global_position + Vector2(float(mp[0]), float(mp[1]) * 0.3))
			_swim_sound("breath", -12.0)


## Picks the sheet frame: walk or sprint cycle while moving, idle loop while standing.
## The gait the speed asks for (0 walk, 1 jog, 2 sprint) and the switch to it after a short hold. Every peer decides it from the
## synced velocity, so a sprint throttled by mist, a slow surface or a heavy load jogs everywhere alike; sneaking always walks.
func _pick_gait(delta: float, sprint_held: bool) -> void:
	var speed: float = velocity.length()
	var want: int = 0
	if not stealth.sneaking and swim == 0:
		var margin: float = 4.0 * (1.0 if _gait == 0 else -1.0) ## hysteresis: leaving a gait needs a few px/s more than entering it
		if speed >= sprint_speed * sprint_from + (4.0 if _gait < 2 else -4.0) and (sprint_held or speed > sprint_speed * 1.05):
			want = 2
		elif speed >= max_speed * jog_from + margin:
			want = 1
	if want == _gait:
		_gait_hold = 0.0
		return
	_gait_hold += delta
	if _gait_hold >= 0.08:
		_gait = want
		_gait_hold = 0.0


## Cycle frames per second for the gait on screen, scaled by the real speed (slow surfaces slow the legs too).
func _gait_cadence() -> float:
	var speed: float = velocity.length()
	match _gait:
		2:
			return jog_fps * clampf(speed / maxf(sprint_speed, 0.01), 0.6, 1.65)
		1:
			return trot_fps * clampf(speed / maxf((max_speed + sprint_speed) * 0.5, 0.01), 0.7, 1.4)
	return walk_fps * clampf(speed / maxf(max_speed, 0.01), 0.5, 2.0)


## True near the two passing frames of a cycle (1.5 and 4.5), where her feet are under her: a stride may end there.
static func _feet_together(phase: float) -> bool:
	var u: float = fposmod(phase, 3.0)
	return absf(u - 1.6) < 0.45


func _animate(delta: float) -> void:
	if climb.active():
		_cancel_standby()
		_use_sheet(CLIMB_SHEET)
		_sprite.frame_coords = climb.frame()
		_sprite.position = climb.sprite_offset()
		_sprite.skew = 0.0
		return
	if _sheet == CLIMB_SHEET:
		_sprite.position.x = 0.0
	if _step_t >= 0.0:
		_animate_step(delta)
		return
	if carry_stone != 0:
		_animate_carry(delta)
		return
	if _sheet == STEP_SHEET_ID:
		_sprite.position.x = 0.0
	var angle: float = facing.angle() / (PI / 4.0)
	if absf(wrapf(angle - float(_sector), -4.0, 4.0)) > 0.62: ## hysteresis: no flicker on sector borders
		_sector = posmod(roundi(angle), 8)

	var moving: bool = velocity.length() > 5.0
	var running: bool = moving and sprinting and not stealth.sneaking
	var col: int
	if moving:
		var direction: float = -1.0 if velocity.dot(facing) < 0.0 else 1.0 ## walking backwards plays in reverse
		if _last_step < 0 and _settle <= 0.0:
			_walk_time = 1.0 ## setting off: the first frame is the push-off, not a wide-legged stride out of the idle stance
			_cadence = 0.0
		_settle = 0.0
		_pick_gait(delta, running)
		var target_fps: float = _gait_cadence()
		_cadence = target_fps if _cadence <= 0.0 else lerpf(_cadence, target_fps, 1.0 - exp(-10.0 * delta))
		var limp_k: float = 1.0 + 0.6 * sin(TAU * _walk_time / float(WALK_FRAMES) + 0.6) if wounded else 1.0 ## the good leg swings quickly, the bad one is dragged
		_walk_time = fposmod(_walk_time + direction * _cadence * limp_k * delta, float(WALK_FRAMES))
		var step: int = int(_walk_time)
		col = [0, JOG_COL, RUN_COL][_gait] + step
		if step != _last_step and step % (WALK_FRAMES / 2) == 0: ## the two contact frames of the cycle
			_on_step()
		_last_step = step
		_idle_time = 0.0
	elif _last_step >= 0 and _settle < GAIT_SETTLE and not _feet_together(_walk_time):
		## stopping mid-stride: the cycle runs on (at least at walking pace) until the feet pass under her, then the idle loop takes over
		_settle += delta
		_walk_time = fposmod(_walk_time + maxf(_cadence, walk_fps) * delta, float(WALK_FRAMES))
		col = [0, JOG_COL, RUN_COL][_gait] + int(_walk_time)
	else:
		_walk_time = 0.0
		_last_step = -1
		_settle = 0.0
		_gait = 0
		_gait_hold = 0.0
		_cadence = 0.0
		_idle_time = fposmod(_idle_time + IDLE_FPS * (0.6 if wounded else 1.0) * delta, float(IDLE_FRAMES)) ## slow, heavy breathing when wounded
		col = IDLE_COL + int(_idle_time)
	var was_standby: bool = _standby_clip >= 0
	_update_standby(delta, moving)
	if was_standby and _standby_clip < 0 and not moving:
		col = IDLE_COL ## the gesture ends on exactly this breathing frame
	var main_frame: int = (_sector + (8 if stealth.sneaking else 0)) * SHEET_COLS + col
	_animate_limp(delta, moving)
	_sprite.position.y = _sink + _limp_dip
	var shoulder: Vector2 = Vector2(-4.0, -31.0)
	var hand: Vector2 = Vector2(-5.0, -21.0)
	var free_hand: bool = false ## the main sheet plays: the held item may move the fist to its own hold (AttackComponent / GripRig)
	var arm_tex0: String = "player.png"
	var arm_tex1: String = "player.png"
	var arm_f0: int = main_frame
	var arm_f1: int = main_frame
	var arm_blend: float = 0.0
	if main_frame < _rig_hand.size():
		shoulder = _rig_shoulder[main_frame]
		hand = _rig_hand[main_frame]
	if _busy:
		var holding: bool = (_busy_kind == "touch" and touch_hold and _busy_time >= TOUCH_HOLD_AT) or (_busy_kind == "feed" and feed_hold and _busy_time >= FEED_REACH_TIME)
		if holding:
			_touch_wait += delta
			if _touch_wait > (FEED_HOLD_MAX if _busy_kind == "feed" else 14.0):
				touch_hold = false
				feed_hold = false
		else:
			_busy_time += delta
		if _busy_time >= _busy_length():
			_busy = false
	var fish_frame: Dictionary = fishing.body_frame(_sector, moving) if fishing != null and not _busy else {}
	var fish_frame_ok: bool = not fish_frame.is_empty() and not attack.is_swinging()
	if not fish_frame_ok:
		attack.rod_pose = Vector3.INF
	var swim_drawn: bool = _animate_swim(delta)
	# The ring of water behind her lives only in the water or on the way out; the climb-out clip can end before its fade did, or the shake takes over.
	if _swim_water != null and _swim_water.intensity > 0.0 and swim == 0 and _swim_exit_t < 0.0:
		_swim_water.intensity = 0.0
		_swim_water.queue_redraw()
		_swim_water._back.queue_redraw()
	if swim_drawn:
		shoulder = Vector2(0.0, -30.0) ## the sheet already shows both arms; the sword arm is hidden below
		hand = Vector2(0.0, -22.0)
		arm_tex0 = ""
		arm_tex1 = ""
	elif _busy and _busy_kind.begins_with("cast_") and _cast_sheet != null:
		## Casting (docs/magie_konzept.md): its own sheet, legs planted; the right arm holds the staff from the rig, the staff's angle follows STAFF_KEYS.
		var clip: int = maxi(CAST_CLIPS.find(_cast_motion()), 0)
		var cast_pos: float = _busy_time / _busy_length() * float(PICK_FRAMES)
		var cast_key: float = clampf(cast_pos - 0.5, 0.0, float(PICK_FRAMES - 1) - 0.001)
		var ci: int = int(cast_key)
		var cf: float = cast_key - float(ci)
		var cast_base: int = (_sector * CAST_CLIPS.size() + clip) * PICK_FRAMES
		_use_sheet(CAST_SHEET_ID)
		_sprite.frame = cast_base + clampi(int(cast_pos), 0, PICK_FRAMES - 1)
		hand = _rig_cast_hand[cast_base + ci].lerp(_rig_cast_hand[cast_base + ci + 1], cf)
		shoulder = _rig_cast_shoulder[cast_base + ci].lerp(_rig_cast_shoulder[cast_base + ci + 1], cf)
		arm_tex0 = "player_cast.png"
		arm_tex1 = "player_cast.png"
		arm_f0 = cast_base + ci
		arm_f1 = cast_base + ci + 1
		arm_blend = cf
	elif _busy and not _rig_pick_hand.is_empty() and not _rig_eat_hand.is_empty():
		## Picking and eating have their own sheets too (legs planted); the right arm is drawn from the rig, weapon put away.
		var position_in_sheet: float = _busy_time / _busy_length() * float(PICK_FRAMES)
		var key: float = clampf(position_in_sheet - 0.5, 0.0, float(PICK_FRAMES - 1) - 0.001)
		var i: int = int(key)
		var f: float = key - float(i)
		var drinking: bool = _busy_kind.begins_with("drink") and not _rig_drink_hand.is_empty()
		var eating: bool = _busy_kind == "eat" or drinking ## both have 7 leg variants
		var legs: int = 1 + clampi(int(_walk_time), 0, WALK_FRAMES - 1) if moving and eating else 0 ## eating while walking keeps the walk cycle's legs
		var base: int = _sector * PICK_FRAMES * (EAT_VARIANTS if eating else 1) + legs * PICK_FRAMES
		var pulling: bool = _busy_kind == "pull" and not _rig_pull_hand.is_empty()
		var touching: bool = _busy_kind == "touch" and not _rig_touch_hand.is_empty()
		var feeding: bool = _busy_kind == "feed" and not _rig_feed_hand.is_empty()
		var hands: PackedVector2Array = _rig_drink_hand if drinking else _rig_feed_hand if feeding else _rig_eat_hand if eating else (_rig_touch_hand if touching else (_rig_pull_hand if pulling else _rig_pick_hand))
		var shoulders: PackedVector2Array = _rig_drink_shoulder if drinking else _rig_feed_shoulder if feeding else _rig_eat_shoulder if eating else (_rig_touch_shoulder if touching else (_rig_pull_shoulder if pulling else _rig_pick_shoulder))
		var busy_tex: String = "player_drink.png" if drinking else ("player_feed.png" if feeding else ("player_eat.png" if eating else ("player_touch.png" if touching else ("player_pull.png" if pulling else "player_pick.png"))))
		_use_sheet(DRINK_SHEET_ID if drinking else 14 if feeding else 3 if eating else (5 if touching else (4 if pulling else 2)))
		_sprite.frame = base + clampi(int(position_in_sheet), 0, PICK_FRAMES - 1)
		hand = hands[base + i].lerp(hands[base + i + 1], f)
		shoulder = shoulders[base + i].lerp(shoulders[base + i + 1], f)
		arm_tex0 = busy_tex
		arm_tex1 = busy_tex
		arm_f0 = base + i
		arm_f1 = base + i + 1
		arm_blend = f
		if drinking:
			var lips: Vector2 = _rig_drink_mouth[base + i].lerp(_rig_drink_mouth[base + i + 1], f)
			_drink_fx.show_state(_busy_time, hand + Vector2(0.0, _sink), lips + Vector2(0.0, _sink), facing)
		elif eating:
			var mouth: Vector2 = _rig_eat_mouth[base + i].lerp(_rig_eat_mouth[base + i + 1], f)
			_eat_fx.show_state(_busy_time, hand + Vector2(0.0, _sink), mouth + Vector2(0.0, _sink))
		if feeding and _busy_time >= 0.22:
			_feed_fx.show_hand(_feed_item, hand + Vector2(0.0, _sink))
	elif attack.heavy_key() >= 0.0 and not _rig_heavy_hand.is_empty():
		## The heavy blow (charge, chop, recover) has its own sheet: 10 keys, legs planted or following the walk cycle.
		var heavy: float = clampf(attack.heavy_key(), 0.0, float(HEAVY_KEYS - 1) - 0.001)
		var hi: int = int(heavy)
		var hf: float = heavy - float(hi)
		var heavy_legs: int = 1 + clampi(int(_walk_time), 0, WALK_FRAMES - 1) if moving and not attack.is_heavy_swing() else 0
		var heavy_base: int = _sector * HEAVY_COLS + heavy_legs * HEAVY_KEYS
		_use_sheet(11)
		_sprite.frame = heavy_base + (hi + 1 if hf >= 0.5 else hi)
		hand = _rig_heavy_hand[heavy_base + hi].lerp(_rig_heavy_hand[heavy_base + hi + 1], hf)
		shoulder = _rig_heavy_shoulder[heavy_base + hi].lerp(_rig_heavy_shoulder[heavy_base + hi + 1], hf)
		arm_tex0 = "player_heavy.png"
		arm_tex1 = "player_heavy.png"
		arm_f0 = heavy_base + hi
		arm_f1 = heavy_base + hi + 1
		arm_blend = hf
	elif attack.is_swinging() and not _rig_attack_hand.is_empty():
		## The swing has its own sheet: upper body from the keyframe, legs planted while she stands and
		## following the walk cycle while she moves.
		var swing: Vector2 = attack.animation_state() ## x: which attack (3 and 4 = the learned combo steps), y: keyframe position (-1 winding up .. 5)
		var legs: int = 1 + clampi(int(_walk_time), 0, WALK_FRAMES - 1) if moving else 0
		var learned_step: bool = swing.x >= 3.0 and not _rig_combo_hand.is_empty() ## the 4th / 5th strike have their own sheet
		var base: int = _sector * COMBO_COLS + ((int(swing.x) - 3) * ATTACK_LEGS + legs) * ATTACK_FRAMES if learned_step else _sector * ATTACK_COLS + (mini(int(swing.x), 2) * ATTACK_LEGS + legs) * ATTACK_FRAMES
		var swing_hands: PackedVector2Array = _rig_combo_hand if learned_step else _rig_attack_hand
		var swing_shoulders: PackedVector2Array = _rig_combo_shoulder if learned_step else _rig_attack_shoulder
		var swing_tex: String = "player_combo.png" if learned_step else "player_attack.png"
		var key: float = swing.y
		var i: int = clampi(int(maxf(key, 0.0)), 0, ATTACK_FRAMES - 2)
		var f: float = maxf(key, 0.0) - float(i)
		_use_sheet(12 if learned_step else 1)
		_sprite.frame = base + clampi(int(maxf(key, 0.0)), 0, ATTACK_FRAMES - 1)
		var to_hand: Vector2 = swing_hands[base + i].lerp(swing_hands[base + i + 1], f)
		var to_shoulder: Vector2 = swing_shoulders[base + i].lerp(swing_shoulders[base + i + 1], f)
		if key < 0.0: ## winding up: from where the hand was into the first keyframe
			to_hand = hand.lerp(swing_hands[base], key + 1.0)
			to_shoulder = shoulder.lerp(swing_shoulders[base], key + 1.0)
			arm_tex0 = "player.png"
			arm_f0 = main_frame
			arm_tex1 = swing_tex
			arm_f1 = base
			arm_blend = key + 1.0
		else:
			arm_tex0 = swing_tex
			arm_f0 = base + i
			arm_tex1 = swing_tex
			arm_f1 = base + i + 1
			arm_blend = f
		hand = to_hand
		shoulder = to_shoulder
	elif fish_frame_ok:
		_use_sheet(10)
		_sprite.frame = int(fish_frame["frame"])
		hand = fish_frame["hand"] as Vector2
		shoulder = fish_frame["shoulder"] as Vector2
		attack.rod_pose = fish_frame["rod"] as Vector3
		arm_tex0 = "player_fish.png"
		arm_tex1 = "player_fish.png"
		arm_f0 = int(fish_frame["frame"])
		arm_f1 = arm_f0
		arm_blend = 0.0
	elif _standby_clip >= 0:
		var key: float = clampf(_standby_time * STANDBY_FPS, 0.0, float(STANDBY_FRAMES - 1))
		var i: int = int(key)
		var next: int = mini(i + 1, STANDBY_FRAMES - 1)
		var base: int = _sector * STANDBY_COLS + _standby_clip * STANDBY_FRAMES
		_use_sheet(9)
		_sprite.frame = base + i
		hand = _rig_standby_hand[base + i].lerp(_rig_standby_hand[base + next], key - float(i))
		shoulder = _rig_standby_shoulder[base + i].lerp(_rig_standby_shoulder[base + next], key - float(i))
		arm_tex0 = "player_standby.png"
		arm_tex1 = "player_standby.png"
		arm_f0 = base + i
		arm_f1 = base + next
		arm_blend = key - float(i)
	else:
		_use_sheet(0)
		_sprite.frame = main_frame
		free_hand = not swim_drawn
	if not (_busy and _busy_kind == "eat"):
		_eat_fx.clear()
	if not _drinking():
		_drink_fx.clear()
	if not (_busy and _busy_kind == "feed"):
		_feed_fx.clear()
	var vert_dy: float = _sink + _limp_dip
	attack.rig_shoulder = shoulder + Vector2(-_sprite.skew * shoulder.y, vert_dy)
	attack.rig_hand = hand + Vector2(-_sprite.skew * hand.y, vert_dy)
	var a3_0: Array[Vector3] = GripRig.frame_arm3(arm_tex0, arm_f0)
	var a3_1: Array[Vector3] = GripRig.frame_arm3(arm_tex1, arm_f1)
	attack.rig_arm3 = GripRig.shift_arm3(GripRig.blend_arm3(a3_0, a3_1, arm_blend), _sprite.skew, vert_dy)
	var blood_tex: Texture2D = (_sprite.material as ShaderMaterial).get_shader_parameter("blood_map") as Texture2D
	var dsrc: Dictionary = ArmPainter.depth_source(blood_tex)
	if bool(dsrc.get("valid", false)) and _sprite.hframes > 0 and _sprite.vframes > 0:
		var cw: int = int(dsrc["w"]) / _sprite.hframes
		var ch: int = int(dsrc["h"]) / _sprite.vframes
		var col_i: int = _sprite.frame % _sprite.hframes
		var row_i: int = _sprite.frame / _sprite.hframes
		attack.depth_ctx = {
			"valid": true,
			"tex_id": blood_tex.get_instance_id() % 1000000,
			"bytes": dsrc["bytes"],
			"w": dsrc["w"],
			"h": dsrc["h"],
			"cell_x": col_i * cw,
			"cell_y": row_i * ch,
			"cell_w": cw,
			"cell_h": ch,
			"foot_x": roundi(float(cw) * 0.5 - _sprite.offset.x),
			"foot_y": roundi(float(ch) * 0.5 - _sprite.offset.y),
			"skew": _sprite.skew,
			"dy": vert_dy,
			"arm_style": appearance.arm_style() if appearance != null else "default",
			"arm_tint": appearance.arm_tint() if appearance != null else Color.WHITE,
			"arm_token": appearance.arm_pose_token() if appearance != null else 0.0,
		}
	else:
		attack.depth_ctx = {
			"arm_style": appearance.arm_style() if appearance != null else "default",
			"arm_tint": appearance.arm_tint() if appearance != null else Color.WHITE,
			"arm_token": appearance.arm_pose_token() if appearance != null else 0.0,
		}
	attack.carrying = moving and _gait == 2 and not attack.is_swinging() ## the blade trails back only in the real sprint
	attack.body_dir = Vector2.from_angle(float(_sector) * PI / 4.0) ## the item rests relative to the facing the sheet shows, not the cursor
	attack.free_hand = free_hand
	attack.mirror_material(_sprite.material)
	attack.sheathed = stealth.sneaking or (_busy and not _busy_kind.begins_with("cast_")) or swim_drawn ## sneaking, picking and swimming put the weapon away (a cast needs the staff)
	if attack.holds_staff() and not fish_frame_ok:
		attack.rod_pose = _staff_pose(moving)
	if attack.arm_shown() == swim_drawn:
		attack.set_arm_shown(not swim_drawn) ## swim frames carry both arms


## The intro starts: normal HUD parts hide, the wound border and blood stay active.
func begin_intro(scene: Node) -> void:
	intro = scene
	facing = Vector2.RIGHT
	_sector = 0
	if _hud != null:
		_hud.call("begin_intro")
	_main_sheet_restore()


## One frame of the emerge sheet, and where she stands (the intro calls this every frame).
func show_emerge_frame(texture: Texture2D, frames: int, frame: int, at: Vector2, blood_map: Texture2D = EMERGE_BLOOD, sprite_offset: Vector2 = Vector2(0.0, -13.0)) -> void:
	if _sheet != 4 or _sprite.texture != texture:
		_sheet = 4
		(_sprite.material as ShaderMaterial).set_shader_parameter("blood_map", blood_map)
		_sprite.texture = texture
		_sprite.hframes = frames
		_sprite.vframes = 1
		_sprite.offset = sprite_offset ## the emerge frames are 76 high (the shaft below her feet), feet at row 51
	_sprite.frame = frame
	_sprite.position.y = 0.0
	global_position = at


## She trips (the story's footpath, `StumbleGuide`): the foot catches, the knee gives, she lands on her hands and knees, stays there a moment,
## pushes up and walks on. Owner only; every peer plays it (`_play_stumble`). Not while she is busy, in a cutscene or hurt to death.
func begin_stumble() -> bool:
	if stumbling or intro != null or story_lock or fainting or _busy or climb.active() or attack.is_swinging() or attack.is_charging() or health.current <= 0.0 or not is_multiplayer_authority():
		return false
	_play_stumble.rpc(_sector)
	return true


@rpc("authority", "call_local", "reliable")
func _play_stumble(sector: int) -> void:
	stumbling = true
	_stumble_time = 0.0
	_stumble_phase = 0
	_stumble_wait = 0.0
	_stumble_cough_at = 1.4
	_stumble_fired.clear()
	_sector = sector
	sprinting = false
	stealth.sneaking = false
	_sheet = 6
	(_sprite.material as ShaderMaterial).set_shader_parameter("blood_map", STUMBLE_BLOOD)
	_sprite.texture = STUMBLE_SHEET
	var rig: Dictionary = (DataRegistry.table("hero_rig").get("stumble", {}) as Dictionary)
	_sprite.hframes = int(rig.get("frames", 1))
	_sprite.vframes = 8
	_sprite.offset = Vector2(0.0, -13.0)


## Phases: 0 she falls (until `hold`), 1 she stays on her hands and knees, breathing, until she presses E (`rise`), 2 she gets up.
func _update_stumble(delta: float) -> void:
	var rig: Dictionary = (DataRegistry.table("hero_rig").get("stumble", {}) as Dictionary)
	var fps: float = float(rig.get("fps", 24))
	var frames: int = int(rig.get("frames", 1))
	var events: Dictionary = rig.get("events", {}) as Dictionary
	var hold_at: float = float(events.get("hold", 0.7))
	var rise_at: float = float(events.get("rise", 1.15))
	var frame: int
	if _stumble_phase == 1:
		_stumble_wait += delta
		var first: int = int(hold_at * fps)
		var last: int = int(rise_at * fps) - 1
		var span: int = maxi(last - first, 1)
		var step: int = int(_stumble_wait * 9.0) % (span * 2) ## breathing: back and forth over the held frames
		frame = first + (step if step <= span else span * 2 - step)
		if _stumble_wait > 1.0 and _stumble_prompt == null: ## "E GET UP" hangs over her
			_stumble_prompt = InteractPrompt.new()
			_stumble_prompt.position = Vector2(0, -44)
			add_child(_stumble_prompt)
			_stumble_prompt.show_text("AUFSTEHEN")
		if is_multiplayer_authority() and _stumble_wait > 0.7 and InputManager.interact_pressed():
			_stumble_rise.rpc()
	else:
		_stumble_time += delta
		if _stumble_phase == 0 and _stumble_time >= hold_at:
			_stumble_phase = 1
			_stumble_wait = 0.0
			_stumble_time = hold_at
		frame = mini(int(_stumble_time * fps), frames - 1)
	_sprite.frame = _sector * frames + frame
	_sprite.position.y = 0.0
	for event_name: String in events:
		if _stumble_phase != 1 and _stumble_time >= float(events[event_name]) and not _stumble_fired.has(event_name):
			_stumble_fired[event_name] = true
			_stumble_event(event_name)
	if _stumble_phase == 1 and _stumble_wait >= _stumble_cough_at:
		_stumble_cough_at += 3.4
		_stumble_event("cough")
	if _stumble_phase == 2 and _stumble_time >= float(rig.get("duration", 2.0)):
		stumbling = false
		_sheet = -1 ## the next _animate puts the normal sheet back
		_sprite.offset = Vector2(0.0, -23.0)


## E: she pushes herself up (every peer plays the rest of the animation).
@rpc("authority", "call_local", "reliable")
func _stumble_rise() -> void:
	if not stumbling or _stumble_phase != 1:
		return
	_stumble_phase = 2
	var rig: Dictionary = (DataRegistry.table("hero_rig").get("stumble", {}) as Dictionary)
	var events: Dictionary = rig.get("events", {}) as Dictionary
	_stumble_time = float(events.get("rise", 1.15))
	for event_name: String in events:
		if float(events[event_name]) <= _stumble_time:
			_stumble_fired[event_name] = true
	if _stumble_prompt != null:
		_stumble_prompt.queue_free()
		_stumble_prompt = null
	_stumble_event("gasp")


func _stumble_event(event_name: String) -> void:
	if STUMBLE_SOUNDS.has(event_name):
		var sound: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
		sound.stream = STUMBLE_SOUNDS[event_name] as AudioStream
		sound.volume_db = -8.0 if event_name != "thud" else -4.0
		sound.max_distance = 360.0
		add_child(sound)
		sound.finished.connect(sound.queue_free)
		sound.play()
	match event_name:
		"gasp":
			_shake = maxf(_shake, 1.0)
		"thud":
			_shake = maxf(_shake, 3.0)
			_dash_dust.direction = Vector2.UP
			_dash_dust.restart()
			BloodSplat.drop(get_tree().current_scene, global_position + Vector2(randf_range(-6.0, 6.0), randf_range(-2.0, 3.0)), 2)
			BloodSplat.drop(get_tree().current_scene, global_position + Vector2(randf_range(-6.0, 6.0), randf_range(-2.0, 3.0)), 1)
		"cough":
			_shake = maxf(_shake, 1.2)
			BloodSplat.drop(get_tree().current_scene, global_position + Vector2(randf_range(-4.0, 4.0), randf_range(0.0, 3.0)), 1)


## One frame of the faint sheet; west uses its own rendered row.
func show_faint_frame(frame: int, flip: bool) -> void:
	if _sheet != 5:
		_sheet = 5
		fainting = true
		(_sprite.material as ShaderMaterial).set_shader_parameter("blood_map", FAINT_BLOOD)
		_sprite.texture = FAINT_SHEET
		_sprite.hframes = int(FAINT_SHEET.get_width() / 72.0)
		_sprite.vframes = 2
		_sprite.offset = Vector2(0.0, -13.0)
	_sprite.frame_coords = Vector2i(frame, 1 if flip else 0)
	_sprite.flip_h = false
	_sprite.position.y = 0.0


## One story-sitting frame; each direction has its own rendered row.
func show_sit_frame(frame: int, sector: int) -> void:
	if _sheet != 6:
		_sheet = 6
		fainting = true
		(_sprite.material as ShaderMaterial).set_shader_parameter("blood_map", SIT_BLOOD)
		_sprite.texture = SIT_SHEET
		_sprite.hframes = int(SIT_SHEET.get_width() / 72.0)
		_sprite.vframes = 8
		_sprite.offset = Vector2(0.0, -13.0)
	_sprite.frame_coords = Vector2i(frame, clampi(sector, 0, 7))
	_sprite.flip_h = false
	_sprite.position.y = 0.0


## Free sitting uses an independently rendered row for each facing.
func show_rest_frame(frame: int, row: int) -> void:
	if _sheet != 8:
		_sheet = 8
		fainting = true
		(_sprite.material as ShaderMaterial).set_shader_parameter("blood_map", RestComponent.BLOOD)
		_sprite.texture = RestComponent.SHEET
		var rig: Dictionary = DataRegistry.table("hero_rig").rest as Dictionary
		_sprite.hframes = int(rig.cols)
		_sprite.vframes = int(rig.rows)
		_sprite.offset = Vector2(0, -13)
	_sprite.frame_coords = Vector2i(frame, row)
	_sprite.flip_h = false
	_sprite.position.y = 0.0


## One frame of the carry sheet; west uses its own rendered row.
func show_carry_frame(frame: int, flip: bool) -> void:
	if _sheet != 7:
		_sheet = 7
		fainting = true
		(_sprite.material as ShaderMaterial).set_shader_parameter("blood_map", null)
		_sprite.texture = CARRY_SHEET
		_sprite.hframes = int(CARRY_SHEET.get_width() / 72.0)
		_sprite.vframes = 2
		_sprite.offset = Vector2(0.0, -13.0)
	_sprite.frame_coords = Vector2i(frame, 1 if flip else 0)
	_sprite.flip_h = false
	_sprite.position.y = 0.0


## One frame of the wardrobe clip (the opening of her room, RoomIntro): she stands at the wardrobe facing north.
func show_wardrobe_frame(frame: int) -> void:
	if _sheet != 11:
		_sheet = 11
		fainting = true
		(_sprite.material as ShaderMaterial).set_shader_parameter("blood_map", null)
		_sprite.texture = WARDROBE_SHEET
		_sprite.hframes = int(WARDROBE_SHEET.get_width() / 72.0)
		_sprite.vframes = 1
		_sprite.offset = Vector2(0.0, -13.0)
	_sprite.frame_coords = Vector2i(frame, 0)
	_sprite.flip_h = false
	_sprite.position.y = 0.0


## The opening of her room is over: she stands at `at` facing north and the game is hers. No HUD and no quest here (RoomIntro starts the quest).
func end_room_intro(at: Vector2) -> void:
	global_position = at
	intro = null
	end_faint()
	facing = Vector2.UP
	_camera.reset_smoothing()


## Back to the normal sheet.
func end_faint() -> void:
	fainting = false
	_sheet = -1
	_sprite.flip_h = false
	_sprite.offset = Vector2(0.0, -23.0)


## She is out and stands at `at`, facing east; the HUD comes back and the game is hers.
func end_intro(at: Vector2) -> void:
	global_position = at
	intro = null
	facing = Vector2.RIGHT
	_sheet = -1 ## the next _animate puts the normal sheet back
	_sprite.offset = Vector2(0.0, -23.0)
	if _hud != null:
		_hud.call("end_intro") ## the vines grow in
	if quests != null:
		get_tree().create_timer(2.2).timeout.connect(func() -> void: quests.start("find_help")) ## the story's first quest, once the HUD has grown in
	_camera.reset_smoothing()


## The wake-up in the hut is over: she stands at `at`, facing east, the HUD grows in. (No quest starts here: the quest steps carry on.)
func end_wake(at: Vector2) -> void:
	global_position = at
	intro = null
	z_index = 0
	facing = Vector2.RIGHT
	_sheet = -1
	_sprite.offset = Vector2(0.0, -23.0)
	if _hud != null:
		_hud.call("end_intro")
	_camera.reset_smoothing()


## The rescuer's bandage: the wound stops bleeding for the eye (no blood on her, no drops, no red border, no heartbeat); the sprite shader draws the cloth.
func set_bandaged(on: bool) -> void:
	bandaged = on
	(_sprite.material as ShaderMaterial).set_shader_parameter("bandage", 1.0 if on else 0.0)
	bandaged_changed.emit(on)


func _main_sheet_restore() -> void:
	_camera.reset_smoothing()


## The wounded state follows her health with a little hysteresis; everyone sees it.
func _update_wounded(current: float, maximum: float) -> void:
	var share: float = current / maxf(maximum, 1.0)
	var now: bool = current > 0.0 and (share <= WOUND_ENTER or (wounded and share <= WOUND_LEAVE))
	if now == wounded:
		return
	wounded = now
	if now:
		sprinting = false
		_shake = maxf(_shake, 4.0)
	wounded_changed.emit(now)


## How pale and bloody she looks for the health she has (0 healthy .. 1 nearly bled out), starting gently at 80 %.
func _wound_target() -> float:
	if bandaged and health.current > 0.0:
		return 0.0
	if health.current <= 0.0:
		return 1.0
	var t: float = clampf((WOUND_PALE_FROM - health.current / maxf(health.max_health, 1.0)) / (WOUND_PALE_FROM - 0.05), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## The limp: while wounded she drops onto the bad leg every second step (her body dips a pixel, she leans a little towards where she is
## going, hunched), and drips now and then when she stands.
func _animate_limp(delta: float, moving: bool) -> void:
	var dip: float = 0.0
	var lean: float = 0.0
	if wounded:
		lean = 0.055 * signf(facing.x) if absf(facing.x) > 0.3 else 0.0
		if moving:
			var phase: float = _walk_time / float(WALK_FRAMES)
			var on_bad_leg: float = smoothstep(0.42, 0.55, phase) * (1.0 - smoothstep(0.92, 1.0, phase))
			dip = 1.0 * on_bad_leg
			lean += 0.035 * on_bad_leg * signf(facing.x)
		elif not bandaged:
			_drip_timer -= delta
			if _drip_timer <= 0.0:
				_drip_timer = randf_range(2.0, 4.5)
				BloodSplat.drop(get_tree().current_scene, global_position + Vector2(randf_range(-4.0, 4.0), randf_range(-1.0, 1.0)), 1)
	_limp_dip = lerpf(_limp_dip, dip, minf(1.0, 14.0 * delta))
	_sprite.skew = lerpf(_sprite.skew, lean, minf(1.0, 10.0 * delta))


## Cheat menu: sets her health (the host decides, so a client asks).
func request_set_health(value: float) -> void:
	if multiplayer.is_server():
		health.set_health(value)
	else:
		_rpc_set_health.rpc_id(1, value)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_health(value: float) -> void:
	if multiplayer.is_server() and multiplayer.get_remote_sender_id() == get_multiplayer_authority():
		health.set_health(value)


func _use_sheet(sheet: int) -> void:
	if sheet == _sheet:
		return
	var restore_offset: bool = _sheet == 13 or _sheet == CLIMB_SHEET
	_sheet = sheet
	if sheet == 13:
		_sprite.offset = SWIM_OFFSET
	elif sheet == CLIMB_SHEET:
		_sprite.offset = CLIMB_OFFSET
	elif restore_offset:
		_sprite.offset = Vector2(0.0, -23.0)
	if _swim_under != null:
		_swim_under.visible = sheet == 13
	(_sprite.material as ShaderMaterial).set_shader_parameter("blood_map", _cast_blood if sheet == CAST_SHEET_ID else STEP_BLOOD if sheet == STEP_SHEET_ID else WallClimb.BLOOD if sheet == CLIMB_SHEET else DRINK_BLOOD if sheet == DRINK_SHEET_ID else FEED_BLOOD if sheet == 14 else COMBO_BLOOD if sheet == 12 else (HEAVY_BLOOD if sheet == 11 else (STANDBY_BLOOD if sheet == 9 else (FISH_BLOOD if sheet == 10 else (BLOOD_MAPS[sheet] if sheet < BLOOD_MAPS.size() else null)))))
	match sheet:
		CLIMB_SHEET:
			_sprite.texture = WallClimb.SHEET
			_sprite.hframes = WallClimb.COLUMNS
			_sprite.vframes = 8
		13:
			_sprite.texture = SWIM_SHEET
			_sprite.hframes = int(_swim_rig.get("total", 86))
			_sprite.vframes = 8
			if _swim_under == null:
				_swim_under = Sprite2D.new()
				_swim_under.show_behind_parent = true
				_swim_under.modulate = Color(0.55, 0.9, 0.95, 0.5)
				_sprite.add_child(_swim_under)
			var under_material: ShaderMaterial = ShaderMaterial.new()
			under_material.shader = load("res://assets/shaders/swim_under.gdshader") as Shader
			_swim_under.material = under_material
			_swim_water = SwimWater.new()
			_swim_water.name = "SwimWater"
			add_child(_swim_water)
			_swim_under.texture = SWIM_UNDER
			_swim_under.offset = SWIM_OFFSET
			_swim_under.hframes = _sprite.hframes
			_swim_under.vframes = 8
			_swim_under.visible = true
		1:
			_sprite.texture = ATTACK_SHEET
			_sprite.hframes = ATTACK_COLS
			_sprite.vframes = 8
		STEP_SHEET_ID:
			_sprite.texture = STEP_SHEET
			_sprite.hframes = STEP_FRAMES
			_sprite.vframes = 8
		CAST_SHEET_ID:
			_sprite.texture = _cast_sheet
			_sprite.hframes = PICK_FRAMES * CAST_CLIPS.size()
			_sprite.vframes = 8
		DRINK_SHEET_ID:
			_sprite.texture = DRINK_SHEET
			_sprite.hframes = PICK_FRAMES * EAT_VARIANTS
			_sprite.vframes = 8
		14:
			_sprite.texture = FEED_SHEET
			_sprite.hframes = PICK_FRAMES
			_sprite.vframes = 8
		2, 3, 4, 5:
			_sprite.texture = PICK_SHEET if sheet == 2 else (EAT_SHEET if sheet == 3 else (TOUCH_SHEET if sheet == 5 else PULL_SHEET))
			_sprite.hframes = PICK_FRAMES * (EAT_VARIANTS if sheet == 3 else 1)
			_sprite.vframes = 8
		12:
			_sprite.texture = COMBO_SHEET
			_sprite.hframes = COMBO_COLS
			_sprite.vframes = 8
		11:
			_sprite.texture = HEAVY_SHEET
			_sprite.hframes = HEAVY_COLS
			_sprite.vframes = 8
		10:
			_sprite.texture = FISH_SHEET
			_sprite.hframes = int((DataRegistry.table("hero_rig").get("fish", {}) as Dictionary).get("cols", 1))
			_sprite.vframes = 8
		9:
			_sprite.texture = STANDBY_SHEET
			_sprite.hframes = STANDBY_COLS
			_sprite.vframes = 8
		_:
			_sprite.texture = _main_sheet
			_sprite.hframes = SHEET_COLS
			_sprite.vframes = 16


## Spawn/load initializes blood and pallor immediately; ordinary healing still fades them.
func sync_wound_visuals() -> void:
	_update_wounded(health.current, health.max_health)
	_wound = _wound_target()
	(_sprite.material as ShaderMaterial).set_shader_parameter("wound", _wound)
	attack.wound = _wound
