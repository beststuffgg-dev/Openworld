shader_type spatial;
// Opaque terrain shader for Project Horizons (greedy-mesh friendly).
//
// A greedy-merged quad spans w x h blocks, so UV runs 0..w / 0..h and we wrap it
// with fract() to TILE the block's atlas tile instead of stretching it. UV2 holds
// the tile origin (constant per quad); tile_size is the tile's extent in atlas UV
// space. Per-voxel brightness variation is derived in the fragment shader from
// world position (so it survives merging), and COLOR.a carries the seasonal tint
// weight. Ambient occlusion comes from the environment's SSAO.
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D atlas : source_color, filter_nearest;
uniform vec2 tile_size = vec2(0.125, 0.5);
uniform float voxel_scale = 0.5;
uniform vec3 season_tint : source_color = vec3(1.0, 1.0, 1.0);
uniform float season_strength : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	// Tile the block's atlas tile across the merged quad.
	vec2 atlas_uv = UV2 + fract(UV) * tile_size;
	vec3 tex = texture(atlas, atlas_uv).rgb;

	// Subtle per-voxel brightness variation to break up flat expanses.
	vec3 cell = floor(v_world / voxel_scale);
	float vary = 0.9 + 0.1 * hash13(cell + 0.5);

	// Seasonal tint on grass/leaves (COLOR.a is the tint weight).
	float weight = COLOR.a * season_strength;
	vec3 tint = mix(vec3(1.0), season_tint, weight);

	ALBEDO = tex * vary * tint;
	ROUGHNESS = 0.9;
	METALLIC = 0.0;
}
