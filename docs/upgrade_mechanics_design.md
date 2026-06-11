# Ship Upgrades: Min-Max Mechanics Design

This document outlines the proposed design for the min-maxing mechanics of ship upgrades.

## Core Concept: The Power Budget

Every ship in the game has a strict **Power Budget** dictated by its **Powerplant**. You cannot just buy every upgrade for your ship; you must carefully balance your power consumption based on your playstyle.

- **Power Capacity**: The total energy output of your current Powerplant (e.g., 500 MW).
- **Power Draw**: The sum of energy consumed by all active systems (Weapons, Shields, Engines, Mining Laser). 
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

## Example Min-Max Scenario

**Ship: INDY Miner**
- Max Powerplant Upgraded: 1000 MW Capacity

**Build A: The Combat Miner**
- Weapons Mk III: 300 MW
- Shields Mk III: 300 MW
- Engines Mk II: 200 MW
- Mining Laser Mk I: 150 MW
- *Total Draw: 950 / 1000 MW* 
- **Result**: Good in a fight, but slow at gathering ore.

**Build B: The Industrial Vacuum**
- Weapons Mk I: 50 MW
- Shields Mk I: 100 MW
- Engines Mk I: 100 MW
- Mining Laser Mk IV: 700 MW
- *Total Draw: 950 / 1000 MW*
- **Result**: Strips asteroids instantly, but completely vulnerable to pirates.

## Next Implementation Steps

When we're ready to build this in Godot, we will need to:
1. Update `GlobalState.gd` to track `power_capacity` and current `power_draw`.
2. Add a new clickable slot in `_create_ship_upgrades_panel()` for the **Mining Laser**.
3. Create an upgrade data dictionary (e.g., `UPGRADE_TIERS`) that defines the cost, stat boost, and power draw of each tier for each system.
4. Add logic to the upgrade purchase buttons: `if current_draw + new_upgrade_draw > power_capacity: show_warning("Insufficient Power")`
5. Update the "System Status" text to explicitly show `POWER: 950 / 1000 MW` so the player sees their budget.
