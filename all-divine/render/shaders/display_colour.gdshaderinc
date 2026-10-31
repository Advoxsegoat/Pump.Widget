// Colours as the screen shows them (sRGB, 0 to 1), and how a spatial shader reads and writes them so
// that what it means to show is what shows, in either renderer. screen_post works in these colours, so
// its maths, and so its pictures, are the same in Compatibility and Forward+.
//
// Forward+ and Mobile keep the 3D picture in linear light and encode it to sRGB once, exactly, in the
// tonemap pass: the screen texture holds linear values, and an unshaded ALBEDO is linear.
//
// Compatibility encodes in the scene shader itself, and with approximations: it decodes ALBEDO with the
// cubic a(a(0.3053a + 0.6822) + 0.0125) and encodes with max(1.055 x^(1/2.4) - 0.055, 0), which are not
// each other's inverse (a colour sent straight through comes back as much as 7/255 off). Its screen
// texture holds the encoded picture, that is, the colours as shown.
//
// Both assume what our scenes use: the linear tonemapper at exposure 1 and, in Compatibility, no glow,
// SSAO or colour adjustments in the environment (any of those make Compatibility keep the picture linear
// until a pass of its own, and our bloom and grade replace them anyway).

#if CURRENT_RENDERER == RENDERER_COMPATIBILITY

// A screen-texture sample as shown.
vec3 display_from_screen(vec3 screen) {
	return screen;
}

// The ALBEDO an unshaded material writes to show `display`: the linear value Compatibility's encoder
// turns into it, then the value its cubic decodes to that, found by Newton's method from the value the
// exact sRGB curve gives (the cubic is close to that curve, so a few steps are plenty).
vec3 albedo_for_display(vec3 display) {
	vec3 d = clamp(display, vec3(0.0), vec3(1.0));
	vec3 x = pow((d + 0.055) / 1.055, vec3(2.4));
	vec3 a = mix(1.055 * pow(x, vec3(1.0 / 2.4)) - 0.055, x * 12.92, lessThan(x, vec3(0.0031308)));
	for (int i = 0; i < 5; i++) {
		vec3 decoded = a * (a * (a * 0.305306011 + 0.682171111) + 0.012522878);
		vec3 slope = a * (a * 0.915918033 + 1.364342222) + 0.012522878;
		a = max(a - (decoded - x) / slope, vec3(0.0));
	}
	return a;
}

#else

// A screen-texture sample as shown: the exact sRGB encoding the tonemap pass will give it, of the part
// the screen can show (Compatibility's screen texture never holds more than that either).
vec3 display_from_screen(vec3 screen) {
	vec3 c = clamp(screen, vec3(0.0), vec3(1.0));
	return mix(1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, c * 12.92, lessThan(c, vec3(0.0031308)));
}

// The ALBEDO an unshaded material writes to show `display`: its exact linear value.
vec3 albedo_for_display(vec3 display) {
	vec3 d = clamp(display, vec3(0.0), vec3(1.0));
	return mix(pow((d + 0.055) / 1.055, vec3(2.4)), d / 12.92, lessThan(d, vec3(0.04045)));
}

#endif
