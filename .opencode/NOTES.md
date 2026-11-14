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

## User's design line
- **Every effect must be switchable off** (or have a neutral value): the user asks for this explicitly. Audit the
  option list when adding anything; the sun was the one hole (manifest `[sky] sun = false` makes vanilla's sun
  unreachable at runtime, so it got its own `Sun` bool).- "Atmosphere is the sum of elements, not the quality of each": they explicitly accept cheap, fake effects over
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
- Root cause of the "рябь": IGN dither in the last pass, not the rays. IGN is a fixed diagonal pattern and its
  amplitude is absolute — fine on mid-tones, 6% relative on dark grass. It is now white hash noise (option
  `Dither`, default on). Keep it off IGN.
- Fog colour: it must follow `fog_color`/`sky_color` (the user's words: "follow the clouds"). A few percent of
  ambient leaves shaded fog black and it reads as smog.
- Shadow darkness is `SHADE` (0.18) times the `shadow_strength` option (0..3, default 1 = the agreed look):
  keep the default, the user only asked for room to go deeper.
- `bobView:true` in the instance's `options.txt`: the engine bobs the camera. The user says vanilla and the
  Iris-format packs do not feel wrong, so the difference is the sky stage, not the engine; suspect any
  camera-locked layer first.

- Water options the user asked for: `water_ripples` (fine chop on the normal only, 0 = glassy, 2 = lively),
  `water_opacity` (surface transparency, multiplier on vanilla alpha) and `underwater_murk` (depth absorption in
  the composite while `frame.in_water` is up, red first). Defaults are "vanilla plus a little".
- Waves were invisible because `top` was taken from `input.face == 1u`, which describes the block's face and
  not the fluid's top quad. Use `abs(input.normal.y) > 0.5`. The swell then also shades its crests
  (`0.96 + 0.08 * swell`) so it reads even with reflections off.
- Water colour controls: `water_saturation` (0..2) and `water_hue` (degrees, via a rotation around the grey
  axis) applied to the water's own body only, never to the mirror, so reflections keep the sky's colours.
- Calibration: the first working swell was ten times too big for the user ("раз в десять меньше"), so the
  constants are a tenth and `wave_size` (0..10, default 1) is the room to grow — do not "fix" the small default.
- Water like the user wants it (Lumen's look, their reference): the colour must *graduate with depth*
  (`deep = 1 - exp(-thickness / reach)`, turquoise shallow over the bed, the biome's own colour deep), and the
  mirror must be bent by the fine chop separately from the swell — with a small swell the reflection otherwise
  turns into a flat pane. Deep water also gets a little more opaque, which hides the aliased sea floor.
- The swell's *geometry* is deliberately tiny, so its visibility must come from three places, all scaled
  by `wave_size`: the mirror's own bend (gradient of `wave_field` over half a block, x0.06), the crest shading
  (`(crest - 0.5) * 0.1`), and the small vertex drop. Scaling only the geometry makes the water look static —
  the user said "волны не рабочие" exactly after that.
- The rain rings (`ripple_slope`) are liked and must stay: baseline 0.15 in the normal, stronger with
  `frame.wetness`, and their share of the mirror bend scales with wetness too.
- Rain rings must be randomised per cell (own centre, phase, speed, and only some cells present) or they line
  up on a visible grid, and they must be gated by `frame.wetness` alone: a dry lake with rings is wrong.
- "Waves visible only far away" is physics: near the camera the view angle is steep, fresnel is ~0.02, so the
  mirror shows flat sky and the swell cannot read in it. The near field needs its own cues: a broad specular
  lobe (`pow(dot(n, halfway), 18)`) and a slow fine shimmer, both gated by daylight and shadows.
- The game draws its own rain rings on wet water, so the pack's rings are an option now: `Rain rings`
  = Vanilla (default, ours off) or Pack's own (ours on top; the vanilla ones cannot be removed from a pack).
- Two real bugs the user caught: (1) the reflection bend had a `0.6 + 0.8 * wetness` factor, so the pack's
  rain rings lived in clear weather — a rain effect must be gated by `wetness` alone, with no baseline;
  (2) waves were invisible within ten blocks because the near field is mostly the bed seen *through* the water,
  and the engine's alpha blend gives the normal nothing to move. Fixed by doing the refraction ourselves:
  sample `opaque_color` at `screen + bend + n.xz`, absorb by thickness, then return an opaque surface
  (alpha 1). Side faces and waterfalls keep vanilla's alpha.
- `Pack's own` rain rings cannot replace vanilla's: the game draws those itself. The option only adds ours.
- Cheap water detail the user asked for, both procedural (no textures): `sparkle()` = product of two moving
  noises, thresholded by smoothstep — rare bright spots that read as sun glitter; `caustic_net()` = |a - b| of two
  drifting noises, bright where they cancel — the net the sun draws on a bed, applied by multiplying the refracted
  `behind` colour, faded by thickness and by the sun's elevation. Options `water_glints`, `water_caustics` (0..2).
- The Water page is grouped into sub-pages now: Surface / Colour / Light, reached from `page:water` (the main
  page lists `page:water`, and that page lists the three). Every page must be reachable from the first or the
  check refuses the pack.
- Detail knobs the user asked for: `glint_scale` (glitter frequency), `caustic_size` (bigger = wider cells; scale = 1/size) and
  `caustic_lines` (strand thickness), on top of `water_glints` / `water_caustics` (strength, 0 = off).
- One noise for both water details: `ridge_net(xz, t, scale, lines, speed)` — two drifting `value_noise`s at
  1.7x and 2.3x frequency, `1 - smoothstep(lines*0.15, lines, |a-b|)` gives the bright net. Caustics call it as
  is (speed 1); glitter calls it at a fine scale, three times faster, and cubes the result so strands break into
  points. Do not duplicate the noise code when a new effect needs "sparkly": reuse `ridge_net`.
- Glitter knobs (Water > Light): `glint_size` (bigger = bigger sparkles; scale = 30/size, so 10 reproduces the reference look), `glint_lines` (strand thickness fed to
  `ridge_net`), `glint_blur` (exponent between 12 and 0.75 *and* widens the strand as it softens, so the slider has real travel
  at both ends — the narrow 6..2 mapping was rejected as "маленький диапазон"), `water_glints` (strength). Caustics have the same trio: `caustic_size`, `caustic_lines`, `water_caustics`.
- `water_texture` (bool, default on): off replaces the vanilla scrolling water sprite with a flat pale blue, so
  the surface is the biome tint plus our waves/reflections only. The scrolling sprite fights the waves; this is
  the switch the user asked for. Side faces keep a constant alpha (0.85) when it is off, since the sprite's alpha
  is gone.
- Slider semantics: the user reads "size" as "how big is the shape", so a bigger value must make bigger
  sparkles/cells. Both water detail sizes are now inverted at the call site (`70 / glint_size`, `1 / caustic_size`)
  with defaults chosen to keep the shipped look. Do not expose a raw frequency again.
- Twice for the same lesson: changing a slider's *mapping* and its *shape* in the same session makes the
  reference look unreachable. The user's "3 was good" is now exactly `glint_size` 10 (`30 / 10`), and blur must
  not widen the strand — it only shapes the exponent (12..0.75). When re-tuning a knob, first reproduce the old
  value exactly, then extend the ends.
- Slider travel rule (learned twice): keep the shipped default on the same visual as before, and extend only the
  ends. `glint_blur` now maps 24 -> 3.56 (at 0.75) -> 0.5 exponent, and past 0.75 it also fades in a coarser
  version of the same net, so the top end is a real spread and not the same point, paler.
- Blur radii were widened on request: clouds 0..64 px (24 spiral taps instead of 16, or a wide radius opens gaps
  between samples), sun 0..48 px (16 taps). Defaults unchanged: 5 and 14.
- Snapshot of the user's accepted look (2026-11-14, `shaderpacks/.horizon-options/petalveil.txt`): reflections
  off, wave_size 0.5, water_ripples 0, water_saturation 0.45, water_glints 0.35, glint_blur 0.95, water_caustics
  0.8, water_opacity 0.7, underwater_murk 0.2, water_clarity 0.25, sun_scale 0.35, volumetric fog on, fog_height
  42. Shadow depth, cloud blur and sun blur sit at the pack defaults (1.6 / 5 / 14). Do not change these defaults
  without a reason.
- The options file still holds stale `glint_scale` / `caustic_scale` keys from before the rename; the live options
  are `glint_size` / `caustic_size` and they are at their defaults. Renaming an option id silently resets the
  player's value — prefer keeping ids when only the mapping changes.
- Headroom rule: the user tunes with values ~50% of what they want and hits the top of sliders, so the maxima
  matter more than the defaults. `water_glints` and `water_caustics` now run 0..4, `glint_blur` 0..1.5 (past 1 the
  wide copy keeps growing: scale*0.55 -> 0.30, lines*1.6 -> 2.6, exponent 0.5 -> 0.2). Keep their tuned values
  meaningful: do not rescale a slider they already use.
- `wave_size` step is 0.05 (was 0.5): the user wanted values between 0 and 0.5 and had nowhere to click. A coarse
  step below 1 is the same class of bug as a narrow range — check the step, not only the bounds.
- `wave_size` is capped at 1: above that it stopped making sense (the user). Animation speeds are separate
  sliders now: `wave_speed` (swell time, shared and used in vertex too), `glint_speed` (multiplies `sparkle`'s
  ridge drift, 3.0 -> 3.0*speed) and `caustic_speed` (multiplies `caustic_net`'s drift).
- Ripple amplitudes were left 5x too small when the swell was cut tenfold: the `Ripples` slider was fine, its
  base was not. `micro` is 0.060 (+0.050 storm), `fine` is 0.035, both multiplied by `water_ripples`, and the fine
  shimmer now scales with `water_ripples` too — not with `wave_size`, which made the two knobs feel coupled.
- All three animation speeds run 0..9 with a 0.1 step: the user reached the top of 0..3 on waves in a minute.
- "Wave size" meant *wavelength* to the user, not amplitude. Split: `wave_size` is now labelled Wave height (id
  kept, so their 0.5 survives) and `wave_length` (0.25..4, default 1) stretches the whole pattern inside
  `wave_field` (`xz / wave_length`), so height and speed keep their meaning.
- Coupling bug: the rain rings' refraction bend carried `water_ripples`, so the Ripples slider visibly drove
  the rain circles. Each effect owns its term: rings use `wetness` only, the fine chop gets its own small bend
  (two noises, x0.004) so `Ripples` still moves the near field.
- With reflections off a water normal has almost no visible channel: the ripples must show through the
  refraction bend (now 0.02 * ripples on two noises) and through brightness layers (0.10 + 0.06), not through
  fresnel. Check the player's `reflections` value before tuning a normal-driven effect.
- Rain rings the user actually wants (`Rain rings = Pack's own`, in rain): they are gated by `wetness` alone,
  and they need a *shading* channel as well as a normal — `ring_shade = length(rip)` brightens their crests
  (`* 1 + 0.35 * lit_ring`), and their refraction bend is now 0.035 * wetness. With the mirror off, a ring that
  only tilts the normal is invisible.
- Ring settings exist now (Water > Surface, after the `Rain rings` choice): `ring_strength` (0..3, bright crests
  and bed bend), `ring_size` (0.4..4, spacing), `ring_lines` (0.4..2.5, how wide one ring is) and `ring_speed`
  (0..9). `ripple_slope` takes `(p, t, cell_size, thickness)` and both its callers pass them.
- The user could not find settings that did not exist: when a feature is "not visible", check whether it has any
  knobs at all, not only whether they are on the right page.
- Every water detail has a checkbox now, as asked: `glints`, `caustics`, `ripples` (bools) gate their sliders;
  `rain_ripples` is a Vanilla/Pack choice. A slider alone is not a switch as far as the user is concerned.
- `water_normal` takes two clocks now (`t` for the swell, `tr` for the chop) plus `ripple_speed`, so the chop's
  animation is independent. Watch out for WGSL scope: the rings block already declares `rt`, a second `rt` in the
  same `if top { ... }` is a redefinition error.
- Vanilla rain rings are particles, not geometry: `render_tick.rs` (`tickWeatherEffects`) spawns splashes gated by
  `settings.particles`; at 2 (Minimal) it breaks after the first spot, so none are drawn and the sound stays. A pack
  cannot touch particles at all in API 0.1. The only ways: the game setting, or a resource pack blanking the
  `particle/*splash*` sprite. The user decided to leave it as is.
- `rain_ripples` is a plain bool again (the user asked for a checkbox): on draws the pack's rings at full
  strength, off hides them. The three-way Vanilla/Hybrid/Own experiment was dropped. The option's description
  tells the player that the game's own rings are rain particles and go away with `Particles = Minimal`.
- Caustics depth falloff is a slider now (`caustic_fade`, 0..3, default 1): `exp(-thickness * fade / (reach*1.6))`,
  on top of the sun-elevation factor. 0 keeps the net to any depth.
- Caustics work under water too: the net (`ridge_net` / `caustic_net`) and its options live in `common.wgsl` now,
  so both stages can use them — the material pass lights the bed seen through the surface, and the composite adds
  the same net at `frame.in_water > 0` (distance fade `exp(-len * caustic_fade * 0.08)` instead of thickness).
- Caustics on the bed alone were invisible from the surface with a low `water_clarity` (the bed's share is
  `absorb = exp(-thickness/reach * 1.6)`), which made them look like an underwater-only effect. The net now also
  multiplies the water's own colour by a softer share (`caustic_gain * 0.45`).
- Caustic stripes down walls happened because the net was sampled on xz only. `caustic_triplanar(p, n, ...)`
  blends the three planes by |n|; the surface normal is rebuilt from two neighbour depths in both stages. Guard
  the cross product: on a flat stretch it vanishes and `normalize` would return NaN (black squares).
- Lesson: caustics belong to the bed only. Applying the same net to the water's own colour (a workaround for
  `water_clarity` 0.25 hiding the bed) painted a pattern on the water plane that read as glued to the camera.
  Retuned instead: the bed's share is 1.3; whether they show from above follows the water's real transparency.
- The above-water caustics slid with the camera because the net's position came from `opaque_depth`: when that
  depth is missing in the material stage the point lands on the far plane and follows the eye. Fixed by anchoring
  the surface path to the water's own `world` position only — never to the bed's depth. The underwater path keeps
  the depth-based position because there the pixel *is* the bed, which is also why the two differ by design.
- Correct architecture for caustics, finally: shade the *blocks*, not the water. A terrain point is under water
  when it is lit in `shadow_map` but shadowed in `shadow_map_translucent` (the map that also holds water and
  glass) — `under_translucent()` in `lighting.wgsl`. The net is then applied in `lit_terrain` with the block's own
  normal, so it follows the block faces, works above and below the surface, and can never appear on the water
  plane. The water stage and the composite no longer draw caustics at all.
- Consequence: caustics need `Shadows` on (no map, no detection) — say so rather than hiding it.
- Accepted: caustics on terrain via the translucent shadow map (0.66.0). The user called it "очень круто" — keep this
  architecture, do not move caustics back into the water or the post pass.
- `caustic_blur` (0..1, default 0) is not a spatial blur: it widens the smoothstep ramp of `ridge_net`
  (lo 0.15L -> 0, hi L -> 1.9L). Three extra noise samples per pixel for a real blur was not worth it on terrain,
  where every pixel pays.
- Glitter and caustics now share one form: `ridge_net` -> `1 - smoothstep(lo, hi, |a-b|)`, with `blur` (0..1.5)
  widening the ramp for both (`lo = lines*max(0.15-0.15*soft,0)`, `hi = lines*(1+0.9*soft)`). The old exponent +
  second-coarse-field code in `sparkle` is gone: it was a historical accident, and the user asked why the two
  differed. Glitter defaults were retuned (lines 0.06, blur 0.6).
- Both blurs run 0..3 now (the internal ramp clamp too): past `hi = 1` the smoothstep never saturates, so the net
  becomes a broad haze — that is the "as smooth as possible" end. Their saved values (0.95 / 0.6) keep meaning
  what they meant at 1.0/1.5.
