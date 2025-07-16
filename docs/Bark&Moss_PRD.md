# Bark & Moss Co-Op Game Design Document

## Overview
A stylized, co-op survival game set in a dense, procedurally generated forest. Two players play as a human and a dog, each with distinct abilities and roles. The game emphasizes asymmetrical gameplay, environmental survival, and relaxed exploration, balanced with nighttime threats.

---

## Art & Atmosphere
- **Visual Style**: Bright, warm, low-poly 3D visuals
- **UI Inspiration**: Mix of The First Tree, Haven, Risk of Rain 2, Alto's Adventure
- **Lighting**: Gradient skies, day/night cycle (9min day / 3min night)
- **Environment**: Minecraft-style forest density, but taller and more atmospheric trees
- **Camera**: 3rd-person, close and soft-follow per player (multiplayer)

---

## Platform & Tech
- **Engine**: Godot
- **Platform**: Desktop (Windows), multiplayer via Godot's networking API
- **Multiplayer**: Online (friends-only), players on separate devices using a host-client architecture
- **World Persistence**: Local save file with player positions and inventories

---

## Multiplayer Architecture
- **Model**: Host-client (host acts as authoritative server)
- **Connection**: Lobby code system with optional lightweight signaling server for NAT traversal
- **Join Flow**: Host creates a session and receives a randomly generated 6-character code (e.g., GR73KX); friend enters code to join
- **Role Assignment**: Second player can only choose the unoccupied role (either human or dog)
- **State Sync**: Entity state sync for positions, animations, hunger, etc.
- **Tick Rate**: 30Hz
- **Interpolation**: Simple linear interpolation for smoother remote movement

---

## Save System
- **Format**: JSON for readability and debugging
- **Triggers**: Manual save + autosave every 5 minutes
- **Storage**: One folder per world instance containing metadata and `world.json`
- **Data Saved**:
  - Player inventory and position
  - World state (chopped trees, campfire state)
  - Spawn metadata for animals

---

## Player Characters

### Human
- **Controls**: WASD + mouse look, jump, walk/run toggle, hotbar selection (1–5 or scroll), interact (E), attack (Left Click), cancel (Right Click or Q)
- **Abilities**:
  - Chop trees with hatchet (default item)
  - Interact with corpses to process meat (requires holding hatchet + light source)
  - Craft weapons from sinew and wood
  - Shoot bow at animals (no spears)
  - Interact with dog to give raw meat
  - Interact with campfire to cook/process
  - Hold Left Click with bow equipped zooms in and shows charging crosshair
- **Restrictions**:
  - Cannot eat raw meat
  - Vulnerable to bears
- **Weapons**: Hatchet (starter), craftable bow (hotbar system)
- **Inventory**: Persisted between sessions and across deaths

### Dog
- **Controls**: WASD + mouse, jump (Space), bite (Hold Left Click), bark (Right Click), drop (Release Left Click)
- **Abilities**:
  - Fast movement (faster than human, slower than deer)
  - Bite (large hitbox, no targeting) to kill rabbits and grab corpses
  - Bark to startle birds or scare bears (3 barks required)
  - Retrieve corpses (drag physics, grab point-based)
- **Behavior**:
  - Dragging slows movement slightly, no reduction in turn speed
  - Dog can get stuck on trees but not on foliage
  - Barking has a hidden 1s cooldown and costs a small amount of hunger
- **Restrictions**:
  - No inventory
  - Must eat raw meat from human or found kills

---

## Core Systems

### Hunger System
- **Shared Mechanic**: Applies to both human and dog
- **Depletion**: Based on actions (running, hunting, chopping, barking)
- **At 10%**: Can no longer run (walk only)
- **At 0%**: Instant death (player respawns after a short delay, with inventory preserved)
- **Dog can eat raw meat**, **Human must cook food** at campfire
- **Cooked meat restores 60% hunger**
- **All animals provide meat when processed**

### Campfire
- **Functions**:
  - Spawn point
  - Safe zone from bears (affected by line-of-sight and tree shadows)
  - Crafting station
  - Cooking station (10s cook time, all queued meat cooks at once, visible model during cook)
- **Light Radius**:
  - Reduced by nearby trees (blocks light and reduces total range)
  - Bears can enter but retreat after a few seconds in full light

### Day/Night Cycle
- **Day**: 9 minutes, main exploration/hunting window
- **Night**: 3 minutes, high danger (bear spawns)
- **Bear Behavior**:
  - Spawns at night
  - Faster than human, slower than dog
  - Will chase into light but retreat quickly
  - Scared off by 3 dog barks

### World & Terrain
- **Map**: Procedurally generated forest
- **Trees**:
  - Can be chopped down by human
  - Block campfire light until destroyed
  - Disappear after fall animation (no collision)
- **Animals**:
  - **Rabbits**: Dodge human arrows, hunted by dog
  - **Birds**: Flee when dog barks, shot by human
  - **Deer**: Graze, flee early, vulnerable to bow, slightly faster than dog
  - **Bears**: Night predators, chase both players
- **Spawning**:
  - Animals spawn throughout day
  - Must spawn outside player viewports and a set distance away
  - Spawn only in forest zones
  - Dead animals are temporary and do not persist between sessions

### Crafting
- **At Campfire Only**
- **Requires**:
  - Wood (chopped from trees)
  - Sinew (processed from rabbit corpses)
- **Examples**:
  - Bow = Wood + Sinew
  - Cooked Meat = Raw Meat + 10s cook time (visible on campfire)
- **UI**:
  - Activated with `E` near campfire
  - Radial grid layout popup
  - ESC to exit crafting

---

## UI Design

### HUD Elements
- **Hotbar** (bottom center): 5 slots, scroll or 1–5 key access
- **Hunger Bar** (bottom left): simple bar with icon and percentage
- **Interaction Prompt** (center bottom): contextual instructions like `E: Cook`, `Hold LMB: Bite`, etc.
- **Compass Markers** (top center or lower edge): icons for campfire 🏕, dog 🐾, or carried corpse 🎯
- **Interactable Indicator**: Small icon floats above any interactable object/animal when within range
- **No tooltips on hover**
- **Hunger bar pulses green briefly when eating**

### Inventory UI (Human)
- **Layout**:
  - Opens by holding `Tab` (not toggle)
  - 3x4 grid layout
  - Centered on screen
  - Background grays out while open
- **Contents**:
  - Displays only tools, weapons, and resources
  - Separate designated slots for tools and weapons (not drag-and-drop to hotbar)
- **Tooltips**:
  - Each item has a short "mysterious" description (e.g., "Raw Meat. A bit too chewy to eat. If only I had a way to cook it...")
- **Usage**:
  - Cooked meat is eaten by equipping it and clicking Left Mouse Button
  - Human can interact with dog to give meat
  - Dog cannot give anything to the human

### Audio Settings
- Simple volume sliders:
  - Master Volume
  - Music Volume
  - SFX Volume

---

## World & Lobby Management

### Main Menu
- **Landing Screen** (similar to Minecraft):
  - Play
  - Join
  - Settings
  - Exit

### Lobby System
- Host generates **lobby code**
- Second player **joins via code**
- Player role selection: joining player can only select the **remaining role** (i.e., no duplicate roles)

### ESC Menu
- Simple vertical list:
  - Resume
  - Settings
  - Save & Quit
  - Leave World

### World Browser
- Accessed from the Play screen
- Displays local worlds
- Options to:
  - Rename
  - Play
  - Delete

### Connection Events
- Show on-screen indicators or logs when players:
  - Connect
  - Disconnect

---

## Core Loop Example
1. Spawn at campfire
2. Dog hunts rabbits → Human processes corpses → Craft bow
3. Dog startles birds → Human shoots birds → Cooks meat
4. Human chops trees for wood and clear line-of-sight
5. Night arrives → Stay near fire → Fend off bear with dog barks
6. Next day begins → Continue survival cycle

---

## TODO Next
- Define player control responsiveness (acceleration, rotation smoothing)
- Create hotbar UX flow for human
- Determine how corpses attach to dog physics
- Set spawn logic rules for different animals
- Begin network testing with Godot multiplayer API
- Implement local JSON or binary save file structure
- Build menu + world manager + lobby connection system

