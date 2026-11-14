// Sun rays, at a quarter of the world's size: a march from each pixel toward the sun, letting light
// through where the world shows sky.

override sun_rays: f32 = 0.35;

// Where the sun is on screen: xy the UV, z 1 when it is in front of the camera.
fn sun_screen() -> vec3<f32> {
    let view = frame.view * vec4<f32>(frame.sun_direction, 0.0);
    let clip = frame.projection * view;
    if clip.w <= 0.0001 {
        return vec3<f32>(0.5, 0.5, 0.0);
    }
    let ndc = clip.xy / clip.w;
    let uv = ndc * vec2<f32>(0.5, -0.5) + vec2<f32>(0.5);
    let near = all(uv > vec2<f32>(-0.3)) && all(uv < vec2<f32>(1.3));
    return vec3<f32>(uv, select(0.0, 1.0, near));
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
    // A dithered start hides the steps of the march, so a dozen samples are enough.
    let jitter = ign(input.pixel);
    var sum = 0.0;
    for (var i = 0; i < 12; i++) {
        let t = (f32(i) + jitter) / 12.0;
        let uv = input.uv + toward_sun * t;
        // Only the sky lets the sun through; a block ends the ray.
        let sky = select(0.0, 1.0, depth_at(clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0))) <= 0.0);
        let falloff = 1.0 - t;
        sum += sky * falloff * falloff;
    }
    return vec4<f32>(vec3<f32>(sum / 12.0 * 2.2), 1.0);
}
