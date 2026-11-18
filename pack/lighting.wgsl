// How terrain is lit. The base is vanilla's own light, whole and untouched; the sun and moon add
// to it, and the shadow map takes away only a bounded part of what comes from the sky.

override shadows: bool = true;
override shadow_softness: u32 = 1u;
override shadow_strength: f32 = 1.0;
override moon_shadows: bool = true;
override moon_shadow_strength: f32 = 0.6;
override cloud_shadows: f32 = 0.5;
override cloud_shadow_size: f32 = 1.0;
override cloud_shadow_cover: f32 = 0.5;
override colored_light: f32 = 0.0;

// Where the engine's clouds would be over this point, following the light: the shadow of the cloud layer
// is the cloud pattern sampled where the ray to the light crosses 192 blocks. The pattern is the pack's
// own, so it does not line up with the clouds you see — it reads as broad patches drifting over the land.
fn cloud_shade(p: vec3<f32>) -> f32 {
    let l = frame.light_direction;
    if l.y <= 0.02 {
        return 0.0;
    }
    let height = 192.33 - p.y;
    if height <= 0.0 {
        return 0.0;
    }
    let t = height / l.y;
    if t > 480.0 {
        return 0.0;
    }
    let at = p.xz + l.xz * t + vec2<f32>(frame.time * 0.7, frame.time * 0.2);
    // `size` stretches the patches, `cover` decides how much of the sky they take: fbm2 averages near
    // 0.38, so the threshold band is what moves.
    let scale = 0.010 / max(cloud_shadow_size, 0.05);
    let n = fbm2(at * scale + vec2<f32>(5.1, 2.7));
    let low = mix(0.42, 0.10, clamp(cloud_shadow_cover, 0.0, 1.0));
    return smoothstep(low, low + 0.25, n);
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

// 1 where a translucent surface (water, stained glass, ice) stands between this point and the light: the
// point is lit in the solid map but shadowed in the map that also holds the translucent terrain. That is
// how a block under water is recognised on the CPU-free side, and it works whether the eye is above the
// water or in it.
fn under_translucent(p: vec3<f32>) -> f32 {
    if frame.has_shadow == 0u {
        return 0.0;
    }
    let s = shadow_position(p);
    if any(s.xy <= vec2<f32>(0.0)) || any(s.xy >= vec2<f32>(1.0)) || s.z >= 1.0 {
        return 0.0;
    }
    let solid = textureSampleCompareLevel(shadow_map, shadow_sampler, s.xy, s.z);
    let through = textureSampleCompareLevel(shadow_map_translucent, shadow_sampler, s.xy, s.z);
    return clamp(solid - through, 0.0, 1.0);
}

fn lit_terrain(input: MaterialInput) -> vec4<f32> {
    // The stage's doors: everything here is vanilla's gamma, as it was in API 0.1 (see common.wgsl).
    let albedo = from_linear(input.albedo.rgb);
    let tint = from_linear(input.shaded_tint.rgb);
    let lightmap = from_linear(input.lightmap);
    // Vanilla first and whole: this is what the scene looks like without the pack, so a cave, a
    // cellar and the night keep vanilla's brightness and torchlight.
    var color = albedo * tint * lightmap * VANILLA_GAIN;

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

    // Clouds pass over the land and take their share of the light with them. Most of a surface's light is
    // vanilla's sky term, not our sun add-on, so the shade has to come out of that term as well — at ten
    // percent of the base it was invisible.
    var clouds = 0.0;
    if cloud_shadows > 0.0 && open > 0.001 {
        clouds = cloud_shade(input.position + frame.camera_position) * clamp(cloud_shadows, 0.0, 1.0);
        color *= 1.0 - 0.35 * clouds;
    }

    if open > 0.001 && sun_strength > 0.0 {
        let offset_dir = select(n, l, plant);
        let slant = select(facing, 1.0, plant);
        let shadow = shadow_at(input.position, offset_dir, slant);
        // A shadow takes back a share of vanilla's sky light. Day and night have their own weight and
        // their own switch: at night a full-weight shade would read as a hole in an already dark world,
        // and some players want no moon shadows at all.
        let depth_day = SHADE * clamp(shadow_strength, 0.0, 3.0) * day;
        let depth_night = SHADE * clamp(moon_shadow_strength, 0.0, 3.0) * nightfall()
            * select(0.0, 1.0, moon_shadows);
        let depth = max(depth_day, depth_night);
        color *= 1.0 - depth * open * (1.0 - shadow);
        color += albedo * tint * direct_color() * nl * shadow * open * (1.0 - 0.85 * clouds);
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
        let lit_hue = from_linear(cl.rgb);
        let unit = lit_hue / max(max(lit_hue.r, max(lit_hue.g, lit_hue.b)), 0.001);
        let shift = clamp(cl.a, 0.0, 1.0) * colored_light * 0.6;
        color = color * mix(vec3<f32>(1.0), unit, shift);
    }

    // Caustics belong to the blocks under the water, never to the water's own surface: they are sunlight
    // that came through the surface and broke up on the bottom.
    if caustics && water_caustics > 0.0 {
        let under = under_translucent(input.position);
        if under > 0.0 {
            let sun_lit = 0.35 + 0.65 * smoothstep(0.0, 0.35, frame.sun_direction.y);
            let reach = exp(-length(input.position) * caustic_fade * 0.03) * sun_lit * under;
            let net = caustic_triplanar(input.position + frame.camera_position, n, frame.time * caustic_speed,
                1.0 / max(caustic_size, 0.05), caustic_lines);
            color *= 1.0 + net * water_caustics * reach * 1.3;
        }
    }

    // A block that shines keeps shining: redstone, glowstone and lava. `emission` is data (the
    // block's light level over 15), so it stays a multiplier in this space, as it was.
    color = max(color, albedo * tint * input.emission);
    return vec4<f32>(to_linear(shoulder(color)), input.albedo.a);
}
