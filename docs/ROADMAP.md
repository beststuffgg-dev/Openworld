# Roadmap

The design document describes a complete AAA-scale game. This roadmap turns that
wishlist into an ordered, buildable plan and marks honestly what exists today.

Legend: ✅ done · 🟡 partial · ⬜ not started

---

## Phase 0 — Foundation (this repo) ✅

The playable voxel slice everything else builds on.

- ✅ Godot 4.4 project, cross-platform renderer config
- ✅ Deterministic seed, `WorkerThreadPool` chunk generation
- ✅ Chunk storage, culled meshing, ambient-occlusion vertex shading
- ✅ Layered noise terrain (continents, hills, mountains, oceans, beaches)
- ✅ Temperature/moisture biomes with soft borders
- ✅ Caves (3D noise), water to sea level, scattered trees
- ✅ First-person controller, mine/place, chunk-seam remeshing
- ✅ Day/night cycle with dynamic sun & sky

## Phase 1 — Voxel engine hardening ⬜

Make the core scale and look better before piling gameplay on it.

- ⬜ **Greedy meshing** (merge coplanar quads) — big vertex-count win
- ⬜ **Vertical chunk sections** (stacked 16³) for taller worlds & true 3D LOD
- ⬜ **Chunk LOD** + distance-based mesh simplification
- ⬜ **Texture atlas + PBR materials**, connected textures, bevelled edge shader
- ⬜ **Occlusion culling**, GPU instancing for foliage
- ⬜ **Chunk save/load & compression** (voxels are already a `PackedByteArray`)
- ⬜ Half-blocks / slopes / stairs (sub-voxel shapes) for smoother terrain

## Phase 2 — Richer world generation ⬜

- ⬜ Erosion simulation pass; rivers & lakes that follow terrain flow
- ⬜ More biomes: swamp detailing, volcanic, canyons, tundra, islands
- ⬜ Giant caverns, ravines, ore distribution
- ⬜ **Structure system**: villages, ruins, dungeons, towers, mines placed as
      templates + procedural variation during chunk post-processing
- ⬜ Biome blending of vegetation, grass tint, foliage density

## Phase 3 — Survival & gameplay systems ⬜

- ⬜ Health / hunger / thirst / temperature / stamina / sleep
- ⬜ Inventory (drag-drop, stacks, hotbar, equipment slots), item registry
- ⬜ Crafting (workbench, smithing, cooking, alchemy) + recipe data
- ⬜ Farming (soil, irrigation, growth by season), fishing, animal breeding
- ⬜ Combat (melee, bows, magic, shields, dodge), status effects
- ⬜ Creative mode (flight, unlimited blocks, no damage, blueprint copy/paste)

## Phase 4 — Environment & atmosphere ⬜

- ⬜ Weather system (rain, storms, snow, fog, wind) affecting gameplay
- ⬜ Seasons (visual + crop + migration effects)
- ⬜ Volumetric clouds & fog, god rays, aurora, stars/Milky Way, moon phases
- ⬜ Water caustics, rain splashes, snow accumulation, wet terrain, puddles
- ⬜ Global illumination / SSR / SSGI tuning per quality tier

## Phase 5 — Living world (NPCs, quests, story) ⬜

- ⬜ NPC agents with schedules (eat/sleep/work/trade/socialise/shelter)
- ⬜ Village simulation (jobs, buildings, defence, repair, reputation)
- ⬜ Animals: peaceful/neutral/hostile, taming, mounts, pack animals
- ⬜ Quest system (exploration/build/combat/gather/craft/trade/story/daily)
- ⬜ Dialogue, lore books, main storyline + branches, bosses, multiple endings

## Phase 6 — UI, input & platforms ⬜

- ⬜ Responsive modern UI (phone/tablet/Steam Deck/PC)
- ⬜ Full settings menus (graphics tiers, audio, gameplay, controls, accessibility)
- ⬜ Remappable keyboard/mouse/controller; touch controls; gyro aim (mobile)
- ⬜ Accessibility: subtitles, UI scaling, colorblind, reduced motion, screen reader
- ⬜ Mobile optimisation: dynamic resolution, battery saver, 30/60 FPS targets
- ⬜ Android / iOS / Windows export presets & CI

## Phase 7 — Multiplayer ⬜

- ⬜ Authoritative server, replicated block edits, chunk sync
- ⬜ Dedicated servers, LAN, invite codes, server browser
- ⬜ Permissions, PvP toggle, guilds, trading, player shops
- ⬜ Voice chat, anti-cheat, shared worlds & quests, cross-play

## Phase 8 — Content, polish & extras ⬜

- ⬜ Progression: XP, skills, professions, tech/magic trees, achievements
- ⬜ Photo/replay mode, blueprint sharing, character/armor customisation
- ⬜ Boats, airships, gliders, zip lines, mine carts, portals
- ⬜ Procedural audio, biome music, dynamic soundtrack, 3D audio
- ⬜ Mod support / Steam Workshop, cloud saves, dynamic economy, world events

---

## How to use this roadmap

Pick the **next unchecked item in the lowest incomplete phase** — the phases are
ordered by dependency, not preference. Phase 1 (engine hardening) pays for itself
before any gameplay, because greedy meshing, LOD and save/load make every later
phase cheaper. Each item is intentionally sized to be a self-contained change
against the extension points listed in `ARCHITECTURE.md`.
