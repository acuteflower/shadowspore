@tool
extends SceneTree

func _init() -> void:
    var vp: SubViewport = SubViewport.new()
    vp.size = Vector2i(1280, 720)
    vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(vp)
    
    var atmo: NightAtmosphere = NightAtmosphere.new()
    vp.add_child(atmo)
    
    for i in 3:
        await process_frame
        
    for child in atmo._layer.get_children():
        if child is Control:
            print('Child rect position: ', child.position, ' size: ', child.size, ' visible: ', child.visible)
    print('Atmo origin: ', atmo._origin, ' view: ', atmo._view)
    print('Viewport get_visible_rect: ', vp.get_visible_rect())
    quit()
