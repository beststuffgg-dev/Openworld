# Block textures

Optional 16×16 PNG textures for blocks, one per block, named after the block in
lowercase — e.g. `stone.png`, `grass.png`, `dirt.png`, `sand.png`, `wood.png`,
`planks.png`, `leaves.png`, `snow.png`, `gravel.png`, `clay.png`.

## How textures are used

At startup `src/world/TextureAtlas.gd` packs one tile per block into a single
atlas. For each block it looks, in order, for:

1. `user://textures/blocks/<name>.png` — textures you paint in the in-game
   **Texture Editor** (press **F1** in game). This is the writable location on
   every platform.
2. `res://textures/blocks/<name>.png` — textures committed to the project here
   (shipped defaults).
3. If neither exists, the block's flat colour is used as its tile.

So the world always renders — custom art is purely additive.

## Making your own

Press **F1** in game to open the Texture Editor: pick a block, paint on the
16×16 grid, **Save**, then **Back to Game**. Your texture is written to
`user://textures/blocks/` and appears on that block immediately.

To ship a texture with the project, drop a 16×16 `<name>.png` into this folder
and Godot will import it; the atlas will load it as the default for that block.
