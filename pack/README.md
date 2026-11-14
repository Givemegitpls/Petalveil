# Petalveil

A light shader pack for [Horizon](https://github.com/horizon-rust/horizon), the Rust version of Minecraft. It
keeps vanilla's own light as its base, so caves, cellars, torchlight and the night keep the brightness and the
colours vanilla gives them, and adds a pastel sky, its own clouds, waves and reflections on water, plants in the
wind and a soft glow on top.

## What it changes

| Effect | How | Cost |
| --- | --- | --- |
| Sun and moon shadows | A distorted shadow map of solid terrain, slope-scaled bias, 1/4/9-tap grid PCF | the shadow pass, and up to 9 compare taps per pixel |
| Vanilla's light kept | Every surface starts as `albedo * tint * lightmap`, which is exactly vanilla; nothing darkens it | none |
| Sunlight and moonlight | Added on top of vanilla's light, only where the sky shows (`light.y`), so a cave or a roof gets none | a few multiplies |
| Shadows that spare the balance | A shadow takes back at most 18% of the sky's light, and only by day, in the open | none |
| Water | Rolling waves and their normals, the world's mirror at a slant (Fresnel), a sun glint, depth shading, storm foam, flowing sheets | Horizon's half-resolution mirror, can be off |
| Waving leaves and plants | Vertex stage, continuous across two-block plants, still in caves and pots | a few `sin`s per vertex |
| Sky | Vanilla's colour with a lilac and peach veil, a cooler night that keeps its brightness | per sky pixel |
| Sun | A circle on a grid of 8 to 48 cells, hard-edged on purpose. `Sun size` scales vanilla's quad tangent; 0.25, the default, is about 8 degrees across and matches what the game shows. Vanilla's clouds still hide it | a few dots per sky pixel |
| Rainbow | The primary bow opposite the sun while the rain dries | a few multiplies |
| Sun blur | A second spiral blur, on the sun's own pixels only (a ray-alignment mask against `sun_direction`), so its pixel rim turns into a glow. Off by default | a depth tap per pixel, twelve taps on the sun |
| Cloud edge blur | A radial blur (a Vogel spiral of 16 taps) applied only where the depth says the pixel is in the cloud layer, and weighted to the rim, so the body of a cloud keeps its shading. The slider is the radius in pixels | five depth taps per pixel, sixteen blur taps on a rim |
| Glow | Karis-averaged bright pass and a nine-tap blur, both at a quarter of the resolution | ~1/16 of the pixels |
| Sun rays | A dithered march toward the sun's screen position over the sky mask, a quarter of the resolution; the sun may be outside the frame, and only samples inside it count | ~1/16 of the pixels |
| Volumetric fog | 8 steps of a march toward what the depth holds, lit by the sun through the shadow map, at a quarter of the resolution; off by default | ~1/16 of the pixels |
| Grade | A hair of lift in the deepest black, gentle S-curve, saturation, optional vignette, dither | one pass |

The Nether and the End are left exactly as vanilla draws them.

## Settings

**Options > Horizon Settings > Shader Packs > Petalveil > Shader Options…**

- **Lighting**: shadows off/on and their detail, distance, edge softness and depth (`Shadow depth` 0–3, 1 is the
  default, higher is a deeper shade); `Sunlight` 0–2 (0 keeps vanilla's brightness); `Coloured light` shifts the
  hue of torches, soul fire and the like without brightening them.
- **Water**: reflections, waves, how far you see into water.
- **Nature**: waving plants and the wind's strength.
- **Sky**: pastel amount, the sun's cell count and size, the sun's blur, cloud edge blur radius, the rainbow, the night mood.
- **Fog**: volumetric fog off/on, its thickness and height, and the march's step count (8 is the cheap one).
- **Camera**: glow, sun rays, exposure, contrast, saturation, vignette.

Vanilla's sun and vanilla's clouds are kept: they are geometry in the world, so they hide each other and move
against the ground when you walk, which a picture drawn on the sky dome cannot do. Cloud rims are softened by the
pack's own anti-aliasing pass instead.

For a slower GPU: shadows off, reflections off, clouds off.

## Install

Put `petalveil-<version>.hshader` in the instance's `shaderpacks/` folder, or add it from the launcher
(`horizon-launcher packs add <file>`), then pick it on the Shader Packs page.

Working on it: link this folder into `shaderpacks/` and the game reloads it within half a second of every save.

## Develop

This pack is checked and packaged with Horizon's own tool:

```
horizon-shader check pack
horizon-shader pack pack
```

## Credits

Original code, MIT licensed. Techniques are the published ones: interleaved gradient noise and the Karis
average (Jimenez, *Next Generation Post Processing in Call of Duty: Advanced Warfare*, 2014), Schlick's Fresnel
approximation (1994), vanilla's own lightmap and cloud grid. No code and no assets from other shader packs.
