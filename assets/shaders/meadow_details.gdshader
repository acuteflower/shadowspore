shader_type canvas_item;
render_mode blend_mix;
uniform float wind_clock = 0.0;
uniform vec2 wind_direction = vec2(1.,0.);
uniform float wind_gust = 0.0;
uniform vec2 chunk_origin;
uniform sampler2D contacts : filter_linear, repeat_disable;
varying vec4 detail;
varying vec4 tint;
void vertex() {
	detail = INSTANCE_CUSTOM;
	tint = COLOR;
	vec2 world = (MODEL_MATRIX * vec4(0.,9.,0.,1.)).xy;
	float clock = floor(wind_clock*12.)/12.;
	float pulse = .5+.5*sin(dot(world,wind_direction)*.014-clock*1.6);
	float breeze = (.12+wind_gust*(.35+.65*pulse))*detail.a;
	float flutter = sin(clock*2.1+detail.g*6.283)*breeze*.25;
	vec2 bend = texture(contacts,(world-chunk_origin)/512.).rg-vec2(.5);
	vec2 wind = wind_direction*breeze*detail.b*2.2+vec2(flutter,flutter*.25);
	vec2 contact = bend*vec2(16.,9.);
	float rooted = pow(1.-UV.y,1.5);
	VERTEX += round((wind+contact)*rooted);
}
void fragment() {
	vec2 uv = vec2((UV.x+floor(detail.r*26.+.5))/26.,UV.y);
	COLOR = tint*texture(TEXTURE,uv);
}
