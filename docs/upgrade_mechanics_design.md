# Ship Upgrades: Min-Max Mechanics Design

This document outlines the proposed design for the min-maxing mechanics of ship upgrades.

## Core Concept: The Power Budget

Every ship in the game has a strict **Power Budget** dictated by its **Powerplant**. You cannot just buy every upgrade for your ship; you must carefully balance your power consumption based on your playstyle.

When a player first acquires a ship, **every component (including the Powerplant) starts at Tier 1**. The Tier 1 Powerplant capacity is explicitly capped to equal the exact total power draw of all Tier 1 components combined. This means the player must upgrade their Powerplant *before* they can upgrade any other system, forcing them to spend time and materials to begin their progression.

- **Power Capacity**: The total energy output of your current Powerplant. Upgrading to the next tier of Powerplant (e.g., Mk I to Mk II) grants exactly enough incremental capacity to support *one* subsystem upgrade.
- **Power Draw**: The sum of energy consumed by all active systems (Weapons, Shields, Engines, Mining Laser).
- **Hard Min-Max Limit**: The maximum tier Powerplant will *never* provide enough capacity to max out every subsystem simultaneously. You are forced to prioritize which systems to upgrade.
- **Rule**: `Total Power Draw <= Power Capacity`. If an upgrade pushes your draw over the capacity, you cannot install it until you upgrade the Powerplant or downgrade another system.

> [!IMPORTANT]
> The Powerplant itself can only be upgraded to a certain maximum tier per ship hull. This forces the player into tough decisions: do you want a tanky slow ship, a fast glass-cannon, or a dedicated mining vessel?

## The Upgrade Slots & Dependencies

### 1. Powerplant (The Enabler)
- Determines the total Power Capacity.
- Costs Credits to upgrade, but doesn't consume power itself.
- Hard-capped by the specific ship hull (e.g., the INDY Miner can only fit up to a Class-C Powerplant).

### 2. Cargohold (The Exception)
- Does **not** consume power from the Powerplant.
- Upgrading simply increases SCU capacity.
- Might have a trade-off in **Mass**, which could slightly reduce the Engine's effective top speed or maneuverability.

### 3. Weapons (Combat Offense)
- **Power Draw**: High
- Upgrading increases damage, fire rate, or tracking speed.

### 4. Shields (Combat Defense)
- **Power Draw**: High
- Upgrading increases total HP, recharge rate, or resistance.

### 5. Engine (Mobility)
- **Power Draw**: Medium
- Upgrading increases top speed and turning speed (maneuverability). 

### 6. Mining Laser (Resource Gathering) - *NEW SLOT*
- **Power Draw**: High
- Upgrading increases ore yield per second or range.
- A dedicated miner might run a massive Mining Laser and heavy Cargohold, leaving very little power for Weapons or Shields.

## Max Tier Drawbacks

To further balance the min-maxing mechanics, reaching the absolute **maximum tier** (e.g., Mk V) of any subsystem introduces a minor but noticeable inconvenience. The player should still want to use it, but it requires adjusting their playstyle slightly:

- **Max Weapons (Rapid-Fire)**: Generates excessive heat. While firing continuously, the ship's turning speed is reduced by 15%.
- **Max Weapons (Heavy Payload)**: The massive recoil temporarily pauses the ship's forward momentum for 0.1s on every shot.
- **Max Engines (Speed Demon)**: The intense power draw interferes with shielding. Your shield regeneration delay takes 2 seconds longer to kick in.
- **Max Engines (Industrial Hauler)**: The massive thruster housing takes up physical space, slightly reducing your base Hull Armor by 10 points.
- **Max Shields (Bulwark)**: The dense energy field causes sensor interference, slowing down the Mining Laser cycle time by 5%.
- **Max Shields (Deflector)**: When the shield breaks, the resulting power surge completely disables your engine acceleration for 1 second.
- **Max Mining Laser (Rapid Beam)**: The chaotic cutting creates dust; you lose 1 unit of ore every 10 cycles as waste.
- **Max Mining Laser (Deep Core)**: The beam agitates the asteroid core. Mining continuously for more than 10 seconds causes a micro-explosion dealing 5 hull damage to your ship.

## Example Min-Max Scenario

**Ship: INDY Miner**
- Every subsystem tier upgrade (Mk I -> Mk II) increases power draw by +50 MW.

**Build: Starter (Tier 1)**
- Powerplant Mk I: 300 MW Capacity
- Weapons Mk I: 50 MW
- Shields Mk I: 50 MW
- Engines Mk I: 100 MW
- Mining Laser Mk I: 100 MW
- *Total Draw: 300 / 300 MW*
- **Result**: Exactly at capacity. Cannot upgrade any component until the Powerplant is upgraded to Mk II.

**Build: First Upgrade (Tier 2 Powerplant)**
- Powerplant Mk II: 350 MW Capacity (Exactly +50 MW over Tier 1)
- Weapons Mk I: 50 MW
- Shields Mk I: 50 MW
- Engines Mk I: 100 MW
- Mining Laser Mk II: 150 MW
- *Total Draw: 350 / 350 MW*
- **Result**: The Mk II Powerplant provided exactly enough capacity for *one* subsystem upgrade.

**Build A: The Balanced Upgrader (Max Powerplant)**
- Powerplant Mk V (Max): 500 MW Capacity (Total +200 MW available for upgrades)
- Weapons Mk II: 100 MW
- Shields Mk II: 100 MW
- Engines Mk II: 150 MW
- Mining Laser Mk II: 150 MW
- *Total Draw: 500 / 500 MW*
- **Result**: Spread the +200 MW capacity perfectly across all systems. Everything is slightly better, but nothing is maximized.

**Build B: The Industrial Vacuum (Max Powerplant)**
- Powerplant Mk V (Max): 500 MW Capacity (Total +200 MW available for upgrades)
- Weapons Mk I: 50 MW
- Shields Mk I: 50 MW
- Engines Mk I: 100 MW
- Mining Laser Mk V: 300 MW
- *Total Draw: 500 / 500 MW*
- **Result**: Put the entire +200 MW capacity into maxing the Mining Laser. The ship strips asteroids instantly but is completely vulnerable to pirates.

## Next Implementation Steps

When we're ready to build this in Godot, we will need to:
1. Update `GlobalState.gd` to track `power_capacity` and current `power_draw`.
2. Add a new clickable slot in `_create_ship_upgrades_panel()` for the **Mining Laser**.
3. Create an upgrade data dictionary (e.g., `UPGRADE_TIERS`) that defines the cost, stat boost, and power draw of each tier for each system.
4. Add logic to the upgrade purchase buttons: `if current_draw + new_upgrade_draw > power_capacity: show_warning("Insufficient Power")`
5. Update the "System Status" text to explicitly show `POWER: 950 / 1000 MW` so the player sees their budget.
