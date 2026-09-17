shader_type canvas_item;

// Driven from script every frame based on current movement speed (0 = walking/idle,
// 1 = max sprint/dash speed). Controls how tight and dark the vignette gets.
uniform float squint : hint_range(0.0, 1.0) = 0.0;

// Vignette radius (distance from center where darkening begins) at rest.
// Larger = only the far corners darken, like a normal photo vignette.
uniform float base_radius : hint_range(0.3, 1.5) = 0.85;

// Vignette radius at full squint (max speed). Smaller = tighter tunnel vision.
uniform float squint_min_radius : hint_range(0.05, 0.8) = 0.18;

// How soft/blurred the transition edge is. Higher = more gradual, photographic falloff.
uniform float vignette_softness : hint_range(0.05, 1.0) = 0.55;

// How dark the vignette is at rest (0 = invisible, 1 = fully opaque at the edge).
uniform float base_intensity : hint_range(0.0, 1.0) = 0.5;

// How dark it gets at full squint/speed. Capped below 1.0 so the center always
// stays at least partially visible, even at max squint.
uniform float squint_intensity : hint_range(0.0, 1.0) = 0.85;

// Vignette color at rest — typically near-black for a classic photo vignette.
uniform vec4 vignette_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

// Color blended in as squint increases, e.g. a subtle warm/red exertion tint.
uniform vec4 squint_tint_color : source_color = vec4(0.35, 0.05, 0.04, 1.0);

void fragment() {
	// -1..1 centered coordinates. Since this runs on a full-rect ColorRect,
	// UV naturally stretches to the screen's aspect ratio, so the vignette
	// reads as an ellipse matching the screen shape, same as a real photo vignette.
	vec2 centered = (UV - 0.5) * 2.0;
	float dist = length(centered);

	float radius = mix(base_radius, squint_min_radius, squint);
	float vig = smoothstep(radius - vignette_softness, radius + vignette_softness, dist);

	float intensity = mix(base_intensity, squint_intensity, squint);
	vec3 color = mix(vignette_color.rgb, squint_tint_color.rgb, squint);

	COLOR = vec4(color, vig * intensity);
}