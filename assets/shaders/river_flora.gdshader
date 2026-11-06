shader_type canvas_item;

// Signed pixel displacement at the tips; root remains at the sprite's foot.
// The caller supplies current- and actor-driven bend on plant rows only.
uniform float bend = 0.0;
uniform vec2 current_push = vec2(0.0);

void vertex() {
    float root_factor = clamp(-VERTEX.y / 28.0, 0.0, 1.0);
    VERTEX += round((vec2(clamp(bend, -2.0, 2.0), 0.0) + current_push) * root_factor);
}
