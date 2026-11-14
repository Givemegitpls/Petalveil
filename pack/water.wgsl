// Water: vanilla's colour and see-through kept, with waves, the world's mirror at a slant, a sun
// glint and storm foam. No pass of its own: the mirror is Horizon's half-resolution reflection.

override reflections: bool = true;
override water_clarity: f32 = 0.5;

// The distance of the point behind the water, for the water's own depth: not used to change what
// shows through (Horizon blends that as vanilla does), only to know how deep it is.
fn depth_distance(screen: vec2<f32>, depth: f32) -> f32 {
    if depth <= 0.0 {
        return 1e4;
    }
    let clip = vec4<f32>(screen.x * 2.0 - 1.0, 1.0 - screen.y * 2.0, depth, 1.0);
    let view = frame.projection_inverse * clip;
    return length(view.xyz / view.w);
}

// A cheap sky, for when the mirror is off or the surface is not the top: the fog and sky colours
// vanilla gives this frame, with the sun's warm patch.
fn sky_reflection(r: vec3<f32>) -> vec3<f32> {
    let up = smoothstep(-0.05, 0.6, r.y);
    var c = mix(frame.fog_color, frame.sky_color, up);
    c += vec3<f32>(1.0, 0.82, 0.66) * pow(max(dot(r, frame.sun_direction), 0.0), 6.0) * sun_low() * daylight() * 0.45;
    return c;
}

fn water_surface(input: MaterialInput) -> vec4<f32> {
    let world = input.position + frame.camera_position;
    let t = frame.time;
    let storm = storm_amount();
    let to_eye = normalize(-input.position);
    let top = input.face == 1u;
    let flowing = (input.tags & TAG_WATER_FLOW) != 0u;

    // Vanilla's water: the sprite, the biome tint and vanilla's light. Everything below is a
    // change of hue or a reflection over it, never a change of how bright the water is.
    let vanilla = input.albedo.rgb * input.tint.rgb * input.lightmap;

    var n = input.normal;
    if top && water_waves {
        n = water_normal(world.xz, t, storm);
        n = select(n, -n, input.normal.y < 0.0);
    }
    if top {
        let rip = ripple_slope(world.xz, t) * frame.wetness * 0.4;
        n = normalize(n + vec3<f32>(-rip.x, 0.0, -rip.y));
    }

    // How deep the water is here, read from what the world drew before the water: shallow water
    // keeps more of the bed's colour showing through, deep water keeps its own.
    var body = vanilla;
    if top {
        let size = vec2<f32>(textureDimensions(opaque_depth));
        let at = vec2<i32>(min(input.screen * size, size - 1.0));
        let thickness = max(depth_distance(input.screen, textureLoad(opaque_depth, at, 0)) - length(input.position), 0.0);
        let reach = mix(1.5, 9.0, water_clarity);
        let absorb = exp(-thickness / reach * vec3<f32>(1.6, 0.8, 0.55));
        // Deep water darkens a little toward the tint: the bed's colour is what the eye sees first.
        body = mix(vanilla * 0.8, vanilla, absorb);
    }

    let cos_v = clamp(dot(n, to_eye), 0.0, 1.0);
    let fresnel = 0.03 + 0.97 * pow(1.0 - cos_v, 5.0);
    var mirror = sky_reflection(reflect(-to_eye, n));
    if reflections && top && frame.has_reflection == 1u {
        let uv = clamp(input.screen + n.xz * 0.02, vec2<f32>(0.0), vec2<f32>(1.0));
        mirror = textureSampleLevel(reflection, reflection_sampler, uv, 0.0).rgb;
    }
    // Grey storm sky in the mirror, so rain does not turn the water a bright blue.
    mirror = mix(mirror, vec3<f32>(luma(mirror)) * vec3<f32>(0.88, 0.94, 1.0), storm * 0.55);
    var color = mix(body, mirror, clamp(fresnel, 0.0, 0.85));

    // The sun's glint: one tight highlight on the crests.
    let half_way = normalize(frame.light_direction + to_eye);
    let lit = shadow_at(input.position, vec3<f32>(0.0, 1.0, 0.0), frame.light_direction.y);
    color += direct_color() * pow(max(dot(n, half_way), 0.0), 180.0) * lit * 3.0;

    // Foam on the crests while it blows.
    if storm > 0.3 && water_waves {
        let crest = wave_field(world.xz, t, storm);
        let foam = smoothstep(0.8, 1.0, crest) * smoothstep(0.3, 0.85, storm);
        color = mix(color, vec3<f32>(0.86, 0.92, 0.96) * (0.35 + 0.65 * luma(input.lightmap)), foam * 0.55);
    }

    // A falling sheet of water: pale streaks running down, as vanilla's flowing texture is.
    if flowing && !top {
        let tang = normalize(vec2<f32>(-input.normal.z, input.normal.x) + vec2<f32>(1e-5, 0.0));
        let streak = smoothstep(0.55, 0.95, value_noise(vec2<f32>(dot(world.xz, tang) * 2.4, world.y * 0.6 + t * 2.2)));
        color = mix(color, color * 1.15 + vec3<f32>(0.1, 0.13, 0.15), streak * 0.4);
    }

    return vec4<f32>(shoulder(color), input.albedo.a * input.tint.a);
}
