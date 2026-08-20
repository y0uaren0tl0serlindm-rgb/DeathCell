# Player Art

## Current direction

The active player visual uses the user-supplied pixel swordsman sheets.
Idle, run, jump, fall, hurt, death, and attack preserve their supplied frame order,
shared 200 x 200 frame canvas, and grounded baseline.

## Files

- `concepts/deathcell_hero_anchor_v1.png`: high-detail design anchor.
- `concepts/deathcell_hero_sprite_master_v2.png`: simplified transparent pixel-art sprite master.
- `animations/swordsman_jump_sheet.png`: active two-frame rising animation.
- `animations/swordsman_fall_sheet.png`: active two-frame descending animation.
- `animations/swordsman_hurt_sheet.png`: active four-frame hurt animation, synchronized to hit stun.
- `animations/swordsman_death_sheet.png`: active six-frame death animation that holds its final pose.
- `animations/swordsman_idle_01.png` through `swordsman_idle_08.png`: active transparent eight-frame idle loop.
- `animations/swordsman_run_01.png` through `swordsman_run_08.png`: active transparent eight-frame run loop.
- `animations/swordsman_attack_a_01.png` through `swordsman_attack_a_06.png`: first six-frame combo attack, including the active slash and recovery trail.
- `animations/swordsman_attack_b_01.png` through `swordsman_attack_b_06.png`: alternate six-frame combo attack.
- `animations/deathcell_hero_*.png`: archived original character exploration and movement assets.
- `runtime/player_visual.tscn`: self-contained visual scene instanced by the player scene.
- `runtime/hero_sprite.gd`: presentation-only facing and feedback adapter.
- `runtime/hero_flash.gdshader`: sprite hit-flash material.
- `../../../art/previews/deathcell_hero_checkerboard_preview_v1.png`: review preview on a light checkerboard.
- `../../../art/previews/runtime_player_v1.png`: captured in-game integration preview.
- `../../../art/previews/runtime_roll_v1.png`: deterministic in-game roll-action capture.
- `../../../art/previews/runtime_run_v1.png`: deterministic in-game run-cycle capture.
- `../../../art/tests/roll_visual_test.tscn`: art-only roll texture, pivot, and recovery check.
- `../../../art/tests/run_visual_test.tscn`: art-only run-frame, baseline, and recovery check.
- `../../../art/tests/attack_visual_test.tscn`: verifies both attacks and aligns the slash frames with the gameplay active/recovery phases.
- `../../../art/tools/print_frame_bounds.gd`: reports non-transparent frame bounds for alignment.
- `../../../art/tools/normalize_run_frames.gd`: removes generated mattes and normalizes run-frame canvas, scale, and baseline.
- `../../../art/tools/normalize_movement_v5.gd`: cleans generated mattes while preserving shared source scale and aligning contact baselines.
- `../../../art/tools/normalize_run_v7.gd`: removes the generated Passing-frame matte and places both opposite crossing poses on the shared runtime baseline.
- `../../../art/tools/prepare_mario_gif_frames.gd`: removes the connected GIF matte while preserving the supplied canvas alignment.

The runtime visual scene is connected to `src/player/player.tscn`. It does not modify player movement,
combat, collision, health, weapon data, or any existing gameplay script.
The runtime keeps one stable Sprite2D anchor. Motion inside the supplied GIF canvas is retained without adding code-driven vertical bobbing.

## Runtime target

- Logical sprite canvas: 48 x 48 pixels.
- Character body height: approximately 24-28 pixels before weapon and scarf extensions.
- Pivot: feet centered on a shared baseline.
- Filtering: nearest-neighbor.
- Facing: author right-facing frames; the game may mirror them for left-facing movement.

## Next art pass

1. Reduce the sprite master onto the final 48 x 48 pixel grid; the current runtime pass scales the master texture.
2. Produce dedicated run-start, run-stop, turn, and roll poses. Idle, run,
   jump, fall, hurt, death, and two alternating attack actions are implemented;
   temporary locomotion transitions still reuse existing frames.
3. Produce the three rusty-sword attack sequences.
4. Export a transparent sprite sheet and a visual-only preview scene.
