// How terrain is lit. The base is vanilla's own light, whole and untouched; the sun and moon add
// to it, and the shadow map takes away only a bounded part of what comes from the sky.

override shadows: bool = true;
override shadow_softness: u32 = 1u;
override shadow_strength: f32 = 1.0;
override sun_strength: f32 = 1.0;
override colored_light: f32 = 0.0;

// The colour and strength of this frame's direct light: the sun by day, the moon by night.
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

// 1 where the light reaches the point, 0 in shadow. Outside the map's square, and where there is
// no map, everything is lit, so the pack falls back to vanilla's brightness there.
fn shadow_at(p: vec3<f32>, offset_dir: vec3<f32>, ndl: f32) -> f32 {
    if !shadows || frame.has_shadow == 0u {
        return 1.0;
    }
    let dist = length(p);
    if dist >= frame.shadow_distance {
        return 1.0;
    }
    // A surface lit at a slant falls away from the light across each texel, so the offset and the
    // bias grow with the slant; without them the ground shows stripes at low sun.
    let c = clamp(ndl, 0.06, 1.0);
    let slope = min(sqrt(1.0 - c * c) / c, 6.0);
    let texel = max(frame.shadow_center_texel, 0.005);
    let s = shadow_position(p + offset_dir * texel * (0.7 + 1.6 * slope));
    if any(s.xy <= vec2<f32>(0.0)) || any(s.xy >= vec2<f32>(1.0)) || s.z >= 1.0 {
        return 1.0;
    }
    let m = frame.shadow_view_proj;
    let z_per_block = length(vec3<f32>(m[0].z, m[1].z, m[2].z));
    let z = s.z - z_per_block * texel * (0.5 + 2.0 * slope);

    // Each compare tap is already a 2x2 bilinear filter, so a fixed grid of them needs no noise.
    let t = 1.0 / max(frame.shadow_resolution, 1.0);
    var lit = 0.0;
    if shadow_softness == 0u {
        lit = textureSampleCompareLevel(shadow_map, shadow_sampler, s.xy, z);
    } else if shadow_softness == 1u {
        for (var i = 0; i < 4; i++) {
            let o = vec2<f32>(f32(i & 1), f32(i >> 1)) * 2.0 - 1.0;
            lit += textureSampleCompareLevel(shadow_map, shadow_sampler, s.xy + o * t, z);
        }
        lit *= 0.25;
    } else {
        for (var i = 0; i < 9; i++) {
            let o = vec2<f32>(f32(i % 3), f32(i / 3)) - 1.0;
            lit += textureSampleCompareLevel(shadow_map, shadow_sampler, s.xy + o * 1.5 * t, z);
        }
        lit /= 9.0;
    }
    return mix(lit, 1.0, smoothstep(0.85, 1.0, dist / frame.shadow_distance));
}

fn lit_terrain(input: MaterialInput) -> vec4<f32> {
    let albedo = input.albedo.rgb;
    let tint = input.tint.rgb;
    // Vanilla first and whole: this is what the scene looks like without the pack, so a cave, a
    // cellar and the night keep vanilla's brightness and torchlight.
    var color = albedo * tint * input.lightmap * VANILLA_GAIN;

    let leaf = input.material == MAT_LEAVES;
    let plant = input.material >= MAT_PLANT && input.material <= MAT_VINE;
    let n = input.normal;
    let l = frame.light_direction;
    let day = daylight();
    // How much of the sky this point sees. Caves, cellars and roofs sit at 0, where no sun
    // component and no shadow apply at all: that is what keeps the balance.
    let open = smoothstep(0.32, 0.92, input.light.y);

    // Foliage faces the light whichever way it turns, and lets a little of it through.
    let facing = dot(n, l);
    var nl = max(facing, 0.0) * smoothstep(0.0, 0.2, facing);
    if leaf {
        nl = pow(clamp(facing * 0.5 + 0.5, 0.0, 1.0), 1.4) * 0.85;
    } else if plant {
        nl = 0.4 + 0.5 * abs(facing);
    }

    if open > 0.001 && sun_strength > 0.0 {
        let offset_dir = select(n, l, plant);
        let slant = select(facing, 1.0, plant);
        let shadow = shadow_at(input.position, offset_dir, slant);
        // A shadow takes back a share of vanilla's sky light, and never more than `SHADE` times
        // the player's Shadow depth.
        let depth = SHADE * clamp(shadow_strength, 0.0, 3.0);
        color *= 1.0 - depth * day * open * (1.0 - shadow);
        color += albedo * tint * direct_color() * nl * shadow * open;
        // Leaves and blades glow a little with the sun behind them: the fairy-tale part of daylight.
        if leaf || plant {
            let to_eye = normalize(-input.position);
            let through = pow(max(dot(to_eye, -l), 0.0), 4.0);
            color += albedo * tint * vec3<f32>(0.92, 1.0, 0.72) * through * 0.14 * day * open * shadow;
        }
    }

    // Coloured block light, when the player asks for it: a hue shift only, so brightness and the
    // way walls stop light stay vanilla's.
    if colored_light > 0.0 {
        let cl = block_light_color(input.position);
        let unit = cl.rgb / max(max(cl.r, max(cl.g, cl.b)), 0.001);
        let shift = clamp(cl.a, 0.0, 1.0) * colored_light * 0.6;
        color = color * mix(vec3<f32>(1.0), unit, shift);
    }

    // A block that shines keeps shining: redstone, glowstone and lava.
    color = max(color, albedo * tint * input.emission);
    return vec4<f32>(shoulder(color), input.albedo.a);
}
