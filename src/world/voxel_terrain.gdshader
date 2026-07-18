shader_type spatial;
// Opaque terrain shader for Project Horizons.
//
// Per vertex the mesh provides:
//   - UV:      atlas coordinates for this block's tile.
//   - COLOR.rgb: a grayscale shade factor (ambient occlusion * per-block
//                brightness variation) that softens edges and de-flattens the
//                terrain.
//   - COLOR.a: a seasonal tint weight (1 for grass & leaves, 0 otherwise).
//
// Final albedo = atlas texel (the block's colour/texture) * shade * season tint.
// One shared material means updating the atlas or season uniforms recolours the
// whole world with no re-meshing.
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D atlas : source_color, filter_nearest;
uniform vec3 season_tint : source_color = vec3(1.0, 1.0, 1.0);
uniform float season_strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 tex = texture(atlas, UV);
	float weight = COLOR.a * season_strength;
	vec3 tint = mix(vec3(1.0), season_tint, weight);
	ALBEDO = tex.rgb * COLOR.rgb * tint;
	ROUGHNESS = 0.9;
	METALLIC = 0.0;
}
