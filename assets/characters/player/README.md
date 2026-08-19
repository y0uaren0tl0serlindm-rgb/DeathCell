# DeathCell Player Art

## Current direction

The protagonist is an escaped prisoner whose body is partially infused with cellular energy.

- Primary silhouette: tall hood, short torn scarf, narrow athletic body.
- Identity accents: one cyan eye, cyan-green chest core, steel shoulder guard.
- Base colors: deep indigo and charcoal.
- Gameplay accents: crimson for motion and cyan-green for energy/readability.
- Equipment: compact worn sword with a subtle cellular-energy channel.

## Files

- `concepts/deathcell_hero_anchor_v1.png`: high-detail design anchor.
- `concepts/deathcell_hero_sprite_master_v2.png`: simplified transparent pixel-art sprite master.
- `animations/deathcell_hero_roll_v1.png`: curled transparent roll-action pose.
- `runtime/player_visual.tscn`: self-contained visual scene instanced by the player scene.
- `runtime/hero_sprite.gd`: presentation-only facing and feedback adapter.
- `runtime/hero_flash.gdshader`: sprite hit-flash material.
- `../../../art/previews/deathcell_hero_checkerboard_preview_v1.png`: review preview on a light checkerboard.
- `../../../art/previews/runtime_player_v1.png`: captured in-game integration preview.
- `../../../art/previews/runtime_roll_v1.png`: deterministic in-game roll-action capture.
- `../../../art/tests/roll_visual_test.tscn`: art-only roll texture, pivot, and recovery check.

The runtime visual scene is connected to `src/player/player.tscn`. It does not modify player movement,
combat, collision, health, weapon data, or any existing gameplay script.

## Runtime target

- Logical sprite canvas: 48 x 48 pixels.
- Character body height: approximately 24-28 pixels before weapon and scarf extensions.
- Pivot: feet centered on a shared baseline.
- Filtering: nearest-neighbor.
- Facing: author right-facing frames; the game may mirror them for left-facing movement.

## Next art pass

1. Reduce the sprite master onto the final 48 x 48 pixel grid; the current runtime pass scales the master texture.
2. Produce idle, run, jump, fall, hurt, and death key poses. The first roll pose is implemented.
3. Produce the three rusty-sword attack sequences.
4. Export a transparent sprite sheet and a visual-only preview scene.
