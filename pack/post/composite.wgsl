// The last pass: cloud edges, glow and sun rays over the world, then a soft grade that keeps
// vanilla's balance.

override volumetric_fog: bool = false;
override cloud_edges: f32 = 8.0;
override bloom: f32 = 0.35;
override sun_rays: f32 = 0.35;
override moon_rays: bool = true;
override moon_rays_strength: f32 = 0.5;
override night_mood: f32 = 0.35;
override exposure: f32 = 1.0;
override contrast: f32 = 1.03;
override saturation: f32 = 1.06;
override vignette: f32 = 0.0;
override underwater_murk: f32 = 0.35;

// Vanilla's clouds are geometry the engine draws, at a fixed height, four blocks thick; a pack has
// no stage for them. What it can do is find them in the picture: a pixel whose depth puts it in the
// cloud layer is cloud. This is the height vanilla's clouds sit at (`clouds::CLOUD_HEIGHT`).
const CLOUD_Y: f32 = 192.33;
// How far the point's height may be from the layer's and still count as cloud.

// How far the point's height may be from the layer's and still count as cloud. Vanilla's layer is
// four blocks thick, so the band is tight on purpose: a mountain peak that happens to reach the
// clouds' height should not be mistaken for one.
fn band_at(y: f32) -> f32 {
    let dy = y - CLOUD_Y;
    return smoothstep(-2.0, 0.0, dy) * (1.0 - smoothstep(4.5, 6.5, dy));
}

fn picture(uv: vec2<f32>) -> vec3<f32> {
    return textureSampleLevel(scene_color, linear_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
}

// 1 where the point at `depth` lies in the cloud layer, 0 elsewhere: sky is 0 too.
fn in_cloud_layer(uv: vec2<f32>, depth: f32) -> f32 {
    if depth <= 0.0 {
        return 0.0;
    }
    let v = view_position(uv, depth);
    // A cloud right at the camera is a wall of white; its own rim is what wants softening.
    let far_enough = smoothstep(16.0, 32.0, length(v));
    return band_at(v.y + frame.camera_position.y) * far_enough;
}

fn cloud_mask(uv: vec2<f32>) -> f32 {
    return in_cloud_layer(uv, depth_at(uv));
}

// A real blur, not an edge walk: a Vogel spiral of taps over a disc of `radius` pixels. Only cloud
// and sky taps count, never the ground: a cloud standing behind a hill would otherwise bleed into
// the hill and blur the land's own outline. The mean of the cloud taps says how much of the disc is
// cloud, so a rim is softened fully, the body of a cloud gently, and its middle left alone.
fn cloud_soft(uv: vec2<f32>, radius: f32, seed: f32) -> vec3<f32> {
    let px = 1.0 / frame.resolution;
    var cover = 0.0;
    var taps = 0.0;
    var sum = vec3<f32>(0.0);
    var wsum = 0.0;
    for (var i = 0; i < 24; i++) {
        let angle = f32(i) * 2.39996323 + seed * 6.2831853;
        // `r` grows with the square root of the index, so the taps spread evenly over the disc. Twenty
        // four of them keep a wide radius from opening gaps between samples.
        let r = sqrt((f32(i) + 0.5) / 24.0) * radius;
        let suv = clamp(uv + vec2<f32>(cos(angle), sin(angle)) * r * px, vec2<f32>(0.0), vec2<f32>(1.0));
        let d = depth_at(suv);
        let cloud = in_cloud_layer(suv, d);
        if d > 0.0 && cloud <= 0.0 {
            // The ground: not mixed in at all.
            continue;
        }
        cover += cloud;
        taps += 1.0;
        // The middle weighs more, so a wide radius still keeps the cloud's own shade.
        let w = 1.0 / (1.0 + r * 0.08);
        sum += picture(suv) * w;
        wsum += w;
    }
    if taps < 1.0 {
        return picture(uv);
    }
    let covered = cover / taps;
    let blurred = sum / max(wsum, 0.001);
    // 1 where the disc is half cloud and half not: the rim.
    let rim = clamp(4.0 * covered * (1.0 - covered), 0.0, 1.0);
    // Inside a cloud vanilla still shades each face of each cube, which shows as hard bands across
    // the body; a gentler wash over the body softens those without eating the silhouette.
    let body = smoothstep(0.55, 0.95, covered) * 0.65;
    return mix(picture(uv), blurred, max(rim, body));
}

fn post(input: PostInput) -> vec4<f32> {
    // Clouds and a couple of pixels of sky beside them; the land is never touched.
    var c = input.color.rgb;
    if cloud_edges > 0.0 {
        let px = 1.0 / frame.resolution;
        let own = cloud_mask(input.uv);
        let sky = depth_at(input.uv) <= 0.0;
        var near_cloud = false;
        if own > 0.0 {
            near_cloud = true;
        } else if sky {
            let ring = vec2<f32>(px.x, px.y) * 2.0;
            near_cloud = cloud_mask(input.uv + vec2<f32>(ring.x, 0.0)) > 0.0
                || cloud_mask(input.uv - vec2<f32>(ring.x, 0.0)) > 0.0
                || cloud_mask(input.uv + vec2<f32>(0.0, ring.y)) > 0.0
                || cloud_mask(input.uv - vec2<f32>(0.0, ring.y)) > 0.0;
        }
        if near_cloud {
            c = cloud_soft(input.uv, cloud_edges, ign(floor(input.pixel / vec2<f32>(4.0)) * 4.0));
        }
    }
    let day = daylight();
    let night = nightfall();

    // Fog sits between the world and the glow: the shafts are part of the picture, not a lens flare.
    if volumetric_fog {
        let fog = textureSampleLevel(petal_fog, linear_sampler, input.uv, 0.0);
        c = c * (1.0 - clamp(fog.a, 0.0, 1.0)) + fog.rgb;
    }

    if bloom > 0.0 {
        c += textureSampleLevel(petal_glow_b, linear_sampler, input.uv, 0.0).rgb * bloom;
    }
    if sun_rays > 0.0 {
        // A nine-tap tent over the quarter-size ray target. It is what turns the march's dithered
        // samples into a gradient: no grain, no spokes, and it still follows the clouds' edges.
        let r = 1.0 / vec2<f32>(max(textureDimensions(petal_rays), vec2<u32>(1u, 1u)));
        let at = input.uv;
        var ray = textureSampleLevel(petal_rays, linear_sampler, at, 0.0).r * 0.25;
        ray += textureSampleLevel(petal_rays, linear_sampler, at + vec2<f32>(r.x, 0.0), 0.0).r * 0.125;
        ray += textureSampleLevel(petal_rays, linear_sampler, at - vec2<f32>(r.x, 0.0), 0.0).r * 0.125;
        ray += textureSampleLevel(petal_rays, linear_sampler, at + vec2<f32>(0.0, r.y), 0.0).r * 0.125;
        ray += textureSampleLevel(petal_rays, linear_sampler, at - vec2<f32>(0.0, r.y), 0.0).r * 0.125;
        ray += textureSampleLevel(petal_rays, linear_sampler, at + r, 0.0).r * 0.0625;
        ray += textureSampleLevel(petal_rays, linear_sampler, at - r, 0.0).r * 0.0625;
        ray += textureSampleLevel(petal_rays, linear_sampler, at + vec2<f32>(r.x, -r.y), 0.0).r * 0.0625;
        ray += textureSampleLevel(petal_rays, linear_sampler, at + vec2<f32>(-r.x, r.y), 0.0).r * 0.0625;
        // The rays belong to whichever body casts the shadows: warm for the sun, pale blue for the moon,
        // and each time of day has its own strength and its own switch.
        let tint = mix(vec3<f32>(1.0, 0.86, 0.7), vec3<f32>(0.62, 0.74, 1.0), nightfall());
        let shape = (0.35 + 0.65 * light_low()) * light_up();
        let by_day = sun_rays * day * shape;
        let by_night = select(0.0, moon_rays_strength, moon_rays) * nightfall() * shape;
        c += tint * ray * max(by_day, by_night);
    }

    c *= exposure;

    // Lift the deepest black a hair: vanilla's night stays readable instead of crushing.
    c += vec3<f32>(0.006) * (1.0 - smoothstep(0.0, 0.4, luma(c)));

    // Night: a cool cast with the brightness kept, so nothing disappears into blue.
    c = mix(c, retint(c, vec3<f32>(0.82, 0.9, 1.12)), night * night_mood * 0.6);

    c = mix(vec3<f32>(luma(c)), c, saturation);

    // Contrast as a gentle S-curve, so mid-tones keep vanilla's value.
    let x = clamp(c, vec3<f32>(0.0), vec3<f32>(1.0));
    let curve = x * x * (3.0 - 2.0 * x);
    c = x + (curve - x) * (contrast - 1.0) * 2.5;

    if vignette > 0.0 {
        let aspect = frame.resolution.x / frame.resolution.y;
        let corner = length(vec2<f32>(aspect, 1.0) * 0.5);
        let d = length((input.uv - 0.5) * vec2<f32>(aspect, 1.0)) / corner;
        c *= 1.0 - smoothstep(0.55, 1.1, d) * vignette * 0.8;
    }

    // Proper dither: white noise, a new value every frame, about half a step of 8 bits. IGN was a
    // mistake here — it is a fixed diagonal pattern, and its amplitude is absolute, so in a dark
    // scene (grass at 0.05) the same 0.3 steps read as a 6% screen door over everything.
    let n = hash21(input.pixel);
    c += (n - 0.5) * (0.9 / 255.0);
    return vec4<f32>(clamp(c, vec3<f32>(0.0), vec3<f32>(1.0)), input.color.a);
}
