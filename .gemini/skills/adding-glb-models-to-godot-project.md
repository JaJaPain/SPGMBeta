# Adding GLB Models to a Godot 4 Project

## Overview

This skill documents how GLB (binary glTF) 3D models were added to the SpaceGame project as dockable outpost stations, including critical pitfalls with scene loading, model scaling, and AABB-based auto-centering.

---

## The Problem

Two new space station models (`space_station1.glb` and `space_station2.glb`) needed to be added as dockable outpost stations. Multiple attempts with custom `.tscn` scene files and a dedicated `OutpostStation.gd` script failed silently — Godot loaded the resources but **never instantiated the nodes** in the scene tree.

## Diagnosis Process

### Step 1: Verbose Console Output

Running the game with `--verbose` revealed that Godot loaded the outpost scene resources:

```
Loading resource: res://scenes/outpost_iron_reach.tscn
Loading resource: res://scripts/OutpostStation.gd
Loading resource: res://scenes/outpost_kova.tscn
```

But no `[OutpostStation]` debug prints ever appeared — meaning `_ready()` never fired.

### Step 2: push_error() Confirmation

Adding `push_error()` calls (which write to stderr and can't be silently swallowed) to both `Station.gd` and `MainScene.gd` confirmed:

- **Station.gd `_ready()` fires** — the main station works
- **MainScene.gd `_ready()` fires** — the scene loads
- **MainScene children list**: `["WorldEnvironment", "DirectionalLight3D", "GasGiant", "RockyPlanet", "Station", "PlayerShip", "CanvasLayer"]`

The outpost nodes (`IronReachOutpost`, `KovaStation`) were **completely absent** from the runtime scene tree despite being declared in `main.tscn`. Godot silently dropped them during instantiation with zero errors or warnings.

### Step 3: Godot MCP Addon (godot_ai game_helper)

The project includes the `godot_ai` addon (`addons/godot_ai/`) which registers as an MCP (Model Context Protocol) server. This was used to:

- **Inspect the live scene tree** via `game_helper/get_scene_tree` to confirm node presence/absence at runtime
- **Query group membership** via `game_helper/find_nodes` with `{"group": "station"}` to verify station registration
- **Capture game logs** via `game_helper/get_logs` to see errors that might not appear in console output

The addon confirmed that the outpost nodes were not in the scene tree at runtime, corroborating the `push_error()` diagnosis. It was particularly useful for verifying group membership without needing to add debug code.

### Root Cause

Godot 4.6 silently fails to instantiate nodes from custom `.tscn` files that were hand-crafted (not created through the Godot editor) when they reference scripts via `path=` without proper UID resolution. The resource loads, but the node never enters the tree. **No error is emitted.**

---

## The Solution: Reuse a Working Scene

Instead of debugging the custom scene files, the working `station.tscn` was reused for all three stations. The outpost-specific behavior was added via `@export` property overrides in `main.tscn`.

### Architecture

```
station.tscn (single shared scene)
├── Station.gd (shared script with @export vars)
├── CollisionShape3D (BoxShape3D 35x30x35)
├── Core (CylinderMesh — hidden for outposts)
└── Ring (TorusMesh — hidden for outposts)

main.tscn instances:
├── Station           → default (procedural mesh, 5x parent scale)
├── IronReachOutpost  → model_path="res://assets/space_station1.glb" (1x parent scale)
└── KovaStation       → model_path="res://assets/space_station2.glb" (1x parent scale)
```

### Key @export Variables in Station.gd

```gdscript
@export var display_name: String = ""           # Shown in UI overview
@export var station_type: String = "full_service"  # "full_service" or "outpost"
@export var model_path: String = ""             # GLB path, empty = use procedural mesh
@export var model_instance_scale: float = 1.0   # Scale for the GLB model itself
```

### GLB Loading in _ready()

```gdscript
if model_path != "":
    var model_scene = load(model_path)
    if model_scene:
        var model_instance = model_scene.instantiate()
        model_instance.scale = Vector3.ONE * model_instance_scale
        add_child(model_instance)
        _center_model(model_instance)
        # Hide procedural mesh
        get_node_or_null("Core").visible = false
        get_node_or_null("Ring").visible = false
```

---

## Model Scaling

### The Two-Level Scale Problem

Godot scenes have TWO levels of scale that multiply together:

1. **Parent transform scale** — set in the `[node]` declaration in `main.tscn`
2. **model_instance_scale** — applied to the GLB Node3D inside the script

```
Effective size = GLB native size × model_instance_scale × parent transform scale
```

The main station uses a 5x parent scale because its procedural mesh is small (25-unit cylinder). But if outposts ALSO inherit this 5x parent scale, the GLB models become enormous.

### Correct Approach

- **Procedural mesh stations**: Use parent transform scale (e.g., 5x) to size up the small meshes
- **GLB model stations**: Set parent transform to **1x** and use `model_instance_scale` exclusively

### Example Calculations

| Station | GLB Native Size | model_instance_scale | Parent Scale | Effective Size |
|---------|----------------|---------------------|-------------|---------------|
| Main Station | 25 (cylinder) | N/A | 5x | ~125 |
| Iron Reach | ~53 | 2.0 | 1x | ~107 |
| Kova | ~5.7 | 20.0 | 1x | ~114 |

### TSCN Property Overrides

```ini
[node name="IronReachOutpost" parent="." instance=ExtResource("4_station")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 2350, 0, 1150)
display_name = "IRON REACH OUTPOST"
model_path = "res://assets/space_station1.glb"
model_instance_scale = 2.0

[node name="KovaStation" parent="." instance=ExtResource("4_station")]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, -1650, 0, 2200)
display_name = "KOVA STATION"
model_path = "res://assets/space_station2.glb"
model_instance_scale = 20.0
```

---

## AABB Auto-Centering

GLB models often have their origin at the bottom or at an arbitrary point. This causes the targeting reticle to appear at the wrong position. The fix: compute the merged AABB of all meshes and shift the model so its visual center sits at the node's origin.

### Critical: Full Transform Chain

GLB scenes have nested hierarchies (e.g., `GLBRoot > Skeleton3D > MeshInstance3D`). When computing the AABB in model-root-local space, you **must walk the full transform chain**, not just use `mesh.transform` (which is only one level).

**Wrong** (only one level):
```gdscript
combined_aabb = mesh.transform * mesh.get_aabb()  # BROKEN for nested GLBs
```

**Correct** (full chain):
```gdscript
func _relative_transform_to(from_node: Node3D, to_ancestor: Node3D) -> Transform3D:
    var xform := from_node.transform
    var node := from_node.get_parent()
    while node != to_ancestor and node != null:
        if node is Node3D:
            xform = (node as Node3D).transform * xform
        node = node.get_parent()
    return xform
```

### Applying the Offset

The center is in model-root-local space (pre-scale). To convert to the parent's coordinate space:

```gdscript
model_root.position -= center * model_instance_scale
```

---

## Checklist for Adding New GLB Models

1. **Place the `.glb` file** in `assets/` (e.g., `res://assets/my_model.glb`)
2. **Ensure `.glb` is in `.gitignore`** — the project already has `*.glb` covered
3. **Add a new node instance** in `main.tscn` using the existing `station.tscn`:
   ```ini
   [node name="MyStation" parent="." instance=ExtResource("4_station")]
   transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, X, Y, Z)
   display_name = "MY STATION"
   station_type = "outpost"
   model_path = "res://assets/my_model.glb"
   model_instance_scale = <adjust based on GLB native size>
   ```
4. **Set parent scale to 1x** — let `model_instance_scale` handle sizing
5. **Check the console output** for the auto-center log:
   ```
   [Station] Auto-centered 'MyStation': AABB center=(x, y, z) size=(w, h, d)
   ```
6. **Adjust `model_instance_scale`** so the effective size is ~100-130 world units (comparable to the main station)

## Key Lessons

- **Never hand-craft `.tscn` files** for new node types without testing in the Godot editor first — Godot may silently drop them
- **Reuse working scenes** with `@export` property overrides instead of creating new scene/script pairs
- **Always separate parent scale from model scale** — the 5x parent transform was designed for procedural meshes and shouldn't apply to GLB models
- **Use `push_error()` not `print()`** for critical diagnostics — `print()` output can be swallowed by console buffering
- **Use the Godot MCP addon** (`godot_ai game_helper`) to inspect the live scene tree and verify node group membership without restarting the game
