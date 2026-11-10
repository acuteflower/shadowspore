// Hanging vines that breathe (docs/hexenwald_leben_konzept.md): a sheet of ropes (one row) and, `mask_rows` of the texture's height
// further down, their mask: red = how far down its rope a pixel hangs (0 at the hem .. 1 at the tip). Every pixel slides sideways in whole
// art pixels by an amount that grows towards the tip and follows a slow breath (not the wind: the Hexenwald's air stands still), with a
// wave that runs down the rope. Each output pixel looks for the source pixel that lands on it (the exact inverse, up to +-3 px).
// The breath runs on WorldWind's game clock (it stops when the game is paused); every tree has its own phase from where it stands.
global uniform float g_wind_clock;
uniform float amp = 2.2; // art pixels at the tip
uniform float speed = 0.55; // rad/s of the breath
uniform float mask_rows = 0.333333; // UV distance from the art row to the mask row
varying vec4 modulate_in;
varying float phase;

// How many art pixels a mask value `w` slides at the moment (the loop that uses it sits in each shader's fragment(): the built-in TEXTURE
// cannot be handed to a function).
int vine_shift(float w, float ph) {
	return int(floor(amp * pow(w, 1.3) * sin(g_wind_clock * speed + ph - w * 2.2) + 0.5));
}
