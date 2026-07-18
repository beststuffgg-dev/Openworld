class_name ChunkMesher
extends RefCounted
## Builds a renderable ArrayMesh from a chunk's voxels using culled meshing.
##
## Only faces that border a transparent block are emitted, so the interior of the
## terrain costs nothing. Each vertex carries:
##   - COLOR: the block colour, slightly varied per block to break up flatness,
##            with ambient occlusion (the classic 0..3 solid-neighbour method)
##            multiplied in to soften edges and give the less-blocky read.
##   - UV.x:  a seasonal tint weight (1 for grass/leaves, 0 otherwise) that the
##            terrain shader uses to recolour foliage per season with no remesh.
##
## Neighbour lookups cross chunk borders via the `sampler` callable so faces at
## chunk seams cull correctly. The mesher never touches the scene tree, so it is
## safe to call from a worker thread.

const CHUNK_SIZE := Chunk.CHUNK_SIZE
const CHUNK_HEIGHT := Chunk.CHUNK_HEIGHT

# Face definitions: outward normal + the neighbour direction to test for culling.
const FACES := {
	"top":    {"normal": Vector3(0, 1, 0),  "dir": Vector3i(0, 1, 0)},
	"bottom": {"normal": Vector3(0, -1, 0), "dir": Vector3i(0, -1, 0)},
	"north":  {"normal": Vector3(0, 0, -1), "dir": Vector3i(0, 0, -1)},
	"south":  {"normal": Vector3(0, 0, 1),  "dir": Vector3i(0, 0, 1)},
	"west":   {"normal": Vector3(-1, 0, 0), "dir": Vector3i(-1, 0, 0)},
	"east":   {"normal": Vector3(1, 0, 0),  "dir": Vector3i(1, 0, 0)},
}

# Corner vertex offsets per face (unit cube, CCW when viewed from outside so the
# generated winding is front-facing under the default back-face culling).
const FACE_VERTS := {
	"top":    [Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0), Vector3(0, 1, 0)],
	"bottom": [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)],
	"north":  [Vector3(1, 0, 0), Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0)],
	"south":  [Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1)],
	"west":   [Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0)],
	"east":   [Vector3(1, 0, 1), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1)],
}

## Builds an ArrayMesh for `chunk`. `sampler` is a Callable(gx, gy, gz) -> int id
## in world coordinates, used to read across chunk boundaries.
## Returns null when the chunk would produce no geometry.
static func build(chunk: Chunk, sampler: Callable) -> ArrayMesh:
	# Opaque and translucent (water) surfaces go into separate arrays so water
	# can use its own material.
	var opaque := SurfaceArrays.new()
	var fluid := SurfaceArrays.new()
	var base_x := chunk.cx * CHUNK_SIZE
	var base_z := chunk.cz * CHUNK_SIZE

	for ly in CHUNK_HEIGHT:
		for lz in CHUNK_SIZE:
			for lx in CHUNK_SIZE:
				var id := chunk.voxels[Chunk.index(lx, ly, lz)]
				if id == BlockDB.Type.AIR:
					continue
				var gx := base_x + lx
				var gz := base_z + lz
				var target := fluid if BlockDB.is_transparent(id) else opaque
				_emit_block(target, id, lx, ly, lz, gx, gz, sampler)

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

static func _emit_block(sa: SurfaceArrays, id: int, lx: int, ly: int, lz: int, gx: int, gz: int, sampler: Callable) -> void:
	# Slight per-block brightness variation breaks up large flat expanses of one
	# colour without any texture data.
	var variation := 0.9 + 0.1 * _hash01(gx, ly, gz)
	var c := BlockDB.get_color(id)
	var base_color := Color(c.r * variation, c.g * variation, c.b * variation, c.a)
	var tint_weight := 1.0 if BlockDB.is_tintable(id) else 0.0

	for face in FACES:
		var dir: Vector3i = FACES[face]["dir"]
		var nx := gx + dir.x
		var ny := ly + dir.y
		var nz := gz + dir.z
		var neighbor := int(sampler.call(nx, ny, nz))
		# Emit the face only if the neighbour doesn't hide it. Solid neighbours
		# cull; a transparent block hides a face only from another block of the
		# same type (so a water surface stays single-sided).
		if BlockDB.is_solid(neighbor):
			continue
		if neighbor == id:
			continue
		_emit_face(sa, face, base_color, tint_weight, id, lx, ly, lz, gx, gz, sampler)

static func _emit_face(sa: SurfaceArrays, face: String, color: Color, tint_weight: float, id: int, lx: int, ly: int, lz: int, gx: int, gz: int, sampler: Callable) -> void:
	var normal: Vector3 = FACES[face]["normal"]
	var corners: Array = FACE_VERTS[face]
	var origin := Vector3(lx, ly, lz)
	var start := sa.positions.size()

	for i in 4:
		var offset: Vector3 = corners[i]
		var ao := 1.0
		if not BlockDB.is_transparent(id):
			ao = _vertex_ao(face, offset, gx, ly, gz, sampler)
		var shaded := Color(color.r * ao, color.g * ao, color.b * ao, color.a)
		sa.positions.append(origin + offset)
		sa.normals.append(normal)
		sa.colors.append(shaded)
		sa.uvs.append(Vector2(tint_weight, 0.0))

	sa.indices.append_array(PackedInt32Array([start, start + 1, start + 2, start, start + 2, start + 3]))

## Classic voxel ambient occlusion: darken a vertex by how many of the three
## blocks touching that corner (two edges + one diagonal) are solid.
static func _vertex_ao(face: String, offset: Vector3, gx: int, ly: int, gz: int, sampler: Callable) -> float:
	var normal: Vector3 = FACES[face]["normal"]
	var t1 := Vector3(normal.y, normal.z, normal.x)
	var t2 := normal.cross(t1)
	var c := offset - Vector3(0.5, 0.5, 0.5) + normal * 0.5
	var s1 := signf(c.dot(t1))
	var s2 := signf(c.dot(t2))

	var base := Vector3(gx, ly, gz) + normal
	var side1 := _solid_at(base + t1 * s1, sampler)
	var side2 := _solid_at(base + t2 * s2, sampler)
	var corner := _solid_at(base + t1 * s1 + t2 * s2, sampler)

	var occ := 0
	if side1: occ += 1
	if side2: occ += 1
	if side1 and side2:
		occ = 3
	elif corner:
		occ += 1

	match occ:
		0: return 1.0
		1: return 0.8
		2: return 0.65
		_: return 0.5

static func _solid_at(p: Vector3, sampler: Callable) -> bool:
	return BlockDB.is_solid(int(sampler.call(int(round(p.x)), int(round(p.y)), int(round(p.z)))))

## Deterministic per-position value in [0, 1) for cheap colour variation.
static func _hash01(x: int, y: int, z: int) -> float:
	var h: int = (x * 73856093) ^ (y * 19349663) ^ (z * 83492791)
	h = h & 0x7fffffff
	return float(h % 1000) / 1000.0

# --- Shared materials ------------------------------------------------------

## The opaque terrain material. Public so the SeasonManager can push season tint
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
	var indices := PackedInt32Array()

	func to_arrays() -> Array:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = positions
		arr[Mesh.ARRAY_NORMAL] = normals
		arr[Mesh.ARRAY_COLOR] = colors
		arr[Mesh.ARRAY_TEX_UV] = uvs
		arr[Mesh.ARRAY_INDEX] = indices
		return arr
