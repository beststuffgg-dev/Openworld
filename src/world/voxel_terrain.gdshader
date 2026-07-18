shader_type spatial;
// Opaque terrain shader for Project Horizons.
//
// The mesh bakes albedo*ambient-occlusion into COLOR and stores a per-vertex
// "seasonal tint weight" in UV.x (1.0 for grass & leaves, 0.0 for everything
// else). A global season uniform then modulates the tintable vertices live, so
// the whole world changes with the seasons without re-meshing a single chunk.
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Multiplicative colour applied to tintable surfaces; 1,1,1 == no change.
uniform vec3 season_tint : source_color = vec3(1.0, 1.0, 1.0);
// How strongly the current season shows, 0 (off) .. 1 (full).
uniform float season_strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float weight = UV.x * season_strength;
	vec3 tint = mix(vec3(1.0), season_tint, weight);
	ALBEDO = COLOR.rgb * tint;
	ROUGHNESS = 0.9;
	METALLIC = 0.0;
}
