with open('src/world/meadow_details.gd', 'r', encoding='utf-8') as f:
    text = f.read()

target1 = """var _hidden: Dictionary = {} ## instance index -> true: plants the town's ground has no room for"""

replacement1 = """var _hidden: Dictionary = {} ## instance index -> true: plants the town's ground has no room for
var _dirty: bool = false
var _contact_timer: float = 0.0
const CONTACT_UPDATE_INTERVAL: float = 0.12 ## Throttle texture upload to ~8 updates/sec max during active contacts"""

assert target1 in text, "target1 not found"
text = text.replace(target1, replacement1, 1)

target2 = """func stamp_segment(from: Vector2, to: Vector2, force: float) -> bool:
\tif not Rect2(_origin-Vector2(20,20),Vector2(552,552)).intersects(Rect2(from,Vector2.ZERO).expand(to).grow(16)):
\t\treturn false
\tvar touched: bool = false
\tvar direction: Vector2 = (to-from).normalized()
\tvar steps: int = maxi(1,ceili(from.distance_to(to)/5.0))
\tfor step: int in steps+1:
\t\tvar at: Vector2 = from.lerp(to,float(step)/steps)
\t\tvar cell: Vector2i = Vector2i(((at-_origin)/8.0).floor())
\t\tfor dy: int in range(-2,3):
\t\t\tfor dx: int in range(-2,3):
\t\t\t\tvar c: Vector2i = cell+Vector2i(dx,dy)
\t\t\t\tif c.x<0 or c.y<0 or c.x>=64 or c.y>=64: continue
\t\t\t\tvar distance: float = (Vector2(c)*8+Vector2(4,4)+_origin).distance_to(at)
\t\t\t\tif distance > 17.0: continue
\t\t\t\tvar amount: float = (1.0-distance/20.0)*force
\t\t\t\t_bends[c] = Vector3(direction.x*amount,direction.y*amount,0.0)
\t\t\t\tif _occupied.has(c): touched = true
\treturn touched

func advance_contacts(delta: float) -> void:
\tif _bends.is_empty(): return
\tfor cell: Vector2i in _bends.keys():
\t\tvar impulse: Vector3 = _bends[cell]
\t\timpulse.z += delta
\t\tif impulse.z > 0.9:
\t\t\t_field.set_pixelv(cell,Color(0.5,0.5,0,1))
\t\t\t_bends.erase(cell)
\t\t\tcontinue
\t\t_bends[cell] = impulse
\t\tvar fade: float = exp(-impulse.z*5.0)*cos(impulse.z*10.0)
\t\t_field.set_pixelv(cell,Color(0.5+impulse.x*fade*0.25,0.5+impulse.y*fade*0.25,0,1))
\t_contact_texture.update(_field)"""

replacement2 = """func stamp_segment(from: Vector2, to: Vector2, force: float) -> bool:
\tif not Rect2(_origin-Vector2(20,20),Vector2(552,552)).intersects(Rect2(from,Vector2.ZERO).expand(to).grow(16)):
\t\treturn false
\tvar touched: bool = false
\tvar direction: Vector2 = (to-from).normalized()
\tvar steps: int = maxi(1,ceili(from.distance_to(to)/8.0))
\tfor step: int in steps+1:
\t\tvar at: Vector2 = from.lerp(to,float(step)/steps)
\t\tvar cell: Vector2i = Vector2i(((at-_origin)/8.0).floor())
\t\tfor dy: int in range(-2,3):
\t\t\tfor dx: int in range(-2,3):
\t\t\t\tvar c: Vector2i = cell+Vector2i(dx,dy)
\t\t\t\tif c.x<0 or c.y<0 or c.x>=64 or c.y>=64: continue
\t\t\t\tvar cell_center: Vector2 = Vector2(c)*8.0+Vector2(4,4)+_origin
\t\t\t\tvar d_sq: float = cell_center.distance_squared_to(at)
\t\t\t\tif d_sq > 289.0: continue ## 17.0 * 17.0
\t\t\t\tvar distance: float = sqrt(d_sq)
\t\t\t\tvar amount: float = (1.0-distance/20.0)*force
\t\t\t\t_bends[c] = Vector3(direction.x*amount,direction.y*amount,0.0)
\t\t\t\t_dirty = true
\t\t\t\tif _occupied.has(c): touched = true
\treturn touched

func advance_contacts(delta: float) -> void:
\tif _bends.is_empty() and not _dirty:
\t\treturn
\t_contact_timer += delta
\tvar should_update: bool = _dirty or _contact_timer >= CONTACT_UPDATE_INTERVAL
\tif not _bends.is_empty():
\t\tfor cell: Vector2i in _bends.keys():
\t\t\tvar impulse: Vector3 = _bends[cell]
\t\t\timpulse.z += delta
\t\t\tif impulse.z > 0.9:
\t\t\t\t_field.set_pixelv(cell,Color(0.5,0.5,0,1))
\t\t\t\t_bends.erase(cell)
\t\t\t\tshould_update = true
\t\t\t\tcontinue
\t\t\t_bends[cell] = impulse
\t\t\tif should_update:
\t\t\t\tvar fade: float = exp(-impulse.z*5.0)*cos(impulse.z*10.0)
\t\t\t\t_field.set_pixelv(cell,Color(0.5+impulse.x*fade*0.25,0.5+impulse.y*fade*0.25,0,1))
\t\tif _bends.is_empty():
\t\t\tshould_update = true
\tif should_update:
\t\t_contact_texture.update(_field)
\t\t_contact_timer = 0.0
\t\t_dirty = false"""

assert target2 in text, "target2 not found"
text = text.replace(target2, replacement2, 1)

with open('src/world/meadow_details.gd', 'w', encoding='utf-8', newline='') as f:
    f.write(text)

print("meadow_details.gd updated successfully!")
