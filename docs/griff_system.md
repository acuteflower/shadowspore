# Griff-System: how Ellie holds things (2026-11-12)

The sword arm (her right) is not in the body sheets; the game draws it and the held item. Before this system the item was a 2D pointer turning
around the hand (a slash was a full-length clock hand, turning around changed nothing but the screen angle, the rest pose followed the cursor
every frame) and the arm was two 2 px lines with a 3 px glove. Both read "spinny" and foreign next to the rendered body.

## The idea

Everything she holds lives in the same small 3D world as her body model (`tools/art_hero3d.py`) and is projected with the same camera
(pitch 26 deg: screen = (x, y sin - z cos)). `GripRig` (src/components/grip_rig.gd) is that geometry, pure functions only, so every peer
derives the same pose from the synced state (`held_weapon`, swing RPCs, the body sector) without new network traffic.

- **The fist** starts at the sheet's exact 3D right-arm pose (`data/hero_arm3d.json`, exported by `tools/art_hero_arm_depth.py` via
  `GripRig.frame_arm3`, falling back to `GripRig.hand_3d`) and, while the main sheet plays (`free_hand`, set by `Player._animate`) and an
  item is visibly held (`_hold_k`), moves toward the item's own hold via `GripRig.arm`. Empty hands, sheathed weapons, swings, picking,
  eating, casting, fishing and standby gestures follow the exact 3D shoulder/elbow/wrist/fist from the body model.
- **The arm** is painted by `ArmPainter` (src/fx/arm_painter.gd) with the same 4x4 subpixel coverage threshold (`>= 6/16` samples) as
  `tools/art_hero3d.py`, matching the thickness of her baked left arm: plum coat sleeve, black leather bracer with the glowing violet band,
  leather glove; the same radii, the same light from the upper left in four flat bands (`shade_band` thresholds), ink where a part lies in
  front of another and the dark outline (`ink_color`). Each gameplay `*_blood.png` stores per-pixel camera depth in `G` and material ID in
  `B` (with `alpha = 1` on sprite outlines so `hit_flash.gdshader` ignores them while lossless import preserves RGB), allowing `ArmPainter`
  to occlude the arm and its outline per-pixel behind her silver hair, face and coat instead of flipping the whole arm in front of or behind
  the sprite. The arm and the item wear a copy of her sprite shader (`AttackComponent.mirror_material`), so pallor, wetness, the hit flash,
  the mist veil and the daylight grade match the sheet. It is painted again only when the arm pose or sprite frame changed.
- **The item** points along a 3D direction. At rest a damped spring on its compass angle and pitch pulls it toward the hold, so it has
  weight: the fist's acceleration swings the tip, turning to a new facing sweeps it round (relative to the facing the body sheet shows,
  not the cursor), and it settles with a small overshoot. Only the projected angle and foreshortening reach the pre-rotated sprite
  (`*_held_rot.png`); tools with a working side are mirrored instead of shown upside down when they point left.

## Holds (data/grips.json `styles`)

Per item kind (`grip` key in items.json, else its `tool`, else sword):
- `carry` relaxed (sword in a low guard beside the leg, axe hanging by the haft, pickaxe and hoe on the shoulder, sickle low, can by its handle),
- `ready` for `spring.ready_for` seconds after a swing or charge (raised, point forward),
- `sprint` (trailing back; pick and hoe stay on the shoulder).
`hand` = fist offset [forward, right, up] px from the natural hand, `dir` = [degrees toward her right hand, pitch]. `edge` (+1 lower / -1
upper side of the held picture is the working side: it leads every swing) and `upright` (the can keeps its top up).

## Swings (data/grips.json `swings`, per weapon class, `blocks` per combo block)

A cut passes the aim at `GripRig.aim_pitch` (a little down toward the camera, raised away from it), so it reads on the aim line. It sweeps
through a plane that leans `tilt` up on her right side for a forehand and `tilt_back` for a backhand (sword: 48 / -42, so the two cross
as an X); `top_down` classes (axe, pickaxe, hoe) always come over the head. `cock` / `follow` are the radians beyond the arc before and
after, `over` the follow-through overshoot in the recovery, then the item eases back into the hold. The heavy blow, its charge and the
Himmelsriss diagonals keep their pitch/yaw paths, now as 3D directions with smooth hand-overs. The slash trail is a ribbon along the path the
tip really took; motes leave the blade's outer part and fly the way the tip moved. Hit scans are untouched (host, `_hit_scan`).

## Checks

- `Godot --headless --path . tools/test_grip.tscn` (prints `GRIP OK`; `-- --dump` prints the arm's pixel grid per facing): projection,
  aim pitch, arm lengths and reach, swing planes, painter coverage and outline, every tool in every facing (rest finite, swing ends,
  no screen spin against the 3D motion, wind-up through space, smooth settle), turning with weight, the arm material, hiding, raster cost.
- Look study: `Godot --rendering-driver opengl3 --path . tools/preview_held.tscn -- --capture=/abs.png [--item=sword_basic]
  [--mode=rest|swing|walk] [--step=0]` (rest: carry / ready / sprint x eight facings; swing: four facings x eight moments).
