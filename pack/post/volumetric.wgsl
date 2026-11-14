// Optional volumetric fog: a march from the camera to whatever the depth buffer holds, lit by the
// sun through the shadow map, so a forest or a valley gets shafts of light. Half resolution, off by
// default; the pack's surfaces still keep vanilla's own fog either way.

override volumetric_fog: bool = false;
override fog_density: f32 = 0.35;
override fog_height: f32 = 24.0;
// Index into 8 and 16 steps.
override fog_steps: u32 = 0u;

// Cheap on purpose: eight steps at a quarter of the resolution is a sixteenth of the pixels, and
// the fog is low frequency, so the eye reads the shafts without them being traced honestly.
fn step_count() -> i32 {
    return select(8, 16, fog_steps == 1u);
}

fn post(input: PostInput) -> vec4<f32> {
    if !volumetric_fog || frame.dimension != 0 || frame.eye_in != 0u {
        return vec4<f32>(0.0, 0.0, 0.0, 0.0);
    }
    // Outdoors only: under a roof or in a cave the air stays as clear as vanilla's.
    let open = smoothstep(0.25, 0.7, frame.eye_light_smooth.y);
    if open <= 0.0 {
        return vec4<f32>(0.0, 0.0, 0.0, 0.0);
    }
    let depth = depth_at(input.uv);
    var reach = min(frame.far, 192.0);
    if depth > 0.0 {
        reach = min(reach, length(view_position(input.uv, depth)));
    }
    if reach <= 1.0 {
        return vec4<f32>(0.0, 0.0, 0.0, 0.0);
    }
    // A sky pixel has no point to aim at; its direction still comes from a far depth.
    let dir = normalize(view_position(input.uv, max(depth, 0.001)));

    let step = reach / f32(step_count());
    let jitter = ign(input.pixel);
    // Forward scattering: the air glows when the sun is behind it, which is what makes the shafts.
    let g = 0.4;
    let cos_t = dot(dir, frame.sun_direction);
    let phase = (1.0 - g * g) / (12.5663706 * pow(max(1.0 + g * g - 2.0 * g * cos_t, 0.001), 1.5));
    let sun = direct_color();
    let ambient = frame.sky_color * 0.10 + frame.fog_color * 0.06;
    let weather = 1.0 + 0.8 * frame.wetness + 1.4 * frame.thunder;

    var trans = 1.0;
    var scattered = vec3<f32>(0.0);
    for (var i = 0; i < step_count(); i++) {
        let t = (f32(i) + jitter) * step + step * 0.5;
        let p = dir * t;
        let world_y = p.y + frame.camera_position.y;
        // A layer that hugs the ground and thins out with height.
        let height = exp(-max(world_y - 58.0, 0.0) / max(fog_height, 2.0));
        let density = fog_density * 0.02 * height * weather;
        if density > 0.000001 {
            var lit = 1.0;
            if frame.has_shadow == 1u && length(p) < frame.shadow_distance {
                let s = shadow_position(p);
                if all(s.xy > vec2<f32>(0.0)) && all(s.xy < vec2<f32>(1.0)) && s.z < 1.0 {
                    lit = textureSampleCompareLevel(shadow_map, shadow_sampler, s.xy, s.z - frame.shadow_center_texel * 0.6);
                }
            }
            let light = sun * lit * phase * 2.5 + ambient;
            let absorbed = 1.0 - exp(-density * step);
            scattered += trans * absorbed * light * open;
            trans *= 1.0 - absorbed;
        }
        if trans < 0.03 {
            break;
        }
    }
    // The colour is premultiplied by its own coverage, so the composite can grade it in one mix.
    return vec4<f32>(scattered, 1.0 - trans);
}
