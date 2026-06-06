# Transitioning EVE Space Game to Godot 4

This document outlines the detailed transition plan to port our EVE-inspired 3D space game from Ursina/Panda3D to **Godot Engine 4.x**.

Godot 4 provides native support for `.glb` models, standard PBR material imports, built-in raycasting, robust UI layout containers, and text-based scene configuration, solving the rendering bugs (like transparent depth sorting holes) and scaling bugs we encountered.

---

## Workspace Cleanup Status

The workspace has been successfully cleaned of all Ursina/Python logic and model variations:
- **Restored**: Original unflattened models `F1HP.glb`, `INDYMiner.glb`, `faction1.glb`, and `faction2.glb` are restored to their original full-thickness states.
- **Removed**: All flat variations (`*_flat.glb`), texture-projection scripts (`project_textures_precise.py`, etc.), temporary extracted textures, python scripts (`main.py`, `entities/*.py`, etc.), and execution cache folders.
- **Preserved**: Original turnaround images in `Ships/` and audio assets in `BackgroundMusic/`, `SpaceShipExplosion/`, `WeaponFire/`, and `assets/`.

---

## Godot Project Layout

We will use a clean, modular structure where scenes (`.tscn`) and scripts (`.gd`) are separated:

```
SpaceGame/
├── project.godot                # Godot project file
├── scenes/                      # Scene trees
│   ├── main.tscn                # Main space game environment
│   ├── player_ship.tscn         # Player ship scene
│   ├── npc_ship.tscn            # Base NPC ship scene
│   ├── asteroid.tscn            # Mineable asteroid scene
│   └── station.tscn             # Space station docking scene
├── scripts/                     # GDScript logic files
│   ├── GlobalState.gd           # Autoloaded global variables (cargo, speed, target)
│   ├── PlayerShip.gd            # Player navigation and flight controls
│   ├── NPCShip.gd               # NPC AI combat and patrol logic
│   ├── Asteroid.gd              # Resource management
│   ├── Station.gd               # Docking logic
│   ├── UIManager.gd             # Overview, HUD, Right-Click menus, Pause overlay
│   └── AudioManager.gd          # Autoloaded music/sfx coordinator
├── assets/                      # Raw 3D files and textures
│   ├── F1HP.glb                 # Amarr model with 4 weapon nodes
│   ├── INDYMiner.glb            # Mining ship model
│   ├── faction1.glb             # General Amarr model
│   ├── faction2.glb             # Caldari / Minmatar model
│   └── textures/                # Space skybox and celestial body maps
└── audio/                       # Sound effects and music files
```

---

## 3D Model Integration

In Godot, importing GLB models is automatic and robust:
1. **Mesh Import**: Placing `INDYMiner.glb`, `faction2.glb`, and `F1HP.glb` directly in the `assets/` directory will prompt Godot to generate `.import` files automatically.
2. **Materials**: Godot maps embedded textures directly to standard `ORMMaterial3D` or `StandardMaterial3D` parameters, preserving original colors and textures.
3. **Hardpoint Spawning (Amarr Ship)**:
   - Godot imports nodes named `TopRightGun`, `BottomRightGun.001`, `TopLeftGun`, and `BottomLeftGun.001` as standard `Node3D` nodes in the imported scene tree.
   - In GDScript, we can fetch their global positions directly using:
     ```gdscript
     var spawn_pos = $F1HP/geometry_0/TopRightGun.global_position
     ```

---

## Logic Porting Plan

### 1. Global Game State (`GlobalState.gd`)
Registered as an **Autoload (Singleton)** in Godot:
- Tracks: `player_credits`, `cargo`, `cargo_max`, `mining_yield`, `laser_range`, `active_target` (Node3D).
- Exposes signals (e.g. `cargo_changed`, `target_selected`) so UI elements update reactively.

### 2. Player Ship Controller (`PlayerShip.gd`)
Attached to a `CharacterBody3D` or `Node3D`:
- **Click-to-Move / Double-Click Steering**:
  - Casts a ray from camera cursor position using `camera.project_ray_origin(mouse_pos)` and `project_ray_normal(mouse_pos)`.
  - Determines 3D destination point on a virtual plane.
- **Flight Autopilot**:
  - Implements state machine: `APPROACH`, `ORBIT`, `DOCK`, `MINE`, `ATTACK`, or `MANUAL`.
  - Orbit behavior calculated via tangent vectors around the target.
- **Mining Laser Visual**:
  - Rendered using an instanced cylinder mesh scaled and rotated to face the asteroid, or a `GPUParticles3D` beam.

### 3. NPC AI Patrolling & Combat (`NPCShip.gd`)
Attached to `CharacterBody3D` for Caldari, Amarr, and Minmatar factions:
- State machine tracking `PATROL`, `CHASE`, `ATTACK`.
- Alternate hardpoint firing cycles through child Node3D markers.

### 4. UI Manager (`UIManager.gd`)
Main canvas containing Control nodes:
- **Overview List**: An `ItemList` container populated with active nodes in the scene tree.
- **Context Menu**: A popup menu showing contextual flight actions (Orbit, Approach, Dock, Mine, Attack).
- **HUD Overlays**: Labels for Shield, Armor, Hull, and Cargo Capacity.
- **Cargo alert**: Connects to `GlobalState` signals to play `Cargo Full.mp3` once via `AudioStreamPlayer`.

---

## Agentic Godot Workflow (AI Pair Programming)

Since we are developing this code in a headless or terminal-based sandbox, we will follow these agentic practices:
1. **Text-based Scenes (`.tscn`)**: We will write Godot scene files in text format. An example minimal 3D scene structure:
   ```gdscript
   [gd_scene load_steps=2 format=3]
   [node name="Main" type="Node3D"]
   [node name="DirectionalLight3D" type="DirectionalLight3D" parent="."]
   ```
2. **Code Correctness & Syntax Check**:
   - We will write GDScript logic in separate `.gd` files.
   - We can check GDScript file correctness by invoking Godot headlessly via command-line options.

---

## Verification Plan

### Headless Verification
To verify code logic and ensure there are no compilation errors:
- Command: `godot --headless --script scripts/GlobalState.gd` or running verification scripts.

### Manual Verification
1. Open the project in the Godot Editor.
2. Verify GLB model geometry is completely solid with zero holes or texture distortions.
3. Launch game play to test flight controls, Overview navigation, and context menu autopilot mechanics.
