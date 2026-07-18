class_name ChunkMesher
extends RefCounted
## Builds a renderable ArrayMesh from a chunk's voxels using culled meshing.
##
## Only faces that border a transparent block are emitted, so the interior of the
## terrain costs nothing. Each vertex carries an ambient-occlusion factor baked
## into its colour (the classic "0..3 neighbours" AO used by most voxel engines),
## which softens edges and gives the world the smoother, less-blocky read the
## design calls for without adding geometry.
##
## Neighbour lookups cross chunk borders via the `sampler` callable so faces at
## chunk seams cull correctly. The mesher does not touch the scene tree.

const CHUNK_SIZE := Chunk.CHUNK_SIZE
const CHUNK_HEIGHT := Chunk.CHUNK_HEIGHT

# Face definitions: normal + the four corner offsets (CCW) for each cube face.
const FACES := {
	"top":    {"normal": Vector3(0, 1, 0),  "dir": Vector3i(0, 1, 0)},
	"bottom": {"normal": Vector3(0, -1, 0), "dir": Vector3i(0, -1, 0)},
	"north":  {"normal": Vector3(0, 0, -1), "dir": Vector3i(0, 0, -1)},
	"south":  {"normal": Vector3(0, 0, 1),  "dir": Vector3i(0, 0, 1)},
	"west":   {"normal": Vector3(-1, 0, 0), "dir": Vector3i(-1, 0, 0)},
	"east":   {"normal": Vector3(1, 0, 0),  "dir": Vector3i(1, 0, 0)},
}

# Corner vertex offsets per face (unit cube, CCW when viewed from outside).
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
## Returns null when the chunk is entirely empty.
static func build(chunk: Chunk, sampler: Callable) -> ArrayMesh:
	# Opaque and transparent (water/leaves) surfaces go into separate arrays so
	# the water can use a translucent material.
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
		mesh.surface_set_material(mesh.get_surface_count() - 1, _opaque_material())
	if not fluid.positions.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, fluid.to_arrays())
		mesh.surface_set_material(mesh.get_surface_count() - 1, _fluid_material())
	return mesh

static func _emit_block(sa: SurfaceArrays, id: int, lx: int, ly: int, lz: int, gx: int, gz: int, sampler: Callable) -> void:
	var base_color := BlockDB.get_color(id)
	for face in FACES:
		var dir: Vector3i = FACES[face]["dir"]
		var nx := gx + dir.x
		var ny := ly + dir.y
		var nz := gz + dir.z
		var neighbor := int(sampler.call(nx, ny, nz))
		# Emit the face only if the neighbour doesn't hide it. A solid block
		# hides the face; a transparent block hides it only from another block
		# of the same type (so water surfaces stay single-sided, and leaves cull
		# against leaves).
		if BlockDB.is_solid(neighbor):
			continue
		if neighbor == id:
			continue
		_emit_face(sa, face, base_color, id, lx, ly, lz, gx, gz, sampler)

static func _emit_face(sa: SurfaceArrays, face: String, color: Color, id: int, lx: int, ly: int, lz: int, gx: int, gz: int, sampler: Callable) -> void:
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

	# Two triangles. Standard quad winding.
	sa.indices.append_array([start, start + 1, start + 2, start, start + 2, start + 3])

## Classic voxel ambient occlusion: darken a vertex based on how many of the
## three blocks touching that corner (two edges + one diagonal) are solid.
static func _vertex_ao(face: String, offset: Vector3, gx: int, ly: int, gz: int, sampler: Callable) -> float:
	var normal: Vector3 = FACES[face]["normal"]
	# Build two tangent axes on the face plane.
	var t1 := Vector3(normal.y, normal.z, normal.x)
	var t2 := normal.cross(t1)
	# Corner direction on the face, in {-1, +1} along each tangent.
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
	# When both sides are solid the corner is fully occluded regardless.
	if side1 and side2:
		occ = 3
	elif corner:
		occ += 1

	# Map occlusion 0..3 to a brightness multiplier.
	match occ:
		0: return 1.0
		1: return 0.8
		2: return 0.65
		_: return 0.5

static func _solid_at(p: Vector3, sampler: Callable) -> bool:
	return BlockDB.is_solid(int(sampler.call(int(round(p.x)), int(round(p.y)), int(round(p.z)))))

static func _opaque_material() -> StandardMaterial3D:
	if _opaque_mat == null:
		_opaque_mat = StandardMaterial3D.new()
		_opaque_mat.vertex_color_use_as_albedo = true
		_opaque_mat.roughness = 0.9
		_opaque_mat.metallic = 0.0
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

static var _opaque_mat: StandardMaterial3D = null
static var _fluid_mat: StandardMaterial3D = null

## Small helper bundling the parallel vertex arrays a surface needs.
class SurfaceArrays:
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	func to_arrays() -> Array:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = positions
		arr[Mesh.ARRAY_NORMAL] = normals
		arr[Mesh.ARRAY_COLOR] = colors
		arr[Mesh.ARRAY_INDEX] = indices
		return arr
