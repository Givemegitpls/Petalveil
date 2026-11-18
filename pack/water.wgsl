// Water: vanilla's colour and light as the base, its mirror bent by the swell, and — on the surface —
// its own refraction, so the bed under the water bends with the wave. That last part is what makes a
// wave visible within ten blocks of the camera: with the engine's plain alpha blend there is nothing
// for the normal to move.

override reflections: bool = true;
override ripples: bool = true;
override water_ripples: f32 = 1.0;
override ripple_speed: f32 = 1.0;
override water_opacity: f32 = 1.0;
override water_saturation: f32 = 1.0;
override water_hue: f32 = 0.0;
override water_clarity: f32 = 0.5;
override water_texture: bool = true;
override glints: bool = true;
override water_glints: f32 = 1.0;
override glint_size: f32 = 10.0;
override glint_lines: f32 = 0.08;
override glint_blur: f32 = 0.75;
override glint_speed: f32 = 1.0;
override rain_ripples: bool = true;
override ring_strength: f32 = 1.0;
override ring_size: f32 = 1.0;
override ring_lines: f32 = 1.0;
override ring_speed: f32 = 1.0;

// Rotates a colour around the grey axis, in degrees: the cheap way to shift a hue.
fn hue_turn(c: vec3<f32>, degrees_amount: f32) -> vec3<f32> {
    let a = radians(degrees_amount);
    let axis = vec3<f32>(0.57735, 0.57735, 0.57735);
    return c * cos(a) + cross(axis, c) * sin(a) + axis * dot(axis, c) * (1.0 - cos(a));
}

// The distance of the point behind the water: what the bed's depth in the picture is.
fn view_at(screen: vec2<f32>, depth: f32) -> vec3<f32> {
    let clip = vec4<f32>(screen.x * 2.0 - 1.0, 1.0 - screen.y * 2.0, depth, 1.0);
    let view = frame.projection_inverse * clip;
    return view.xyz / view.w;
}

fn depth_distance(screen: vec2<f32>, depth: f32) -> f32 {
    if depth <= 0.0 {
        return 1e4;
    }
    return length(view_at(screen, depth));
}

// A cheap sky, for when the mirror is off or the surface is not the top: the fog and sky colours
// vanilla gives this frame, with the sun's warm patch.
fn sky_reflection(r: vec3<f32>) -> vec3<f32> {
    let up = smoothstep(-0.05, 0.6, r.y);
    var c = mix(from_linear(frame.fog_color), from_linear(frame.sky_color), up);
    c += vec3<f32>(1.0, 0.82, 0.66) * pow(max(dot(r, frame.sun_direction), 0.0), 6.0) * sun_low() * daylight() * 0.45;
    return c;
}

// Sun glitter: the same ridge as the caustics, only finer and faster, with the same `1 - smoothstep`
// ramp — so its blur slider means exactly what the caustics' one means: how wide the fade from bright to
// dim is.
fn sparkle(xz: vec2<f32>, t: f32, scale: f32, lines: f32, blur: f32) -> f32 {
    return ridge_net(xz, t, scale, lines, 3.0 * glint_speed, blur);
}

fn water_surface(input: MaterialInput) -> vec4<f32> {
    let world = input.position + frame.camera_position;
    let t = frame.time;
    let storm = storm_amount();
    let to_eye = normalize(-input.position);
    // The surface's own normal says whether this is the top of the water. `input.face` describes the
    // block's face and is not reliable for a fluid's top quad.
    let top = abs(input.normal.y) > 0.5;
    let flowing = (input.tags & TAG_WATER_FLOW) != 0u;

    // Vanilla's water: the sprite, the biome tint and vanilla's light. With the texture off the sprite is
    // replaced by a flat pale blue, so the surface is the biome's own colour with no scrolling pixels —
    // the scrolling is what makes the vanilla texture visible, and it fights the waves.
    let sprite = from_linear(select(vec3<f32>(0.78, 0.86, 1.0), input.albedo.rgb, water_texture));
    let tint = from_linear(input.shaded_tint.rgb);
    let lightmap = from_linear(input.lightmap);
    let vanilla = sprite * tint * lightmap;
    let light = luma(lightmap);
    // The hue comes from the biome's own tint, so a swamp stays green and a warm sea stays warm.
    let unit = tint / max(max(tint.r, max(tint.g, tint.b)), 0.001);

    // The fine chop's amount, with its own switch: off, the surface keeps only the swell, the rings and
    // the texture.
    let chop_amount = select(0.0, water_ripples, ripples);

    // The wave normal, and the bend it puts on everything that samples the world through it. The bend
    // is scaled by Wave size on its own: the geometry is centimetres, the visible motion is this.
    var n = input.normal;
    var bend = vec2<f32>(0.0);
    // How strong the rain rings are here: they are also shaded, not only warped, or they stay invisible
    // while the mirror is off.
    var ring_shade = 0.0;

    if top && water_waves {
        let wt = t * wave_speed;
        n = water_normal(world.xz, wt, t * ripple_speed, storm, chop_amount, wave_size);
        n = select(n, -n, input.normal.y < 0.0);
        bend = vec2<f32>(
            wave_field(world.xz + vec2<f32>(0.5, 0.0), wt, storm) - wave_field(world.xz, wt, storm),
            wave_field(world.xz + vec2<f32>(0.0, 0.5), wt, storm) - wave_field(world.xz, wt, storm),
        ) * 0.06 * wave_size;
    }
    // Rain rings, the pack's own, only when the player asked for them and only while the world is wet.
    if top {
        let gain = select(0.0, 1.0, rain_ripples);
        // `wetness` dries asymptotically and sits just above zero for a while; a hard floor means the
        // rings stop as soon as the rain does, instead of lingering at a few percent for minutes.
        let wet = smoothstep(0.06, 0.4, frame.wetness);
        let rt = t * ring_speed;
        let rings = 0.55 * ring_strength * wet * gain;
        let rip = ripple_slope(world.xz, rt, ring_size, ring_lines) * rings;
        n = normalize(n + vec3<f32>(-rip.x, 0.0, -rip.y));
        // The rings' share of the bend is the rings' own: `Ripples` must not touch it, or the chop slider
        // ends up driving the rain circles.
        bend += ripple_slope(world.xz * 0.8, rt, ring_size, ring_lines)
            * (0.035 * ring_strength * wet * gain);
        // The fine chop gets its own bend, so `Ripples` has something to move near the camera even with the
        // mirror off: this is the only channel a normal has left when nothing is reflected.
        let xl = world.xz / max(ripple_length, 0.05);
        let ct = t * ripple_speed;
        bend += vec2<f32>(
            value_noise(xl * 5.0 + vec2<f32>(ct * 0.5, 0.0)) - 0.5,
            value_noise(xl * 5.0 + vec2<f32>(0.0, -ct * 0.45) + vec2<f32>(3.0, 1.0)) - 0.5,
        ) * 0.02 * chop_amount;
    }

    let cos_v = clamp(dot(n, to_eye), 0.0, 1.0);
    let fresnel = 0.03 + 0.97 * pow(1.0 - cos_v, 5.0);
    var mirror = sky_reflection(reflect(-to_eye, n));
    if reflections && top && frame.has_reflection == 1u {
        let uv = clamp(input.screen + n.xz * 0.045 + bend, vec2<f32>(0.0), vec2<f32>(1.0));
        mirror = from_linear(textureSampleLevel(reflection, reflection_sampler, uv, 0.0).rgb);
    }
    // Grey storm sky in the mirror, so rain does not turn the water a bright blue.
    mirror = mix(mirror, vec3<f32>(luma(mirror)) * vec3<f32>(0.88, 0.94, 1.0), storm * 0.55);

    // The sun's glint, in two lobes: a broad one that lights the surface near the camera, where the
    // mirror holds only flat sky, and the tight sparkle on the crests.
    let half_way = normalize(frame.light_direction + to_eye);
    let lit = shadow_at(input.position, vec3<f32>(0.0, 1.0, 0.0), frame.light_direction.y);
    let facing = max(dot(n, half_way), 0.0);
    let glint = direct_color() * lit * (pow(facing, 18.0) * 0.45 + pow(facing, 180.0) * 3.0);

    // Sides of a fall and anything that is not the surface: vanilla's own look and alpha, tinted by the
    // mirror at a slant, with the pale streaks of a falling sheet.
    if !top {
        var color = mix(vanilla, mirror, clamp(fresnel, 0.0, 0.5));
        color = hue_turn(color, water_hue);
        color = mix(vec3<f32>(luma(color)), color, clamp(water_saturation, 0.0, 2.0));
        color += glint * 0.5;
        if flowing {
            let tang = normalize(vec2<f32>(-input.normal.z, input.normal.x) + vec2<f32>(1e-5, 0.0));
            let streak = smoothstep(0.55, 0.95, value_noise(vec2<f32>(dot(world.xz, tang) * 2.4, world.y * 0.6 + t * 2.2)));
            color = mix(color, color * 1.15 + vec3<f32>(0.1, 0.13, 0.15), streak * 0.4);
        }
        let alpha = select(0.85, input.albedo.a, water_texture) * input.shaded_tint.a * clamp(water_opacity, 0.0, 1.0);
        return vec4<f32>(to_linear(shoulder(color)), clamp(alpha, 0.0, 1.0));
    }

    // The surface: our own refraction. The bed is read from the picture taken before the translucent
    // pass, at a coordinate bent by the wave, so the bottom under the water moves with the swell.
    let size = vec2<f32>(textureDimensions(opaque_color));
    let own = length(input.position);
    let plain_uv = clamp(input.screen, vec2<f32>(0.001), vec2<f32>(0.999));
    let plain_at = vec2<i32>(min(plain_uv * size, size - 1.0));
    let plain_depth = textureLoad(opaque_depth, plain_at, 0);
    let plain_dist = depth_distance(plain_uv, plain_depth);
    // How much water stands under this pixel. Along the shoreline there is almost none, and a bent
    // sample there drags the sand above the waterline into the water: the seam then reads as if the
    // block were deformed. The bend grows only once the bed is a block or so below the surface.
    let bendable = smoothstep(0.06, 0.9, max(plain_dist - own, 0.0));
    let bent_uv = clamp(plain_uv + (bend + n.xz * 0.02) * bendable, vec2<f32>(0.001), vec2<f32>(0.999));
    let bent_at = vec2<i32>(min(bent_uv * size, size - 1.0));
    let bent_dist = depth_distance(bent_uv, textureLoad(opaque_depth, bent_at, 0));
    // A tap that comes back in front of the water surface is a block standing out of the water, not the
    // bed: keep the unbent one, so a wall beside the water is never painted across it.
    let use_bent = bent_dist > own + 0.35;
    var behind = from_linear(textureLoad(opaque_color, select(plain_at, bent_at, use_bent), 0).rgb);
    let thickness = max(select(plain_dist, bent_dist, use_bent) - own, 0.0);
    let reach = mix(2.0, 12.0, water_clarity);

    // Shallow water is the bed with a turquoise cast; deep water is its own colour, darkening with depth.
    let deep = 1.0 - exp(-thickness / reach);
    let shallow = vanilla * 1.06 + unit * vec3<f32>(0.10, 0.30, 0.32) * 0.35 * light;
    let drowned = vanilla * 0.45 + unit * vec3<f32>(0.02, 0.10, 0.20) * 0.60 * light;
    var body = mix(shallow, drowned, deep);
    body = hue_turn(body, water_hue);
    body = mix(vec3<f32>(luma(body)), body, clamp(water_saturation, 0.0, 2.0));

    // Light is absorbed red first, then green, so a deep bed fades into the water's own colour.
    let absorb = exp(-thickness / reach * vec3<f32>(1.6, 0.8, 0.55));
    var color = mix(body, behind, absorb);

    // The crests catch the light and the troughs sit in shade: the swell reads even without reflections.
    if water_waves {
        let crest = wave_field(world.xz, t * wave_speed, storm);
        color *= 1.0 + (crest - 0.5) * (0.10 + 0.10 * storm) * min(wave_size, 4.0);
    }
    // The rings themselves: their crests catch the light, their troughs go dark, so the circles read on
    // the surface even with no reflection at all.
    if ring_shade > 0.0 {
        let lit_ring = 0.35 + 0.65 * smoothstep(0.0, 0.35, frame.sun_direction.y);
        color *= 1.0 + ring_shade * 0.35 * lit_ring;
    }

    color = mix(color, mirror, clamp(fresnel, 0.0, 0.85));
    color += glint;

    // Sun glitter: many small highlights instead of the one broad lobe, only where the light is.
    if glints && water_glints > 0.0 && lit > 0.0 {
        let crest = wave_field(world.xz, t * wave_speed, storm);
        // 30 / size puts the default (10) on the scale the pack looked best at, and lets the slider go
        // both finer (2 -> 15) and much coarser (40 -> 0.75).
        let dots = sparkle(world.xz, t, 30.0 / max(glint_size, 0.5), glint_lines, glint_blur) * (0.45 + 0.55 * crest);
        color += direct_color() * dots * water_glints * lit * daylight() * 4.0;
    }

    // The chop's own shading: two uneven layers of brightness, so the surface moves even when the sun is
    // behind the camera and nothing is mirrored. This, not the normal, is what the eye reads as ripples.
    if chop_amount > 0.0 {
        let xl = world.xz / max(ripple_length, 0.05);
        let st = t * ripple_speed;
        let a = value_noise(xl * 2.3 + vec2<f32>(st * 0.35, -st * 0.28)) - 0.5;
        let b = value_noise(xl * 6.1 - vec2<f32>(st * 0.42, st * 0.31) + vec2<f32>(5.0, 2.0)) - 0.5;
        color *= 1.0 + (a * 0.10 + b * 0.06) * min(chop_amount, 2.0);
    }

    // See-through from above: at 1 the water keeps its own colour, at 0 only the bed shows.
    color = mix(behind, color, clamp(water_opacity, 0.0, 1.0));
    // The surface draws itself: what lies behind it is already mixed in, so it writes an opaque pixel.
    return vec4<f32>(to_linear(shoulder(color)), 1.0);
}
