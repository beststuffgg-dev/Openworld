class_name ChunkMesher
extends RefCounted
## Builds a renderable ArrayMesh from a chunk's voxels using GREEDY meshing.
##
## For each of the three axes it sweeps the chunk in slices, builds a mask of the
## visible faces on that plane, then merges coplanar faces of the same block into
## the largest possible rectangles. This collapses a flat field of thousands of
## unit quads into a handful of big ones — essential now that blocks are small
## (see Chunk.VOXEL_SCALE), where a naive mesher would emit ~64x the geometry.
##
## Attributes per vertex:
##   - UV:   tiling coordinates 0..w / 0..h so a merged quad repeats the block
##           texture instead of stretching it.
##   - UV2:  the block's atlas tile origin (constant per quad).
##   - COLOR.a: seasonal tint weight (1 for grass/leaves, else 0).
## Ambient occlusion is provided by the environment's SSAO rather than baked into
## vertices (baked AO would prevent merging); per-voxel colour variation is done
## in the shader from world position. The mesher never touches the scene tree, so
## it is safe on a worker thread.

const CS := Chunk.CHUNK_SIZE
const CH := Chunk.CHUNK_HEIGHT

## Builds an ArrayMesh for `chunk`. `sampler` is Callable(gx, gy, gz) -> int id in
## world voxel coordinates, used to read across chunk borders. Returns null when
## the chunk would produce no geometry.
static func build(chunk: Chunk, sampler: Callable) -> ArrayMesh:
	var opaque := SurfaceArrays.new()
	var fluid := SurfaceArrays.new()
	var base_x := chunk.cx * CS
	var base_z := chunk.cz * CS
	var dims := [CS, CH, CS]

	for d in 3:
		_greedy_axis(chunk, sampler, base_x, base_z, dims, d, opaque, fluid)

	if opaque.positions.is_empty() and fluid.positions.is_empty():
		return null

	var mesh := ArrayMesh.new()
	if not opaque.positions.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, opaque.to_arrays())
		mesh.surface_set_material(mesh.get_surface_count() - 1, get_opaque_material())
	if not fluid.positions.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, fluid.to_arrays())
		mesh.surface_set_material(mesh.get_surface_count() - 1, _fluid_material())
	return mesh

# --- Greedy meshing --------------------------------------------------------

static func _greedy_axis(chunk: Chunk, sampler: Callable, base_x: int, base_z: int, dims: Array, d: int, opaque: SurfaceArrays, fluid: SurfaceArrays) -> void:
	var u := (d + 1) % 3
	var v := (d + 2) % 3
	var du: int = dims[u]
	var dv: int = dims[v]

	var mask_op := PackedInt32Array()
	var mask_fl := PackedInt32Array()
	mask_op.resize(du * dv)
	mask_fl.resize(du * dv)

	for slice in range(-1, dims[d]):
		# Build the two masks (opaque + water) for this plane.
		var n := 0
		for j in dv:
			for i in du:
				var pa := _pos(d, u, v, slice, i, j)
				var pb := _pos(d, u, v, slice + 1, i, j)
				var a := _vox(chunk, sampler, base_x, base_z, pa)
				var b := _vox(chunk, sampler, base_x, base_z, pb)
				mask_op[n] = _face_opaque(a, b)
				mask_fl[n] = _face_fluid(a, b)
				n += 1
		_emit_plane(mask_op, du, dv, d, u, v, slice, opaque, false)
		_emit_plane(mask_fl, du, dv, d, u, v, slice, fluid, true)

## Signed block id of the opaque face between cell a and cell b (b = a + axis),
## or 0 if none. Positive => face normal points +axis (belongs to a); negative =>
## normal points -axis (belongs to b).
static func _face_opaque(a: int, b: int) -> int:
	var a_solid := BlockDB.is_solid(a)
	var b_solid := BlockDB.is_solid(b)
	if a_solid and not b_solid:
		return a
	if b_solid and not a_solid:
		return -b
	return 0

## Same as _face_opaque but for water, which only shows a face against air.
static func _face_fluid(a: int, b: int) -> int:
	if a == BlockDB.Type.WATER and b == BlockDB.Type.AIR:
		return BlockDB.Type.WATER
	if b == BlockDB.Type.WATER and a == BlockDB.Type.AIR:
		return -BlockDB.Type.WATER
	return 0

static func _emit_plane(mask: PackedInt32Array, du: int, dv: int, d: int, u: int, v: int, slice: int, sa: SurfaceArrays, is_fluid: bool) -> void:
	var j := 0
	while j < dv:
		var i := 0
		while i < du:
			var c := mask[i + j * du]
			if c == 0:
				i += 1
				continue
			# Grow width along u.
			var w := 1
			while i + w < du and mask[(i + w) + j * du] == c:
				w += 1
			# Grow height along v while the whole row matches.
			var h := 1
			var done := false
			while j + h < dv and not done:
				for k in w:
					if mask[(i + k) + (j + h) * du] != c:
						done = true
						break
				if not done:
					h += 1
			_emit_quad(sa, d, u, v, slice, i, j, w, h, c, is_fluid)
			# Clear the consumed cells.
			for hh in h:
				for ww in w:
					mask[(i + ww) + (j + hh) * du] = 0
			i += w
		j += 1

static func _emit_quad(sa: SurfaceArrays, d: int, u: int, v: int, slice: int, i: int, j: int, w: int, h: int, c: int, is_fluid: bool) -> void:
	var id := absi(c)
	var positive := c > 0
	var base := _axis(d, slice + 1) + _axis(u, i) + _axis(v, j)
	var uax := _axis(u, w)
	var vax := _axis(v, h)
	var c0 := base
	var c1 := base + uax
	var c2 := base + uax + vax
	var c3 := base + vax
	var normal := _axis(d, 1.0 if positive else -1.0)

	var col := Color(1, 1, 1, 1.0 if BlockDB.is_tintable(id) else 0.0)
	if is_fluid:
		col = BlockDB.get_color(id)
	var origin := Textures.tile_origin(id)
	var fw := float(w)
	var fh := float(h)

	var start := sa.positions.size()
	_push(sa, c0, normal, col, Vector2(0, 0), origin)
	_push(sa, c1, normal, col, Vector2(fw, 0), origin)
	_push(sa, c2, normal, col, Vector2(fw, fh), origin)
	_push(sa, c3, normal, col, Vector2(0, fh), origin)
	if positive:
		sa.indices.append_array(PackedInt32Array([start, start + 1, start + 2, start, start + 2, start + 3]))
	else:
		sa.indices.append_array(PackedInt32Array([start, start + 2, start + 1, start, start + 3, start + 2]))

static func _push(sa: SurfaceArrays, pos: Vector3, normal: Vector3, col: Color, uv: Vector2, uv2: Vector2) -> void:
	sa.positions.append(pos)
	sa.normals.append(normal)
	sa.colors.append(col)
	sa.uvs.append(uv)
	sa.uv2s.append(uv2)

# --- Helpers ---------------------------------------------------------------

## Reads a voxel id at chunk-local position `p` (an [x, y, z] array); falls back
## to the world sampler when p is outside this chunk's x/z columns.
static func _vox(chunk: Chunk, sampler: Callable, base_x: int, base_z: int, p: Array) -> int:
	var px: int = p[0]
	var py: int = p[1]
	var pz: int = p[2]
	if py < 0 or py >= CH:
		return BlockDB.Type.AIR
	if px >= 0 and px < CS and pz >= 0 and pz < CS:
		return chunk.voxels[Chunk.index(px, py, pz)]
	return int(sampler.call(base_x + px, py, base_z + pz))

## Builds an [x, y, z] position array with p[d] = sd, p[u] = su, p[v] = sv.
static func _pos(d: int, u: int, v: int, sd: int, su: int, sv: int) -> Array:
	var p := [0, 0, 0]
	p[d] = sd
	p[u] = su
	p[v] = sv
	return p

static func _axis(axis: int, val: float) -> Vector3:
	match axis:
		0: return Vector3(val, 0, 0)
		1: return Vector3(0, val, 0)
		_: return Vector3(0, 0, val)

# --- Shared materials ------------------------------------------------------

## The opaque terrain material. Public so SeasonManager and TextureAtlas can push
## uniforms onto it; a single shared instance means one call recolours the world.
static func get_opaque_material() -> ShaderMaterial:
	if _opaque_mat == null:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://src/world/voxel_terrain.gdshader")
		_opaque_mat = mat
	return _opaque_mat

static func _fluid_material() -> StandardMaterial3D:
	if _fluid_mat == null:
		_fluid_mat = StandardMaterial3D.new()
		_fluid_mat.vertex_color_use_as_albedo = true
		_fluid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_fluid_mat.roughness = 0.1
		_fluid_mat.metallic = 0.2
		_fluid_mat.albedo_color = Color(1, 1, 1, 0.75)
	return _fluid_mat

static var _opaque_mat: ShaderMaterial = null
static var _fluid_mat: StandardMaterial3D = null

## Parallel vertex arrays for one surface.
class SurfaceArrays:
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()

	func to_arrays() -> Array:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = positions
		arr[Mesh.ARRAY_NORMAL] = normals
		arr[Mesh.ARRAY_COLOR] = colors
		arr[Mesh.ARRAY_TEX_UV] = uvs
		arr[Mesh.ARRAY_TEX_UV2] = uv2s
		arr[Mesh.ARRAY_INDEX] = indices
		return arr
