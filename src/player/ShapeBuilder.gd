class_name ShapeBuilder
extends RefCounted
## Generates the voxel set for a build shape from two points + an extent.
##
## Shapes are defined by two picked voxels A and B (and a scroll-adjustable
## `extent` for the shapes that need a third dimension). `flat` produces the
## 2D (single-layer) variant; otherwise the shape is a solid 3D volume. Sizes are
## clamped so a stray pick can't try to place millions of blocks.

enum Shape { CUBE, SPHERE, SLOPE, CYLINDER }

const MAX_RADIUS := 40
const MAX_SPAN := 160

static func shape_name(s: int) -> String:
	return ["Cube", "Sphere", "Slope", "Cylinder"][s]

## Returns an Array of Vector3i voxel positions for the shape.
static func generate(shape: int, flat: bool, a: Vector3i, b: Vector3i, extent: int) -> Array:
	match shape:
		Shape.SPHERE:
			return _sphere(a, b, flat)
		Shape.SLOPE:
			return _slope(a, b, extent, flat)
		Shape.CYLINDER:
			return _cylinder(a, b, extent, flat)
		_:
			return _cube(a, b, flat)

static func _cube(a: Vector3i, b: Vector3i, flat: bool) -> Array:
	var lo := Vector3i(mini(a.x, b.x), mini(a.y, b.y), mini(a.z, b.z))
	var hi := Vector3i(maxi(a.x, b.x), maxi(a.y, b.y), maxi(a.z, b.z))
	# Clamp span so an accidental huge pick can't lock the game up.
	hi.x = mini(hi.x, lo.x + MAX_SPAN)
	hi.y = mini(hi.y, lo.y + MAX_SPAN)
	hi.z = mini(hi.z, lo.z + MAX_SPAN)
	var out := []
	var y_range := [a.y] if flat else range(lo.y, hi.y + 1)
	for y in y_range:
		for x in range(lo.x, hi.x + 1):
			for z in range(lo.z, hi.z + 1):
				out.append(Vector3i(x, y, z))
	return out

static func _sphere(a: Vector3i, b: Vector3i, flat: bool) -> Array:
	var out := []
	if flat:
		var r := clampi(int(round(Vector2(b.x - a.x, b.z - a.z).length())), 0, MAX_RADIUS)
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if dx * dx + dz * dz <= r * r:
					out.append(a + Vector3i(dx, 0, dz))
	else:
		var r := clampi(int(round(Vector3(b - a).length())), 0, MAX_RADIUS)
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				for dz in range(-r, r + 1):
					if dx * dx + dy * dy + dz * dz <= r * r:
						out.append(a + Vector3i(dx, dy, dz))
	return out

## A ramp rising from A to B, extruded sideways by `extent`. Solid (walkable) or,
## when flat, just the sloped surface.
static func _slope(a: Vector3i, b: Vector3i, extent: int, flat: bool) -> Array:
	var out := []
	var dx := b.x - a.x
	var dz := b.z - a.z
	var dy := b.y - a.y
	var run_on_x := absi(dx) >= absi(dz)
	var run_len := clampi(maxi(absi(dx) if run_on_x else absi(dz), 1), 1, MAX_SPAN)
	var srun := signi(dx) if run_on_x else signi(dz)
	var sperp := signi(dz) if run_on_x else signi(dx)
	if sperp == 0:
		sperp = 1
	var depth := clampi(extent, 1, MAX_SPAN)
	for i in range(run_len + 1):
		var surface_y := a.y + int(round(dy * float(i) / float(run_len)))
		var rx := a.x + (srun * i if run_on_x else 0)
		var rz := a.z + (0 if run_on_x else srun * i)
		for w in range(depth):
			var px := rx + (0 if run_on_x else sperp * w)
			var pz := rz + (sperp * w if run_on_x else 0)
			if flat:
				out.append(Vector3i(px, surface_y, pz))
			else:
				for y in range(mini(a.y, surface_y), surface_y + 1):
					out.append(Vector3i(px, y, pz))
	return out

## A vertical cylinder: base centred at A, radius = horizontal distance to B,
## height = |B.y - A.y| (>= 1), or a single-layer disc when flat.
static func _cylinder(a: Vector3i, b: Vector3i, extent: int, flat: bool) -> Array:
	var out := []
	var r := clampi(int(round(Vector2(b.x - a.x, b.z - a.z).length())), 0, MAX_RADIUS)
	var height := 1 if flat else clampi(maxi(absi(b.y - a.y), maxi(extent, 1)), 1, MAX_SPAN)
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			if dx * dx + dz * dz <= r * r:
				for h in range(height):
					out.append(a + Vector3i(dx, h, dz))
	return out
