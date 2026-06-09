# Creating Safe Zones

Safe zones are no-attack bubbles around stations or key locations. NPCs inside a safe zone will not attack the player unless the player's reputation with that faction is extremely low.

---

## How the System Works

### Core Constants in `GlobalState.gd`

| Constant                  | Default Value             | Purpose                                              |
|---------------------------|---------------------------|------------------------------------------------------|
| `MAIN_STATION_POS`        | `Vector3(0, 0, 180)`     | Center position of the safe zone                     |
| `SAFE_ZONE_RADIUS`        | `250.0`                  | Radius of the safe zone in meters                    |
| `SAFE_ZONE_REP_THRESHOLD` | `-40.0`                  | NPCs won't attack if player rep is above this value  |

### The `is_in_safe_zone(world_pos)` Function

`GlobalState.is_in_safe_zone(world_pos: Vector3) -> bool` checks whether a given world position falls within any registered safe zone. It iterates through the `SAFE_ZONES` array and returns `true` if the position is within the radius of any entry.

### Where the Check Happens

In `NPCShip.gd`, inside `_physics_process()`, after the NPC determines whether it should be hostile toward the player, it calls `is_in_safe_zone()` on the player's position. If the player is inside a safe zone **and** their reputation with the NPC's faction is above `SAFE_ZONE_REP_THRESHOLD`, the NPC suppresses its attack.

### Minor Factions Ignore Safe Zones

Minor factions (outlaws) **always ignore safe zones**. They will attack the player regardless of location. This is intentional — they're lawless and have no respect for station authority.

---

## Adding a New Safe Zone

To add a new safe zone, simply add a new entry to the `SAFE_ZONES` array in `GlobalState.gd`. The system handles everything automatically.

Each entry is a dictionary with:

| Key        | Type      | Description                        |
|------------|-----------|------------------------------------|
| `position` | `Vector3` | World-space center of the zone     |
| `radius`   | `float`   | Radius of the zone in meters       |

### Example: Adding Iron Reach Outpost

```gdscript
var SAFE_ZONES = [
    {"position": MAIN_STATION_POS, "radius": SAFE_ZONE_RADIUS},
    {"position": Vector3(500, 0, -300), "radius": 200.0},  # Iron Reach Outpost
]
```

### Example: Adding Kova Station

```gdscript
var SAFE_ZONES = [
    {"position": MAIN_STATION_POS, "radius": SAFE_ZONE_RADIUS},
    {"position": Vector3(500, 0, -300), "radius": 200.0},   # Iron Reach Outpost
    {"position": Vector3(-400, 0, 600), "radius": 180.0},   # Kova Station
]
```

No other code changes are required. The `is_in_safe_zone()` function already iterates over the full array.

---

## Adjusting the Reputation Threshold

To change how hostile a player must be before safe zones stop protecting them, modify `SAFE_ZONE_REP_THRESHOLD` in `GlobalState.gd`:

```gdscript
const SAFE_ZONE_REP_THRESHOLD = -40.0  # Default: must drop below -40 to lose protection
```

A more negative value (e.g., `-60.0`) makes safe zones more forgiving. A less negative value (e.g., `-20.0`) makes them stricter.

---

## Design Notes

- **Safe zones are intentionally for major factions only.** Minor factions are outlaws and don't honor safe zones.
- **The rep threshold of `-40` means you have to really anger a faction** before even the station isn't safe. Casual skirmishes won't strip your protection — you need sustained hostility.
- Safe zones create natural "home base" areas where players can trade, take quests, and regroup without threat from allied or neutral factions.
