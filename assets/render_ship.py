# Blender 5.x — render INDYMiner GLB to transparent-background PNGs
# Usage:
#   blender -b -P render_ship.py -- --input <glb_path> --out_dir <dir> --name <basename>

import bpy
import sys
import os
import math
from mathutils import Vector

# ── Parse CLI args (Blender passes everything after "--" through to sys.argv) ──
argv = sys.argv
argv = argv[argv.index("--") + 1:] if "--" in argv else []

def arg(name, default=None):
    for i, a in enumerate(argv):
        if a == f"--{name}" and i + 1 < len(argv):
            return argv[i + 1]
    return default

input_path = arg("input", r"C:\CodingProjects\SpaceGame\assets\INDYMiner.glb")
out_dir    = arg("out_dir", r"C:\CodingProjects\SpaceGame\assets")
base_name  = arg("name", "INDYMiner_render")

# ── Fresh scene — strip the default cube/camera/light ─────────────────────────
bpy.ops.wm.read_factory_settings(use_empty=True)

# ── Import the GLB ───────────────────────────────────────────────────────────
print(f"[render_ship] Importing {input_path}")
before_objs = set(bpy.data.objects.keys())
bpy.ops.import_scene.gltf(filepath=input_path)
imported = [o for o in bpy.data.objects if o.name not in before_objs and o.type == 'MESH']
# Also catch empties / armature parents that might be the actual scene root
imported_all = [o for o in bpy.data.objects if o.name not in before_objs]
print(f"[render_ship] Imported {len(imported)} mesh + {len(imported_all) - len(imported)} other objects")
for o in imported_all:
    print(f"  - {o.name} ({o.type}) at {o.location} parent={o.parent.name if o.parent else 'None'} collections={[c.name for c in o.users_collection]}")
    if o.type == 'MESH' and o.data:
        print(f"    verts={len(o.data.vertices)} faces={len(o.data.polygons)} edges={len(o.data.edges)}")
        # Check for actual 3D depth
        if o.data.vertices:
            zs = [v.co.z for v in o.data.vertices]
            print(f"    z range: [{min(zs):.4f}, {max(zs):.4f}] depth={max(zs)-min(zs):.4f}")
            # If vertices are nearly coplanar (depth near 0), it's a plane
            if (max(zs) - min(zs)) < 0.01:
                print(f"    ⚠ MESH IS NEARLY PLANAR (depth < 0.01) — probably a flat textured plane")

# If the imported mesh is parented to an empty, the camera needs to be
# positioned in world space relative to the empty. We use the topmost
# parent's world matrix when computing bounds so the camera frames
# the visual hull, not just the geometry's local space.
def world_pos_chain(obj):
    """Walk parent chain to compute world position."""
    p = obj.matrix_world.translation
    return p

# Recompute bounds using world matrix of EACH imported object
def world_bounds_v2(objs):
    min_co = Vector((float('inf'),) * 3)
    max_co = Vector((float('-inf'),) * 3)
    for o in objs:
        for corner in o.bound_box:
            w = o.matrix_world @ Vector(corner)
            min_co.x = min(min_co.x, w.x); min_co.y = min(min_co.y, w.y); min_co.z = min(min_co.z, w.z)
            max_co.x = max(max_co.x, w.x); max_co.y = max(max_co.y, w.y); max_co.z = max(max_co.z, w.z)
    return min_co, max_co

min_co, max_co = world_bounds_v2(imported)
center = (min_co + max_co) * 0.5
size = (max_co - min_co)
max_dim = max(size.x, size.y, size.z)
print(f"[render_ship] Pre-recenter bounds: min={min_co} max={max_co} center={center} max_dim={max_dim}")

# Re-center: if the mesh has a parent, move the parent so the visual hull
# ends up at world origin. This is more robust than moving the mesh itself
# (which can break animations / armatures).
parents = set()
for o in imported:
    p = o.parent if o.parent else o
    parents.add(p)
for p in parents:
    p.location -= center

min_co, max_co = world_bounds_v2(imported)
size = (max_co - min_co)
max_dim = max(size.x, size.y, size.z)
print(f"[render_ship] Post-recenter bounds: min={min_co} max={max_co} max_dim={max_dim}")

if not imported:
    raise RuntimeError("No meshes imported from GLB")

# ── Compute the world-space bounding box of the imported geometry ────────────
def world_bounds(objs):
    min_co = Vector((float('inf'),) * 3)
    max_co = Vector((float('-inf'),) * 3)
    for o in objs:
        for corner in o.bound_box:
            w = o.matrix_world @ Vector(corner)
            min_co.x = min(min_co.x, w.x); min_co.y = min(min_co.y, w.y); min_co.z = min(min_co.z, w.z)
            max_co.x = max(max_co.x, w.x); max_co.y = max(max_co.y, w.y); max_co.z = max(max_co.z, w.z)
    return min_co, max_co

min_co, max_co = world_bounds(imported)
center = (min_co + max_co) * 0.5
size = (max_co - min_co)
max_dim = max(size.x, size.y, size.z)
print(f"[render_ship] Bounds: min={min_co} max={max_co} center={center} max_dim={max_dim}")

# ── Re-center the meshes at world origin (so the camera math is simple) ───────
for o in imported:
    o.location -= center

min_co, max_co = world_bounds(imported)
size = (max_co - min_co)
max_dim = max(size.x, size.y, size.z)

# ── Camera: orthographic, framed around the ship, side view by default ───────
cam_data = bpy.data.cameras.new("SideCamera")
cam_data.type = 'ORTHO'
cam_data.ortho_scale = max_dim * 1.15  # a bit of padding around the hull
cam_data.clip_end = max_dim * 50  # generous far clip in case of unit-scale

cam_obj = bpy.data.objects.new("SideCamera", cam_data)
bpy.context.scene.collection.objects.link(cam_obj)

# Default orientation: no rotation, just place at offset and let the
# camera look down its own -Z axis (Blender's default).
cam_obj.rotation_euler = (0, 0, 0)

bpy.context.scene.camera = cam_obj

# ── Lighting: one strong key light + a soft fill, plus World ambient ──────────
# Key light
key_data = bpy.data.lights.new("KeyLight", 'SUN')
key_data.energy = 8.0  # Crank up since the embedded texture is dark
key_data.color = (1.0, 0.95, 0.9)
key_obj = bpy.data.objects.new("KeyLight", key_data)
key_obj.location = (max_dim, max_dim * 0.5, max_dim * 0.8)
key_obj.rotation_euler = (math.radians(45), 0, math.radians(-35))
bpy.context.scene.collection.objects.link(key_obj)

# Fill light from the opposite side, cooler/dimmer
fill_data = bpy.data.lights.new("FillLight", 'SUN')
fill_data.energy = 3.0
fill_data.color = (0.7, 0.85, 1.0)
fill_obj = bpy.data.objects.new("FillLight", fill_data)
fill_obj.location = (-max_dim, -max_dim * 0.5, max_dim * 0.4)
fill_obj.rotation_euler = (math.radians(45), 0, math.radians(145))
bpy.context.scene.collection.objects.link(fill_obj)

# Rim light from above and behind to define the silhouette against the
# transparent background
rim_data = bpy.data.lights.new("RimLight", 'SUN')
rim_data.energy = 4.0
rim_data.color = (0.4, 0.7, 1.0)
rim_obj = bpy.data.objects.new("RimLight", rim_data)
rim_obj.location = (0, max_dim * 0.3, max_dim * 1.2)
rim_obj.rotation_euler = (math.radians(60), 0, 0)
bpy.context.scene.collection.objects.link(rim_obj)

# Ambient — Blender 5.x doesn't auto-assign a World to a fresh factory scene,
# so we have to create one and link it before toggling use_nodes.
if bpy.context.scene.world is None:
    new_world = bpy.data.worlds.new("AmbientWorld")
    bpy.context.scene.world = new_world
bpy.context.scene.world.use_nodes = True
world = bpy.context.scene.world
bg_node = world.node_tree.nodes.get('Background')
if bg_node:
    bg_node.inputs[0].default_value = (0.05, 0.05, 0.07, 1.0)  # very dark blue
    bg_node.inputs[1].default_value = 0.3

# ── Render settings: transparent background, PNG, decent quality ──────────────
scene = bpy.context.scene
# Blender 5.x renamed BLENDER_EEVEE_NEXT back to BLENDER_EEVEE. Cycles is the
# default, and we want it for cleaner alpha on metallic hulls.
scene.render.engine = 'CYCLES'
scene.cycles.samples = 64
scene.cycles.use_denoising = True
scene.cycles.device = 'CPU'  # GPU detection is finicky in headless; CPU is safe

scene.render.resolution_x = 1920
scene.render.resolution_y = 1080
scene.render.resolution_percentage = 100
scene.render.film_transparent = True   # alpha = 0 outside the ship
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
scene.render.image_settings.compression = 15

scene.view_settings.view_transform = 'Standard'
scene.view_settings.exposure = 0.0
scene.view_settings.gamma = 1.0

print("[render_ship] Using Cycles (64 samples, CPU)")

# ── Render multiple angles ───────────────────────────────────────────────────
# The ship's longest axis is Y (1.0m), so to see the "side" (long profile)
# we look along the X axis. For the front/back we look along the Y axis.
# For the top we look along the Z axis. The 3/4 view combines two.
angles = [
    # side: from +X, looking at origin — shows the long side profile
    ("side",    ( max_dim * 1.5, 0, 0),  (0, 0, 0)),
    # 3q front: from front-left, slightly above
    ("3q_left", (-max_dim * 0.8, -max_dim * 1.0, max_dim * 0.5), (0, 0, 0)),
    # 3q back: from rear-right
    ("3q_right",( max_dim * 0.8, max_dim * 1.0, max_dim * 0.5), (0, 0, 0)),
    # top: from above
    ("top",     (0, 0, max_dim * 1.8),   (0, 0, 0)),
    # front: from -Y (the front of the ship)
    ("front",   (0, -max_dim * 1.5, 0),  (0, 0, 0)),
]

os.makedirs(out_dir, exist_ok=True)

for suffix, cam_loc, target in angles:
    cam_obj.location = Vector(cam_loc)
    # Aim the camera at the target using look_at; this handles all the
    # rotation math for us so the camera always frames the model.
    direction = Vector(target) - Vector(cam_loc)
    rot_quat = direction.to_track_quat('-Z', 'Y')
    cam_obj.rotation_euler = rot_quat.to_euler()
    scene.render.filepath = os.path.join(out_dir, f"{base_name}_{suffix}.png")
    print(f"[render_ship] Rendering {suffix} from {cam_loc} looking at {target} -> {scene.render.filepath}")
    bpy.ops.render.render(write_still=True)

print("[render_ship] Done.")
