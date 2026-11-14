# Petalveil (Horizon shader pack)

## Tooling
- Build the checker once: `git clone --filter=blob:none https://github.com/horizon-rust/horizon.git` in `/tmp/opencode`,
  then `cargo build -p horizon-shader-api --bin horizon-shader` (needs the WHOLE workspace checked out: sparse
  checkout makes cargo fail on missing member manifests). Proxy `http://127.0.0.1:2080` for cargo/git.
- `horizon-shader check pack` validates every stage at option defaults/min/max and translates to SPIR-V/Metal/HLSL.
  `horizon-shader pack . --out dist/<id>-<ver>.hshader`.
- API reference: `docs/api/shaders-reference.md`, `docs/api/shaders.md` in the cloned repo (also raw on GitHub).

## Pack format gotchas found here
- `[material]` and `[vertex]` are ONE WGSL module: an `override` declared in both is a redefinition error, and a
  declaration in a `[material] files = [...]` entry is not visible to `vertex.wgsl`. Shared options go in
  `shared` (common.wgsl).
- `target` is a reserved WGSL name in naga 30; the check reports it per stage.
- Choice options become `override <id>: u32` (index), bool → `bool`, float → `f32`.
- `[sky] clouds = false` / `sun = false` remove vanilla's clouds/sun; stars and moon always stay.
- Post passes: `output = "<name>"` + `scale = 0.25`, later passes read `<name>` as a `texture_2d<f32>`.

## Local loop
- Project skill `.opencode/skills/horizon-shader-packs/` carries the API, the checker build and the pitfalls;
  read it before touching a stage.
- Live source link: `ln -sfn ~/Projects/own/horizon-shader/pack ~/.local/share/horizon/shaderpacks/petalveil`
  (game hot-reloads every save). Installed pack file would duplicate the id, so keep only one.
- Turn on from CLI: `horizon-launcher packs on --kind shader "Petalveil"` (title or filename, `--kind shader`).
- The user takes the screenshots; the agent does not launch the game.

## Lessons from the user's screenshots
- Flat clouds read as "glued to the camera" and make the walk feel like swaying. A sky-stage cloud is a picture on
  the dome: it cannot parallax like vanilla's cloud geometry, and the user rejected both my flat version and the
  volumetric one. Vanilla's clouds are kept: they are world geometry, they hide the sun, they move against the
  ground. Do not replace them with a sky-stage layer without a real cloud texture and 12+ samples.
- Rounded cells of exactly one cell size leave a diamond of sky at every four-cell vertex; the rounded box must
  reach ~1 block past its cell (half 7, radius 2.4) so neighbours merge.
- A sharp horizon transition in the sky (band edge, cloud layer cut-off) sweeps across the view while the camera
  bobs: keep sky gradients wide and fade to vanilla's fog colour at the horizon.
- Vanilla's sun is the user's pick over a custom disc: keep `[sky] sun` at its default.
- Cloud geometry is the engine's (`crates/horizon-client-render/src/clouds.rs`, fragment path in `entity.wgsl`),
  not reachable from a pack stage; the only way to soften its rim is a post pass. With a `[[post]]` chain the
  player's `taa`/`fxaa` never run (docs/api/shaders.md, "Anti-aliasing"), so the pack's last pass does
  FXAA-lite (`post/composite.wgsl`).
- The user wants that smoothing stronger and tunable. It is now a radial blur (`cloud_soft`, 16 taps of
  a Vogel spiral) whose radius is the slider in pixels (0..32, default 8), not FXAA: FXAA only fixes
  stair-steps, and the user wanted visibly soft rims. It is cloud-only: a pixel is a cloud when its depth
  puts it in the layer at `CLOUD_Y` 192.33 (`clouds::CLOUD_HEIGHT`), so it lives on the Sky page, not
  Camera. Cloud height is not a player option in the client, only cloud range, so the constant holds.
- A blur softens the rim but cannot round a cube's corners: that needs the engine's geometry or the pack's
  own raymarched clouds, which the user rejected as worse than vanilla's. Say so instead of promising the
  Complementary look. Their reference frame cost 13.3 ms of GPU, this pack runs at ~3.8 ms.
- Vanilla shades each cloud face per cube, so a mass shows hard bright/dark bands across its body. The same
  radial blur is applied to the body at 0.65 where the disc is fully cloud (`body` in `cloud_soft`), which
  softens them; the rim keeps the full blend.
- A blur disc that averages the ground smears the land's silhouette where a cloud stands behind a hill: taps
  on solid ground are skipped, and a ground pixel is never processed. That was a real regression the user
  caught.
- Shadow darkness is `SHADE` (0.18) times the `shadow_strength` option (0..3, default 1 = the agreed look):
  keep the default, the user only asked for room to go deeper.
- `bobView:true` in the instance's `options.txt`: the engine bobs the camera. The user says vanilla and the
  Iris-format packs do not feel wrong, so the difference is the sky stage, not the engine; suspect any
  camera-locked layer first.

