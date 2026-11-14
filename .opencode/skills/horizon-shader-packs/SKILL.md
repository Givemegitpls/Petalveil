---
name: horizon-shader-packs
description: Use when writing, checking, packaging or debugging a shader pack for Horizon (the Rust Minecraft client) in its own WGSL format — horizon-shaders.toml, stages (sky/vertex/material/weather/post), override options, [shadow], [reflection], post passes, pack check errors, cloud or water effects, or when a pack must not break vanilla's light balance. Not for Iris/OptiFine GLSL packs (that is a separate loader).
---

# Horizon shader packs (WGSL)

Horizon has its own shader format: `horizon-shaders.toml` plus `.wgsl` files, validated by naga and
translated to SPIR-V/Metal/HLSL before the game accepts them. One running pack at a time. Packs change
how surfaces, sky and post look; they never change how the world is drawn to the GPU.

Reference, always authoritative:
- `docs/api/shaders-reference.md` — every stage signature, struct field, resource, helper, limit.
- `docs/api/shaders.md` — pack format, options, live reload, cloud/sky keys.
Both are in the clone below, and on GitHub under `raw.githubusercontent.com/horizon-rust/horizon/main/docs/api/`.

## The checker (do this first)

The tool is not installed system-wide; build it once. A **full** clone is required: a sparse checkout
makes cargo fail on the missing workspace members.

```sh
git clone --filter=blob:none https://github.com/horizon-rust/horizon.git /tmp/opencode/horizon
cd /tmp/opencode/horizon && git sparse-checkout disable
cd /tmp/opencode/horizon && cargo build -p horizon-shader-api --bin horizon-shader
```

If cargo cannot reach crates.io, export the environment's HTTP proxy first (`https_proxy`,
`http_proxy`, `CARGO_HTTP_PROXY`).

```sh
BIN=/tmp/opencode/horizon/target/debug/horizon-shader
$BIN check <pack-dir>            # everything the game, launcher and registry check
$BIN check <pack-dir> --json     # for tools
$BIN pack <pack-dir> --out <file.hshader>
$BIN new <dir> --template post|sky|material --name "Name"
```

`check` prints each stage with its expression count and texture reads, or every problem with
`file:line:col`. Treat a red check as "the game will refuse it". Iterate against the checker, not the
game.

## Pack layout

The pack root holds **only** what the format allows: `horizon-shaders.toml`, the `.wgsl` files it
names, `README.md`, `LICENSE` (`.md`/`.txt`), `icon.png`, `[[textures]]` PNGs. Anything else in the
root — `dist/`, `.opencode/`, notes, screenshots — fails the check with
`a pack holds only horizon-shaders.toml, .wgsl files, ...`. Keep the pack in a subfolder
(`pack/`) and build artifacts beside it.

Manifest skeleton:

```toml
schema = 1
id = "my_pack"          # [a-z0-9_]{1,64}, also the key of the saved options
name = "My Pack"
version = "0.1.0"
api = "0.1"
shared = ["common.wgsl"]     # put before every stage's file

[sky]
file = "sky.wgsl"
clouds = false               # the pack draws its own clouds
sun = false                  # the pack draws its own sun (the moon always stays)

[material]
file = "material.wgsl"
files = ["lighting.wgsl"]    # after `shared`, before the stage file
fog = false                  # false: the pack fogs surfaces itself

[vertex]                     # needs [material]; shares its module
file = "vertex.wgsl"

[weather]
file = "weather.wgsl"

[shadow]                     # needs [material] or [[post]]
option = "shadows"           # no map and no shadow pass while off
resolution = 2048            # 256..8192
distance = 128.0             # half the side of the square, 32..512
resolution_option = "shadow_resolution"   # int or numeric choice
distance_option = "shadow_distance"
solid_materials = [1]        # [[materials]] ids drawn whole into the map

[reflection]
option = "reflections"

[[post]]
file = "post/prefilter.wgsl"
output = "my_target"         # later passes read it by name
scale = 0.25                 # 1, 0.5, 0.25
name = "Prefilter"           # label in the GPU time overlay

[budget]
gpu_ms = 2.5
```

## Stages

| Stage | Function | Notes |
| --- | --- | --- |
| sky | `fn sky(input: SkyInput) -> vec4<f32>` | `input.color` is vanilla's sky along the ray; sun/moon/stars/clouds draw over it unless disabled |
| material | `fn material(input: MaterialInput) -> Surface` | terrain only, not entities/particles/hand |
| vertex | `fn vertex(input: VertexInput) -> vec3<f32>` | corners of terrain, also in the shadow pass |
| weather | `fn weather(input: WeatherInput) -> vec4<f32>` | rain/snow streak colour |
| post | `fn post(input: PostInput) -> vec4<f32>` | up to 12, in order; the last draws the frame |

Vanilla's own material, for reference: `albedo * tint * vec4(lightmap, 1.0)`.

`frame` (uniform) carries what a pack usually needs: `sun_direction`, `moon_direction`, `light_direction`
(the body casting this frame's shadows), `day_time`/`game_time`, `sky_color`, `fog_color`, `rain`,
`thunder`, `wetness`, `brightness`, `camera_position`, `time`, `delta_time`, `resolution`,
`eye_light`/`eye_light_smooth`, `eye_in`, `dimension`, `night_vision`, `has_shadow`, `shadow_distance`,
`shadow_resolution`, `shadow_center_texel`, `shadow_view_proj`, `has_reflection`, `water_plane`.

Helpers worth knowing: `shadow_position(p)`, `shadow_map`/`shadow_sampler` with
`textureSampleCompareLevel(shadow_map, shadow_sampler, p.xy, p.z)` (1 lit, 0 shadowed),
`depth_at(uv)`, `view_position(uv, depth)` (post), `block_light_color(p)`, `opaque_color`/`opaque_depth`
(what lies behind water), `reflection`/`reflection_sampler` (the world mirrored about the water plane),
`set_surface`/`surface_at`, LabPBR `block_normal_map`/`block_specular_map`.

## Options

Every player setting is a WGSL `override` of the same id; the manifest declares it:

| `type` | keys | override |
| --- | --- | --- |
| `bool` | `default` | `override x: bool` |
| `float` | `default`, `min`, `max`, `step` | `override x: f32` |
| `int` | `default`, `min`, `max` | `override x: i32` |
| `choice` | `values`, `default` | `override x: u32` (the index) |

Rules the check enforces: every option is used as an `override` somewhere; an `override` that is no
option needs a default; `[[pages]]` must reach every option from the first page. Branch on an option
with `if` — it is a branch on a constant, so the GPU skips it; avoid `select()` when one side is
expensive, since `select` evaluates both.

## Gotchas that cost real time

- **`[material]` and `[vertex]` are one module.** Declaring the same `override` in both is
  `redefinition of x`; declaring it in a `files = [...]` entry is not visible from `vertex.wgsl`
  (`no definition in scope`). Options used by both go in `shared`.
- **Reserved WGSL names.** naga 30 rejects e.g. `target` as an identifier — the error is reported per
  stage, all at once.
- **A `[[post]]` chain disables the player's `taa`/`fxaa`.** Horizon's own anti-aliasing never runs
  while a pack draws its post chain, so a pack that wants smooth edges must do it itself in the last
  pass. Check `horizon-graphics.txt` for `taa:`/`fxaa:` before assuming the engine smooths anything.
- **Clouds, sun and moon are engine geometry.** Clouds come from `crates/horizon-client-render/src/clouds.rs`
  and write real depth; they sit at `CLOUD_HEIGHT` 192.33 in a 4-block layer, and no stage can shade
  them. A picture drawn in `sky.wgsl` looks glued to the camera (no parallax) and the user notices;
  vanilla geometry is usually the right answer. Post effects can only be applied on top, and a mask by
  world height (`view_position` + `camera_position.y`) is how you find cloud pixels.
- **Never average the ground into a cloud blur.** Any screen-space effect that samples freely will drag
  terrain colour into the sky and smear the horizon silhouette; skip taps whose depth is solid ground.
- **Keep vanilla's light as the base.** `albedo * tint * lightmap` is exactly vanilla, including caves,
  torches and night. Add sunlight on top scaled by how much sky the surface sees
  (`smoothstep(0.3, 0.95, input.light.y)`), and let shadows take back a bounded share of the sky light
  only. Replacing the light (e.g. `pow(level, 2.4) * 1.6` for torches, a dark night floor) is what makes
  players complain that caves and nights are ruined.
- **Water**: keep vanilla's alpha and tint; add fresnel reflection and a sun glint, wave the vertex
  corners above the block floor only (`fract(world.y) > 0.02`), or water opens gaps against what is
  under it.
- **Dimensions**: guard Overworld-only effects with `frame.dimension == 0` and return vanilla for the
  rest.

## Limits

12 post passes and 4 post targets, 64 options, 20000 naga expressions and 64 texture reads per stage,
256 KiB per WGSL file, 8 MiB per pack, 1024 `[[materials]]`, 32 `[[tags]]`, 256 `[[lights]]`, 32
`[[particle_lights]]`, 8 `[[textures]]`. Post `output` targets are declared in every pass's prelude
under their name. The format doc says 8 passes; the code says 12 (`MAX_POST_PASSES`) — trust the code.

## Live loop in the game

```sh
ln -sfn "$PWD/pack" ~/.local/share/horizon/shaderpacks/<id>
horizon-launcher packs on --kind shader "<Title or file name>"
horizon-launcher packs list            # what is on, resource and shader packs
```

A symlinked folder is fine and hot-reloads: the game re-checks the pack every half second and rebuilds
the changed stage, keeping the last good one and printing errors into chat. Options are saved to
`shaderpacks/.horizon-options/<id>.txt` and survive edits. Do not also install a packaged `.hshader`
with the same `id` — both would be listed.

## Before packaging

1. `check` green at defaults, minimums and maximums (the tool does this itself).
2. `pack` and confirm the sha256 it prints.
3. Re-read the option descriptions: they are the user's only explanation of the sliders.
4. Confirm nothing outside the format sits in the pack root.
