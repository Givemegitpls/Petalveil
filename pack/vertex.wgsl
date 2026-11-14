// Where each corner of a block's surface is drawn: waves on the water and wind on leaves and plants.
// It runs in the world and in the shadow pass, so a leaf's shadow moves with the leaf.

override waving: bool = true;
override wave_strength: f32 = 1.0;

// A gust travelling across the world, with a faster flutter on top of it.
fn wind_offset(world: vec3<f32>, t: f32, storm: f32) -> vec3<f32> {
    let angle = 0.6 + 0.25 * sin(t * 0.05);
    let dir = vec2<f32>(cos(angle), sin(angle));
    let gust = 0.55 + 0.45 * sin(dot(world.xz, dir) * 0.12 - t * (0.45 + 0.8 * storm));
    let phase = world.x * 1.31 + world.z * 0.87;
    let flutter = 0.6 * sin(t * (2.4 + 1.6 * storm) + phase) + 0.4 * sin(t * 4.1 + phase * 1.7);
    let along = gust + 0.3 * flutter;
    let across = 0.35 * flutter;
    return vec3<f32>(dir.x * along - dir.y * across, 0.0, dir.y * along + dir.x * across) * (1.0 + 1.4 * storm);
}

fn vertex(input: VertexInput) -> vec3<f32> {
    var p = input.position;
    let world = p + frame.camera_position;
    let t = frame.time;
    let storm = storm_amount();

    if input.fluid == 1u {
        // Only the corners above the block's floor move, so water never opens a gap against what
        // lies under it.
        if water_waves && fract(world.y) > 0.02 {
            p.y -= (1.0 - wave_field(world.xz, t, storm)) * (0.05 + 0.08 * storm);
        }
        return p;
    }

    if !waving || wave_strength <= 0.0 || input.material == 0u || input.material > MAT_VINE {
        return p;
    }

    // A plant under a roof, in a cave or in a pot hardly moves; one in the open sways fully.
    let exposed = smoothstep(0.28, 0.88, input.light.y);
    let w = wind_offset(world, t, storm) * wave_strength * exposed;
    // uv.y is 0 at the top of the sprite and 1 at its foot, so `top` is 1 at the tip.
    let top = 1.0 - input.uv.y;
    switch input.material {
        case MAT_LEAVES: {
            p += w * 0.03 + vec3<f32>(0.0, w.x * 0.012, 0.0);
        }
        case MAT_PLANT: {
            p += w * (0.1 * top);
        }
        case MAT_TALL_LOWER: {
            p += w * (0.05 * top);
        }
        case MAT_TALL_UPPER: {
            p += w * (0.05 + 0.06 * top);
        }
        default: {
            p += w * 0.02;
        }
    }
    return p;
}
