class_name ChunkMesher
extends RefCounted
## Builds a renderable ArrayMesh for one VERTICAL SECTION of a chunk column using
## GREEDY meshing.
##
## A column stores all its voxels in one array; `build_section` meshes only the
## y-range [y_lo, y_hi) of it, while still SAMPLING the full column (and
## horizontal neighbours via `sampler`) so face culling across section and chunk
## boundaries stays correct. Each vertical section becomes its own MeshInstance,
## which gives free per-section frustum culling, lets empty sections cost nothing,
## and means an edit only re-meshes the section(s) it touches.
##
## Greedy meshing merges coplanar faces of the same block into large rectangles.
## To avoid a boundary face being emitted by both the section above and below, a
## y-face is only emitted by the section that owns the solid cell (the owner
## filter below). Attributes per vertex: UV = tiling coords, UV2 = atlas tile
## origin, COLOR.a = seasonal tint weight. SSAO supplies edge shading. The mesher
## never touches the scene tree, so it is safe on a worker thread.

const CS := Chunk.CHUNK_SIZE
const CH := Chunk.CHUNK_HEIGHT

## Builds an ArrayMesh for the section spanning column-y [y_lo, y_hi). `sampler`
## is Callable(gx, gy, gz) -> int id in world voxel coordinates. Returns null when
## the section has no visible geometry.
static func build_section(chunk: Chunk, sampler: Callable, y_lo: int, y_hi: int) -> ArrayMesh:
	var opaque := SurfaceArrays.new()
	var fluid := SurfaceArrays.new()
	var base_x := chunk.cx * CS
	var base_z := chunk.cz * CS

	for d in 3:
		_greedy_axis(chunk, sampler, base_x, base_z, d, y_lo, y_hi, opaque, fluid)

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

# --- LOD: coarse whole-column mesh -----------------------------------------

## Meshes an entire column at 1/step resolution into a single mesh, for distant
## columns. Each coarse cell samples the fine voxel at its centre, and quads are
## scaled by `step`. No per-section split or owner filter is needed (the whole
## column is one mesh); interior faces still cull, so buried rock stays cheap.
## Minor cracks can appear where a coarse column meets a finer neighbour — an
## accepted first-pass limitation (skirts/stitching are a later refinement).
static func build_column_lod(chunk: Chunk, sampler: Callable, step: int) -> ArrayMesh:
	var opaque := SurfaceArrays.new()
	var fluid := SurfaceArrays.new()
	var base_x := chunk.cx * CS
	var base_z := chunk.cz * CS
	@warning_ignore("integer_division")
	var cs := CS / step
	@warning_ignore("integer_division")
	var ch := CH / step

	for d in 3:
		_greedy_axis_coarse(chunk, sampler, base_x, base_z, d, cs, ch, step, opaque, fluid)

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

static func _greedy_axis_coarse(chunk: Chunk, sampler: Callable, base_x: int, base_z: int, d: int, cs: int, ch: int, step: int, opaque: SurfaceArrays, fluid: SurfaceArrays) -> void:
	var u := (d + 1) % 3
	var v := (d + 2) % 3
	var du := ch if u == 1 else cs
	var dv := ch if v == 1 else cs
	var sdim := ch if d == 1 else cs

	var mask_op := PackedInt32Array()
	var mask_fl := PackedInt32Array()
	mask_op.resize(du * dv)
	mask_fl.resize(du * dv)

	for slice in range(-1, sdim):
		var n := 0
		for j in dv:
			for i in du:
				var a := _cvox(chunk, sampler, base_x, base_z, _pos(d, u, v, slice, i, j), step)
				var b := _cvox(chunk, sampler, base_x, base_z, _pos(d, u, v, slice + 1, i, j), step)
				mask_op[n] = _face_opaque(a, b)
				mask_fl[n] = _face_fluid(a, b)
				n += 1
		_emit_plane(mask_op, du, dv, 0, 0, d, u, v, slice, opaque, false, step)
		_emit_plane(mask_fl, du, dv, 0, 0, d, u, v, slice, fluid, true, step)

## Samples the representative voxel at the centre of a coarse cell.
static func _cvox(chunk: Chunk, sampler: Callable, base_x: int, base_z: int, cell: Array, step: int) -> int:
	@warning_ignore("integer_division")
	var half := step / 2
	var fx: int = cell[0] * step + half
	var fy: int = cell[1] * step + half
	var fz: int = cell[2] * step + half
	if fx >= 0 and fx < CS and fz >= 0 and fz < CS:
		if fy < 0 or fy >= CH:
			return BlockDB.Type.AIR
		return chunk.voxels[Chunk.index(fx, fy, fz)]
	return int(sampler.call(base_x + fx, fy, base_z + fz))

# --- Greedy meshing --------------------------------------------------------

static func _dim(axis: int) -> int:
	return CH if axis == 1 else CS

static func _greedy_axis(chunk: Chunk, sampler: Callable, base_x: int, base_z: int, d: int, y_lo: int, y_hi: int, opaque: SurfaceArrays, fluid: SurfaceArrays) -> void:
	var u := (d + 1) % 3
	var v := (d + 2) % 3
	# The y axis (1) is restricted to this section; x/z span their full chunk.
	var u_lo := y_lo if u == 1 else 0
	var u_hi := y_hi if u == 1 else _dim(u)
	var v_lo := y_lo if v == 1 else 0
	var v_hi := y_hi if v == 1 else _dim(v)
	var du := u_hi - u_lo
	var dv := v_hi - v_lo
	if du <= 0 or dv <= 0:
		return

	# Slice sweep along d. For the y axis we walk the section's boundaries.
	var slice_lo := (y_lo - 1) if d == 1 else -1
	var slice_hi := (y_hi - 1) if d == 1 else (_dim(d) - 1)

	var mask_op := PackedInt32Array()
	var mask_fl := PackedInt32Array()
	mask_op.resize(du * dv)
	mask_fl.resize(du * dv)

	for slice in range(slice_lo, slice_hi + 1):
		var n := 0
		for j in range(v_lo, v_hi):
			for i in range(u_lo, u_hi):
				var pa := _pos(d, u, v, slice, i, j)
				var pb := _pos(d, u, v, slice + 1, i, j)
				var a := _vox(chunk, sampler, base_x, base_z, pa)
				var b := _vox(chunk, sampler, base_x, base_z, pb)
				var mo := _face_opaque(a, b)
				var mf := _face_fluid(a, b)
				if d == 1:
					mo = _owner_filter(mo, slice, y_lo, y_hi)
					mf = _owner_filter(mf, slice, y_lo, y_hi)
				mask_op[n] = mo
				mask_fl[n] = mf
				n += 1
		_emit_plane(mask_op, du, dv, u_lo, v_lo, d, u, v, slice, opaque, false)
		_emit_plane(mask_fl, du, dv, u_lo, v_lo, d, u, v, slice, fluid, true)

## For y-faces, only the section that owns the solid cell emits the face:
##   +val (face of the cell below the plane) -> owner y = slice
##   -val (face of the cell above the plane) -> owner y = slice + 1
## Faces owned by a cell outside [y_lo, y_hi) belong to the adjacent section.
static func _owner_filter(val: int, slice: int, y_lo: int, y_hi: int) -> int:
	if val > 0 and slice < y_lo:
		return 0
	if val < 0 and slice + 1 >= y_hi:
		return 0
	return val

## Signed block id of the opaque face between a and b (b = a + axis), else 0.
## Positive => normal +axis (owned by a); negative => normal -axis (owned by b).
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

static func _emit_plane(mask: PackedInt32Array, du: int, dv: int, u_lo: int, v_lo: int, d: int, u: int, v: int, slice: int, sa: SurfaceArrays, is_fluid: bool, scale: int = 1) -> void:
	var lj := 0
	while lj < dv:
		var li := 0
		while li < du:
			var c := mask[li + lj * du]
			if c == 0:
				li += 1
				continue
			# Grow width along u.
			var w := 1
			while li + w < du and mask[(li + w) + lj * du] == c:
				w += 1
			# Grow height along v while the whole row matches.
			var h := 1
			var done := false
			while lj + h < dv and not done:
				for k in w:
					if mask[(li + k) + (lj + h) * du] != c:
						done = true
						break
				if not done:
					h += 1
			_emit_quad(sa, d, u, v, slice, u_lo + li, v_lo + lj, w, h, c, is_fluid, scale)
			for hh in h:
				for ww in w:
					mask[(li + ww) + (lj + hh) * du] = 0
			li += w
		lj += 1

## `scale` (1 for full detail, 2/4/… for LOD) multiplies voxel positions so a
## coarse quad covers `scale` voxels per cell.
static func _emit_quad(sa: SurfaceArrays, d: int, u: int, v: int, slice: int, i: int, j: int, w: int, h: int, c: int, is_fluid: bool, scale: int = 1) -> void:
	var id := absi(c)
	var positive := c > 0
	var base := _axis(d, (slice + 1) * scale) + _axis(u, i * scale) + _axis(v, j * scale)
	var uax := _axis(u, w * scale)
	var vax := _axis(v, h * scale)
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

## Reads a voxel id at column-local position `p` ([x, y, z]); reads the full
## column directly (so vertical section boundaries cull correctly) and falls back
## to the world sampler for horizontal neighbours in adjacent columns.
static func _vox(chunk: Chunk, sampler: Callable, base_x: int, base_z: int, p: Array) -> int:
	var px: int = p[0]
	var py: int = p[1]
	var pz: int = p[2]
	if px >= 0 and px < CS and pz >= 0 and pz < CS:
		if py < 0 or py >= CH:
			return BlockDB.Type.AIR
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
