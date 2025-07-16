Bark & Moss: Development Checklist
This checklist breaks down the development of "Bark & Moss" into manageable phases and tasks, based on your game design document.

Phase 1: Pre-Production & Prototyping (The Foundation)
Goal: Build and validate the core mechanics. Test the most critical and riskiest systems first: player movement and co-op networking.

1. Project Setup & Version Control
[X] Initialize a new Godot project.

[X] Set up a Git repository (e.g., on GitHub, GitLab) for version control.

[X] Establish a clear project folder structure (e.g., scenes, scripts, assets, ui).

[X] Configure Godot's display settings for the target resolution and aspect ratio.

2. Core Player Controller Prototyping (Single Player)
[ ] Human Character:

[X] Create a basic 3D model/placeholder (e.g., a capsule) for the human.

[X] Implement basic 3rd-person movement (WASD) and mouse look.

[X] Implement jumping.

[X] Implement walk/run toggle with different speeds.

[X] Dog Character:

[X] Create a basic 3D model/placeholder for the dog.

[X] Implement its unique movement (faster than human).

[X] Implement dog's jump.

[X] Camera System:

[X] Create a soft-follow 3rd-person camera that trails the player.

[X] Ensure the camera handles collisions with the environment gracefully (doesn't clip through walls).

3. Networking Prototype
[X] Lobby System:

[X] Create a basic UI for the main menu (Play, Join, Settings, Exit).

[X] Implement Godot's High-Level Multiplayer API.

[X] Create logic for a "Host" button to start a server.

[X] Create logic for a "Join" button and a text field to enter an IP address (for initial testing).

[X] Player Spawning & Syncing:

[X] Implement logic to spawn the host as the Human and the client as the Dog.

[X] Synchronize player position and rotation over the network.

[X] Use MultiplayerSynchronizer node for state syncing.

[X] Implement basic linear interpolation to smooth out remote player movement.

[ ] Test basic co-op movement in a simple test scene with some obstacles.

4. World & Environment Prototype
[X] Procedural Generation:

[X] Create a script for basic procedural world generation.

[X] Start with a flat plane and spawn placeholder "trees" (e.g., cylinders) randomly.

[X] Implement rolling hills terrain using noise-based height generation.

[X] Create proper terrain mesh with vertices, normals, and collision.

[X] Implement surface-based tree spawning using raycast detection.

[X] Ensure the density feels right, as described in the GDD.

[X] Set up proper terrain collision with StaticBody3D and trimesh shape.

[X] Configure collision layers for player-terrain interaction.

[X] Implement terrain height lookup system for object placement.

[X] Fix terrain triangle winding for proper upward-facing surfaces.

[X] Basic Interaction System:

[X] Create a generic "Interactable" area or component.

[X] Implement a system where the player can look at an object and get a UI prompt (e.g., "Press E to Interact").

[X] Apply this to a tree stump for a "chop" action.

[X] Player Spawning & Terrain Integration:

[X] Implement terrain-aware player spawning system.

[X] Players spawn safely above terrain surface using height detection.

[X] Coordinate spawning timing with terrain generation completion.

[X] Lighting & Environment:

[X] Set up proper directional lighting for terrain illumination.

[X] Configure ambient lighting for natural appearance.

[X] Optimize terrain material for proper light reflection.

Phase 2: Vertical Slice (Building the Core Loop)
Goal: Implement one full "day-night-day" cycle with all essential features functional, but not necessarily polished. This proves the game is fun.

1. Character Abilities & Core Mechanics
[X] Human Abilities:

[X] Implement the hotbar system (5 slots, 1-5/scroll wheel selection).

[X] Create a hatchet tool.

[X] Implement tree chopping logic (e.g., 3 hits to fell a tree).

[X] Create a tree falling animation/effect (disappears after).

[X] Implement inventory system (Tab to open, 3x4 grid).

[X] Implement bow shooting mechanics with charging system and zoom.

[ ] Dog Abilities:

[X] Implement the bite attack (hold left-click, large hitbox).

[X] Implement the bark action (right-click, with cooldown and hunger cost).

[X] Implement corpse grabbing/dragging physics.

[ ] Hunger System:

[ ] Add a hunger variable to both players.

[ ] Create a UI bar to display hunger.

[ ] Implement hunger depletion over time and from actions (running, barking).

[ ] Implement the "walk only" state at 10% hunger.

[ ] Implement the death/respawn mechanic at 0% hunger.

2. AI & Animals
[X] Rabbit AI:

[X] Create a rabbit scene with a simple model.

[X] Implement basic wandering behavior.

[X] Implement logic to be killed by the dog's bite.

[X] On death, spawn a "rabbit corpse" object.

[X] Bird AI:

[X] Create a bird scene with flying behavior.

[X] Implement logic to flee when dog barks nearby.

[X] Implement logic to be shot by human arrows.

[X] On death, spawn a "bird corpse" object that falls to ground.

[X] Animal Spawning System:

[X] Create a spawn manager.

[X] Implement logic to spawn animals outside the players' viewports.

[X] Add multiple animal types (rabbits and birds).

3. Crafting & Campfire
[ ] Campfire Implementation:

[ ] Create a campfire scene.

[ ] Designate it as the player spawn point.

[ ] Implement the cooking mechanic (interact, queue raw meat, 10s timer).

[ ] Implement logic for cooked meat to restore hunger.

[ ] Crafting System:

[ ] Design the crafting UI (radial or simple list for now).

[ ] Implement the logic to check for ingredients (Wood, Sinew) in the human's inventory.

[ ] Implement the first recipe: Bow = Wood + Sinew.

4. Day/Night Cycle
[ ] Lighting & Time:

[ ] Implement a global script to manage time.

[ ] Create a 12-minute cycle (9 min day, 3 min night).

[ ] Animate the WorldEnvironment node's properties (sky color, sun direction, ambient light) to transition between day and night.

[ ] Bear AI (Prototype):

[ ] Create a bear scene with a placeholder model.

[ ] Implement logic for the bear to spawn only at night.

[ ] Implement a simple "chase player" behavior if the player is within range.

[ ] Implement the "retreat from campfire light" logic.

5. UI & HUD
[ ] HUD Elements:

[ ] Implement the final hotbar UI.

[ ] Implement the hunger bar UI with icon and percentage.

[ ] Implement the contextual interaction prompt (E: Cook).

[ ] Implement the floating interactable indicators.

[ ] Inventory UI:

[ ] Implement the 3x4 grid layout.

[ ] Add logic to populate it with items.

[ ] Implement the "mysterious" tooltips.

Phase 3: Production & Content Expansion
Goal: Flesh out the game with more content, polish existing systems, and refine the user experience from start to finish.

1. Art & Asset Integration
[ ] Create and import final 3D models for:

[ ] Human (with animations for walking, running, jumping, chopping).

[ ] Dog (with animations for walking, running, jumping, biting, barking).

[ ] Rabbit, Bird, Deer, Bear.

[ ] Trees, foliage, rocks, and other environmental assets.

[ ] Campfire (with states for unlit, lit, cooking).

[ ] Items (hatchet, bow, raw meat, cooked meat).

[ ] Design and implement the final UI/HUD art style.

[ ] Create and integrate sound effects (SFX) for all actions.

[ ] Compose and integrate background music.

2. Expanding Gameplay Systems
[ ] Full Animal Roster:

[X] Birds: Flee on bark, can be shot by bow.

[ ] Deer: Flee early, faster than dog, vulnerable to bow.

[ ] Refine Bear AI: Improve chase logic, implement the 3-bark scare mechanic.

[ ] Human Weapon Systems:

[X] Implement bow shooting mechanics (hold to charge/zoom, release to fire projectile).

[X] Implement logic for arrows to hit and kill animals.

[X] Implement hunting mechanics for rabbits and birds.

[ ] Implement corpse processing (requires hatchet + light source).

Campfire & World Interaction:

[ ] Implement campfire light being blocked by trees.

[ ] Ensure chopping down trees correctly affects the light radius.

3. Multiplayer Polish & Lobby System
[ ] Lobby Code System:

[ ] Replace IP-based joining with the 6-character random code system.

[ ] Consider setting up a lightweight signaling server for NAT traversal if direct connections fail.

State Synchronization:

[ ] Sync all necessary states: animations, hunger levels, inventory changes, campfire state.

[ ] Ensure tick rate is set to 30Hz.

Connection Events:

[ ] Implement on-screen messages for "Player has connected/disconnected."

[ ] Handle graceful disconnects (player character is removed, etc.).

4. Save/Load System
[ ] Implement the JSON-based save system.

[ ] Create logic to save player position, inventory, and hunger.

[ ] Create logic to save relevant world state (chopped trees, campfire state).

[ ] Implement manual save and 5-minute autosave triggers.

[ ] Create the World Browser UI to manage, rename, and delete save files.

5. Menus & Settings
[ ] Implement the full main menu flow.

[ ] Implement the in-game ESC menu (Resume, Settings, Save & Quit).

[ ] Implement the audio settings panel with volume sliders.

Phase 4: Beta & Post-Launch
Goal: Bug fixing, optimization, and preparing for release.

1. Testing & Quality Assurance
[ ] Conduct extensive playtesting sessions (especially for co-op).

[ ] Hunt for and log bugs in a tracker.

[ ] Focus on fixing game-breaking bugs and major issues first.

[ ] Test on different hardware to check for performance bottlenecks.

2. Optimization
[ ] Use Godot's profiler to identify performance hotspots.

[ ] Optimize procedural generation code.

[ ] Optimize rendering (e.g., using LODs - Level of Detail - if necessary).

[ ] Optimize networking traffic to reduce bandwidth.

3. Final Polish
[ ] Add "juice" - screen shake, particle effects, satisfying sounds.

[ ] Review all text for typos and clarity.

[ ] Ensure the game's control responsiveness feels perfect.

[ ] Build the final executable for Windows.

4. Post-Launch
[ ] Monitor player feedback.

[ ] Prepare to deploy patches for critical bugs.

[ ] Plan for potential future content updates.