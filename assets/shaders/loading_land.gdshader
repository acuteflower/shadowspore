shader_type canvas_item;
render_mode unshaded;
// Same warm dark, copper ember edge and 4x4 dithering as door_wipe.
uniform float time = 0.0;
uniform float travel = 0.0;
uniform vec2 view_size = vec2(640.0, 360.0);
const vec3 DARK = vec3(0.03, 0.02, 0.035);
const vec3 EMBER = vec3(0.95, 0.55, 0.25);
const float BAYER[16] = float[16](0.,8.,2.,10.,12.,4.,14.,6.,3.,11.,1.,9.,15.,7.,13.,5.);
float hash21(vec2 p) {
 p = fract(p * vec2(123.34,456.21)); p += dot(p,p+45.32); return fract(p.x*p.y);
}
float noise(vec2 p) {
 vec2 i=floor(p), f=fract(p); f=f*f*(3.-2.*f);
 return mix(mix(hash21(i),hash21(i+vec2(1,0)),f.x),mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),f.x),f.y);
}
void fragment() {
 vec2 p=floor(UV*view_size)-(view_size-vec2(640,360))*.5;
 float d=BAYER[int(mod(p.y+4096.,4.))*4+int(mod(p.x+4096.,4.))]/16.;
 float halo=exp(-dot((p-vec2(322,190))/vec2(220,85),(p-vec2(322,190))/vec2(220,85)));
 float mist=noise(p*.018+vec2(time*.035,-time*.025));
 vec3 col=DARK+vec3(.045,.027,.055)*floor((halo*(.6+mist*.4))*5.+d)/5.;
 // A travelling slice of soil with broken stone, a copper seam and frayed roots.
 vec2 q=p+vec2(travel,0);
 float edgefade=smoothstep(95.,170.,p.x)*(1.-smoothstep(470.,545.,p.x));
 float depth=p.y-212.;
 float bottom=12.+noise(vec2(q.x*.07,2.))*15.;
 if(depth>=0. && depth<bottom && edgefade>d) {
   float grain=noise(vec2(q.x*.15,depth*.25));
   col=mix(vec3(.070,.048,.070),vec3(.16,.105,.105),floor(grain*3.)/3.);
   if(depth>bottom-5.) col=mix(DARK,col,(bottom-depth)/5.);
   float cracks=noise(vec2(q.x*.075,depth*.13));
   if(abs(cracks-.48)<.028 && depth<14.) col=EMBER*(.17+.12*sin(time*1.8+q.x*.03));
   if(depth<2. && grain>.4) col=EMBER*(.25+.12*grain);
   if(depth>3. && mod(floor(q.x/9.)+floor(depth/4.),3.)==0. && grain>.53) col*=.55;
 }
 COLOR=vec4(col,1.);
}
