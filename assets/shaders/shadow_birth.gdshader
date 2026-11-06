shader_type canvas_item;
render_mode unshaded;
uniform sampler2D ground : hint_screen_texture, repeat_disable, filter_nearest;
uniform float age = 0.0;
uniform float seed = 0.0;
const float BAYER[16] = float[16](0.,8.,2.,10.,12.,4.,14.,6.,3.,11.,1.,9.,15.,7.,13.,5.);
float hash(vec2 p) { return fract(sin(dot(p,vec2(12.9898,78.233))+seed*91.7)*43758.5453); }
vec2 knot(float i) {
	// Both halves meet under the creature. Every other point tears sideways.
	float x = (i-4.0)*10.0;
	return vec2(x, i == 4.0 ? 0.0 : (hash(vec2(i,8.1))-.5)*15.0);
}
float segment(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b-a;
	float t = clamp(dot(p-a,ab)/max(dot(ab,ab),.001),0.,1.);
	return length(p-a-ab*t);
}
void fragment() {
	vec2 pixel = floor(UV*vec2(128.,96.));
	vec2 p = pixel + .5 - vec2(64.,48.);
	float angle = fract(seed*.6180339)*6.2832;
	p.y /= .62;
	p = mat2(vec2(cos(angle),sin(angle)),vec2(-sin(angle),cos(angle))) * p;
	float t = floor(age*10.)/10.;
	float dissolve = smoothstep(3.0,4.6,age);
	float grow = smoothstep(0.,1.55,age);
	float bite = (hash(floor(pixel*.5))-.5)*1.7;
	float wound = 100.;
	float branch = 100.;
	float pulse = 0.;
	for(int i=0;i<8;i++) {
		float k = float(i);
		vec2 a = knot(k), b = knot(k+1.);
		float delay = abs(k-3.5)*.13 + hash(vec2(k,12.))* .22;
		float spread = smoothstep(delay,delay+.5,age);
		b = mix(a,b,spread);
		float swelling = smoothstep(.35+delay,1.55+delay,age);
		float width = (1.0+hash(vec2(k,4.))*3.5 + swelling*(3.+hash(vec2(k,5.))*5.)) * spread;
		width *= 1.-dissolve*.65;
		// A living, uneven border, rather than rotating concentric rings.
		width += sin(t*2.4+k*2.7+p.x*.19)*swelling*.9;
		float d = segment(p,a,b);
		wound = min(wound,d-width+bite);
		vec2 root = mix(knot(k),knot(k+1.),hash(vec2(k,16.)));
		float side = hash(vec2(k,17.))>.5 ? 1. : -1.;
		vec2 elbow = root + vec2((hash(vec2(k,18.))-.5)*14.,side*(8.+hash(vec2(k,19.))*10.));
		vec2 tip = elbow + vec2((hash(vec2(k,20.))-.5)*18.,side*(5.+hash(vec2(k,21.))*9.));
		float reach = smoothstep(delay+.2,delay+.95,age);
		float dbranch = min(segment(p,root,mix(root,elbow,reach)),segment(p,elbow,mix(elbow,tip,reach)));
		float branch_width = (.55+hash(vec2(k,22.))*1.2)*reach;
		branch = min(branch,dbranch-branch_width);
		if(dbranch < branch_width+1.) pulse = max(pulse,.5+.5*sin(length(p-root)*.9-t*5.+k*1.7));
	}
	float h = hash(pixel);
	float stipple = BAYER[int(mod(pixel.y,4.))*4+int(mod(pixel.x,4.))]/16.;
	float inside = 1.-step(0.,wound);
	float on_branch = 1.-step(0.,branch);
	float rim = (1.-smoothstep(-1.,2.,wound))*(1.-inside);
	vec3 dark = mix(vec3(.027,.016,.05),vec3(.09,.06,.16),hash(floor(pixel*.5)+7.)*.8);
	if(wound > -2.5 && stipple < .55) dark = vec3(.14,.09,.27);
	if(h>.965 && sin(age*3.+h*40.)>.3) dark = vec3(.54,.30,1.);
	vec3 col = mix(dark,mix(vec3(.20,.12,.40),vec3(.63,.49,1.),pulse*pulse),on_branch*(1.-inside)*.8);
	float warp = (1.-smoothstep(1.,5.,abs(wound)))*grow*(1.-dissolve);
	vec2 shift = vec2(sin(p.y*.4+t*3.),cos(p.x*.3-t*2.))*warp*1.8;
	vec3 earth = texture(ground,SCREEN_UV+shift*SCREEN_PIXEL_SIZE).rgb;
	float ink = max(inside,on_branch)*grow;
	col = mix(earth,col,ink);
	float alpha = max(max(ink,rim*.7*grow),warp*.7);
	// Same outward, stochastic crumble as footprints and death infestation.
	if(h < dissolve*(.55+length(p)/75.) || age < .04) alpha = 0.;
	COLOR = vec4(col,alpha*(1.-smoothstep(4.25,4.6,age)));
}
