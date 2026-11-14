// Sun rays, at a quarter of the world's size: a march from each pixel toward the sun, letting light
// through where the world shows sky. The sun does not have to be on screen: the shafts still cross
// the picture, and only the samples that fall inside it count.

override sun_rays: f32 = 0.5;

// Where the sun is: xy its UV (may be far outside 0..1), z 1 when it is in front of the camera.
fn sun_screen() -> vec3<f32> {
    let view = frame.view * vec4<f32>(frame.light_direction, 0.0);
    let clip = frame.projection * view;
    if clip.w <= 0.0001 {
        return vec3<f32>(0.5, 0.5, 0.0);
    }
    let ndc = clip.xy / clip.w;
    let uv = ndc * vec2<f32>(0.5, -0.5) + vec2<f32>(0.5);
    // A sun almost beside the camera has no usable screen direction; anything short of that is fine.
    let sane = all(uv > vec2<f32>(-3.0)) && all(uv < vec2<f32>(4.0));
    return vec3<f32>(uv, select(0.0, 1.0, sane));
}

fn post(input: PostInput) -> vec4<f32> {
    if sun_rays <= 0.0 {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    let sun = sun_screen();
    if sun.z < 1.0 {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    let toward_sun = sun.xy - input.uv;
    // A per-pixel start breaks the march's own rings and spokes into noise; the composite then blurs
    // this target, which averages the noise away and leaves a smooth gradient. Noise without the blur
    // reads as grain, a fixed start without the noise reads as spokes — this pass needs both halves.
    let jitter = ign(input.pixel);
    var sum = 0.0;
    for (var i = 0; i < 24; i++) {
        let t = (f32(i) + jitter) / 24.0;
        let uv = input.uv + toward_sun * t;
        // A sample outside the picture says nothing about the air; it is skipped, not clamped, so a
        // sun beyond the frame does not smear the border over the scene.
        if any(uv <= vec2<f32>(0.0)) || any(uv >= vec2<f32>(1.0)) {
            continue;
        }
        // Only the sky lets the sun through: ground, clouds and the water all end the ray, which is
        // what turns the gaps between them into shafts.
        let sky = select(0.0, 1.0, depth_at(uv) <= 0.0);
        let falloff = 1.0 - t;
        sum += sky * falloff * falloff;
    }
    return vec4<f32>(vec3<f32>(sum / 24.0 * 2.6), 1.0);
}
