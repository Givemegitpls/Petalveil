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

## User's design line- "Atmosphere is the sum of elements, not the quality of each": they explicitly accept cheap, fake effects over
  honest simulation as long as the frame reads right. Prefer quarter/half resolution passes, few steps, masks and
  blur over raymarched truth; report the cost, not the technique.
- Sun: pixel-round, size by eye, not by geometry. Vanilla's quad is ±30 at a distance of 100
  (`celestial_geometry`), but what the game shows is ~5-8 degrees, so `sun_scale` 0.25 of the quad tangent
  (≈8 degrees) is the default; the option is only the grid's cell count (8..48). Two earlier attempts were
  wrong: 16 screen pixels (~1 degree, "tiny") and the full quad (33 degrees, "too big by 3×").

## Lessons from the user's screenshots
- Noise lesson: per-pixel `ign()` jitter in a pass that draws at a quarter or half resolution upscales into
  visible grain over the whole picture (rays, fog). Use a fixed half-step there, and only dither at full
  resolution (the last pass, 0.6/255). Per-pixel spiral rotation in a blur is the same trap: quantise the seed
  to a 4-pixel grid. But removing the jitter exposed the march itself: at 16 fixed steps the rays read as
  hard rings and spokes around the sun ("стало хуже"). More samples alone did not remove them. The working
  recipe for a quarter-res raymarch of a binary mask: per-pixel jitter (kills the rings), plus a nine-tap tent
  blur of the target in the composite (kills the grain), 24 taps. Dither and blur are a pair — neither alone
  looks right.
- Godrays must not stop when the sun leaves the frame: project the sun even outside the frustum (reject only
  `clip.w <= 0` or a UV beyond about -3..4) and *skip* samples that fall outside the picture instead of clamping
  them, or the border smears across the scene. Occlusion is depth-based, so terrain, clouds and water end the ray;
  entities cannot be excluded — a post pass sees one depth buffer only. The user decided that is fine, even
  better: entities blocking the shafts is the wanted look. Do not "fix" it.
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
- Sun blur (`sun_blur`, Sky page, 0..24 px, default 0) is its own radial blur in `post/composite.wgsl`, masked by
  the ray's alignment with `sun_direction` and limited to sky pixels, so a cloud in front of the sun keeps its
  edge. Same Vogel spiral as the cloud blur, twelve taps.
- Vanilla shades each cloud face per cube, so a mass shows hard bright/dark bands across its body. The same
  radial blur is applied to the body at 0.65 where the disc is fully cloud (`body` in `cloud_soft`), which
  softens them; the rim keeps the full blend.
- A blur disc that averages the ground smears the land's silhouette where a cloud stands behind a hill: taps
  on solid ground are skipped, and a ground pixel is never processed. That was a real regression the user
  caught.
- The user's tuned values (2026-11-14, read from `shaderpacks/.horizon-options/petalveil.txt`): shadow depth 1.6,
  sun blur 14, cloud blur 5, volumetric fog on, thickness 0.55, height 42. Those three are now the shipped
  defaults; read that file instead of asking.
- Fog colour: it must follow `fog_color`/`sky_color` (the user's words: "follow the clouds"). A few percent of
  ambient leaves shaded fog black and it reads as smog.
- Shadow darkness is `SHADE` (0.18) times the `shadow_strength` option (0..3, default 1 = the agreed look):
  keep the default, the user only asked for room to go deeper.
- `bobView:true` in the instance's `options.txt`: the engine bobs the camera. The user says vanilla and the
  Iris-format packs do not feel wrong, so the difference is the sky stage, not the engine; suspect any
  camera-locked layer first.

