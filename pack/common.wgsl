// Petalveil, shared by every stage, put after Horizon's prelude (which declares `frame`).
// Positions are camera-relative, in blocks; directions are in world axes (x east, y up, z south).
//
// The rule this pack is built on: vanilla's own light (`MaterialInput.lightmap`) is the base and
// nothing here darkens it. The sun and moon only add, and the shadow map only takes away a
// bounded part of the light that comes from the sky. A cave, a cellar and the night keep the
// brightness and the colours vanilla gives them.

// The manifest's [[materials]] ids.
const MAT_LEAVES: u32 = 1u;
const MAT_PLANT: u32 = 2u;
const MAT_TALL_LOWER: u32 = 3u;
const MAT_TALL_UPPER: u32 = 4u;
const MAT_VINE: u32 = 5u;

// Bit 0 of MaterialInput.tags: block/water_flow.
const TAG_WATER_FLOW: u32 = 1u;

// How much direct sunlight adds on top of vanilla's light, at Sunlight 1. Small on purpose:
// vanilla's daylight is already the base, and a bigger number washes bright textures out.
const SUN_ADD: f32 = 0.18;
// The same for the moon: enough to read the ground by, not enough to re-light the night.
const MOON_ADD: f32 = 0.05;
// The most a shadow takes away from vanilla's sky light, so a shadow is shade and never night.
const SHADE: f32 = 0.18;
// Vanilla's own light, the base of everything: albedo * tint * lightmap, untouched.
const VANILLA_GAIN: f32 = 1.0;

// Declared here because the material and vertex stages share one module: a wave option belongs to both.
override water_waves: bool = true;
// Sunlight's gain, used by the terrain light and by the fog's in-scattering.
override sun_strength: f32 = 1.0;

fn luma(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn overworld() -> bool {
    return frame.dimension == 0;
}

// 1 by day, 0 by night, eased across the horizon.
fn daylight() -> f32 {
    return select(0.0, smoothstep(-0.1, 0.12, frame.sun_direction.y), overworld());
}

// 1 by night, 0 by day.
fn nightfall() -> f32 {
    return select(0.0, 1.0 - smoothstep(-0.16, 0.02, frame.sun_direction.y), overworld());
}

// 1 with the sun on the horizon, 0 from a third of the way up.
fn sun_low() -> f32 {
    return 1.0 - smoothstep(0.0, 0.32, abs(frame.sun_direction.y));
}

// Rain smoothed into one 0..1 level: waves, sky and glow follow it instead of stepping.
fn storm_amount() -> f32 {
    return clamp(frame.wetness * 0.45 + frame.thunder * 0.75, 0.0, 1.0);
}

// Gives a colour another hue while keeping its brightness, so a tint never darkens a scene.
fn retint(c: vec3<f32>, hue: vec3<f32>) -> vec3<f32> {
    let t = hue / max(luma(hue), 0.001);
    return c * t;
}

// The colour and strength of this frame's direct light: the sun by day, the moon by night. Lives in
// the shared file because the fog pass lights its air with it too.
fn direct_color() -> vec3<f32> {
    let l = frame.light_direction;
    let is_sun = dot(l, frame.sun_direction) > 0.0;
    // Orange only near the horizon: by mid-morning the light is a soft warm white.
    let high = smoothstep(0.0, 0.3, l.y);
    let sun = mix(vec3<f32>(1.0, 0.62, 0.34), vec3<f32>(1.0, 0.96, 0.9), high);
    let moon = vec3<f32>(0.62, 0.72, 1.0);
    let weather = 1.0 - 0.85 * max(frame.rain, frame.thunder);
    // A sunset gives a little more of its warm light, which the fade at the horizon then dims.
    let gain = select(MOON_ADD, SUN_ADD * (1.0 + 0.8 * sun_low()), is_sun) * sun_strength;
    return select(moon, sun, is_sun) * gain * smoothstep(0.0, 0.06, l.y) * weather;
}

// A soft shoulder above 0.78, so bright light rolls into white instead of clipping.
fn shoulder(c: vec3<f32>) -> vec3<f32> {
    let over = max(c - vec3<f32>(0.78), vec3<f32>(0.0));
    return min(c, vec3<f32>(0.78)) + 0.22 * (vec3<f32>(1.0) - exp(-over * 4.5));
}

// Integer hash: a float hash turns into stripes far from the world origin.
fn hash21(p: vec2<f32>) -> f32 {
    let ip = vec2<i32>(floor(p));
    var h = (bitcast<u32>(ip.x) * 1597334673u) ^ (bitcast<u32>(ip.y) * 3812015801u);
    h = (h ^ (h >> 16u)) * 2246822519u;
    h = (h ^ (h >> 13u)) * 3266489917u;
    h = h ^ (h >> 16u);
    return f32(h >> 8u) * (1.0 / 16777216.0);
}

fn value_noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    let a = hash21(i);
    let b = hash21(i + vec2<f32>(1.0, 0.0));
    let c = hash21(i + vec2<f32>(0.0, 1.0));
    let d = hash21(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn fbm2(p: vec2<f32>) -> f32 {
    return 0.5 * value_noise(p) + 0.25 * value_noise(p * 2.03 + vec2<f32>(1.7, 9.2));
}

fn fbm3(p: vec2<f32>) -> f32 {
    return fbm2(p) + 0.125 * value_noise(p * 4.01 + vec2<f32>(8.3, 2.8));
}

// Interleaved gradient noise (Jimenez 2014): a cheap, well spread 0..1 value per pixel.
fn ign(pixel: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(pixel, vec2<f32>(0.06711056, 0.00583715))));
}

// The height of the water surface at world `xz`, 0..1 (1 the crest). It depends on world position
// only, so neighbouring blocks meet without seams.
fn wave_field(xz: vec2<f32>, t: f32, storm: f32) -> f32 {
    let speed = 0.5 + 1.6 * storm;
    let w1 = sin(dot(xz, vec2<f32>(0.78, 0.62)) * 0.85 + t * 0.9 * speed);
    let w2 = sin(dot(xz, vec2<f32>(-0.55, 0.83)) * 1.25 + t * 1.2 * speed + 1.7);
    let w3 = sin(dot(xz, vec2<f32>(0.2, -0.98)) * 2.1 - t * 1.6 * speed + 4.2);
    let drift = sin(xz.x * 0.23 + t * 0.11) * sin(xz.y * 0.19 - t * 0.09);
    return clamp(0.5 + (w1 * 0.45 + w2 * 0.3 + w3 * (0.15 + 0.15 * storm) + drift * 0.1) * 0.5, 0.0, 1.0);
}

// The water surface's normal: the swell's slope from two extra samples, plus fine ripples.
fn water_normal(xz: vec2<f32>, t: f32, storm: f32) -> vec3<f32> {
    let e = 0.07;
    let h = wave_field(xz, t, storm);
    let dx = (wave_field(xz + vec2<f32>(e, 0.0), t, storm) - h) / e;
    let dz = (wave_field(xz + vec2<f32>(0.0, e), t, storm) - h) / e;
    let slope = -vec2<f32>(dx, dz) * (0.1 + 0.16 * storm);
    let micro = vec2<f32>(
        value_noise(xz * 2.7 + vec2<f32>(t * 0.3, -t * 0.24)) - 0.5,
        value_noise(xz * 3.3 + vec2<f32>(-t * 0.26, t * 0.29) + 7.0) - 0.5,
    ) * (0.05 + 0.12 * storm);
    return normalize(vec3<f32>(slope.x + micro.x, 1.0, slope.y + micro.y));
}

// Ring ripples on wet ground: the slope of a field of spreading circles.
fn ripple_slope(p: vec2<f32>, t: f32) -> vec2<f32> {
    let cell = floor(p * 1.6);
    let f = fract(p * 1.6) - 0.5;
    let phase = fract(t * 0.7 + hash21(cell));
    let r = length(f);
    let q = (r - phase * 0.5) * 12.0;
    let ring = sin((r - phase * 0.5) * 40.0) * exp(-q * q) * (1.0 - phase);
    return f / max(r, 0.001) * ring * 1.2;
}
