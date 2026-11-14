// The pack's own pixel sun, removed in 1.9.0 when stock sun came back.
// Options it used: sun, sun_style, sun_pixels, sun_scale, sun_canvas, sun_blur, sun_samples.
// Restore with `[sky] sun = false` and a `c += sun_disc(d);` in sky().

fn sun_canvas_size() -> f32 {
    switch sun_canvas {
        case 0u: {
            return 128.0;
        }
        case 2u: {
            return 512.0;
        }
        default: {
            return 256.0;
        }
    }
}

fn sun_tap_count() -> i32 {
    switch sun_samples {
        case 0u: {
            return 8;
        }
        case 1u: {
            return 16;
        }
        case 3u: {
            return 64;
        }
        default: {
            return 32;
        }
    }
}

fn sun_pixel_size() -> f32 {
    switch sun_pixels {
        case 0u: {
            return 8.0;
        }
        case 2u: {
            return 24.0;
        }
        case 3u: {
            return 32.0;
        }
        case 4u: {
            return 48.0;
        }
        default: {
            return 16.0;
        }
    }
}

// The sun's grid, drawn on whole screen pixels: `px` is the offset from the disc's centre in pixels,
// `cell` the side of one block in pixels (a whole number), so the blocks stay pixel-perfect however
// large the disc gets. 1 where the block's centre is inside the circle.
fn sun_cell(px: vec2<f32>, cell_px: f32, radius_px: f32) -> f32 {
    let index = floor(px / cell_px);
    let centre = (index + vec2<f32>(0.5)) * cell_px;
    return select(0.0, 1.0, dot(centre, centre) <= radius_px * radius_px);
}

// The sun drawn by hand: a circle of `sun_pixel_size()` cells across, each cell one flat square, so
// it reads as pixel art and not as a soft gradient. `Sun blur` is a blur of that little grid, not of
// the disc's rim: the cells are sampled with their neighbours at a radius measured in cells, so the
// block shape survives while its edges melt. Vanilla's sun is off (`[sky] sun = false`);
// vanilla's clouds still draw over this one.
fn sun_disc(d: vec3<f32>) -> vec3<f32> {
    let forward = frame.sun_direction;
    let facing = dot(d, forward);
    if facing <= 0.0 || forward.y < -0.02 {
        return vec3<f32>(0.0);
    }
    // Where the ray meets the sun's own plane, in the plane's units.
    let right = normalize(cross(forward, vec3<f32>(0.0, 1.0, 0.0)) + vec3<f32>(1e-5, 0.0, 0.0));
    let up = cross(right, forward);
    // The ray's place on the sun's plane, in units of vanilla's quad: |x| and |y| of 1 is its edge.
    let local = vec2<f32>(dot(d, right), dot(d, up)) / (facing * SUN_TANGENT);

    // Vanilla's own body is a square of that quad, and it is what the style switch draws: the engine's
    // sun is off in the manifest, so the pack has to paint it back when the player asks for it.
    if sun_style == 0u {
        let square = max(abs(local.x), abs(local.y));
        let edge = 1.0 - smoothstep(0.985, 1.0, square);
        if edge <= 0.0 {
            return vec3<f32>(0.0);
        }
        let up_amount = smoothstep(-0.02, 0.06, forward.y);
        let warm = mix(vec3<f32>(1.0, 0.55, 0.26), vec3<f32>(1.0, 0.97, 0.9), smoothstep(0.0, 0.3, forward.y));
        return warm * 1.1 * up_amount * edge;
    }

    let q = local / max(sun_scale, 0.05);
    // The sun is rasterised on its own canvas of a fixed size (128, 256 or 512 pixels across), with
    // room inside for the blur; the canvas is then stretched onto its place in the sky. So the blocks
    // and the blur are measured in canvas pixels and do not change with the render resolution.
    let canvas = sun_canvas_size();
    let blur_px = clamp(sun_blur, 0.0, canvas * 0.3);
    let radius_px = max(canvas * 0.5 - blur_px, 1.0);
    let cell_px = max(floor(radius_px * 2.0 / sun_pixel_size()), 1.0);
    let px = q * radius_px;
    // A Vogel spiral of thirty-two taps: a cross of nine only gives nine grey levels, which is exactly
    // the staircase the player sees. With this many the block silhouette survives and its edge fades.
    var edge = 0.0;
    if blur_px <= 0.0 {
        edge = sun_cell(px, cell_px, radius_px);
    } else {
        // A stable per-pixel rotation, so the spiral itself does not leave a pattern.
        let seed = hash21(floor(px / 3.0)) * 6.2831853;
        let taps = sun_tap_count();
        for (var i = 0; i < taps; i++) {
            let angle = f32(i) * 2.39996323 + seed;
            let r = sqrt((f32(i) + 0.5) / f32(taps)) * blur_px;
            edge += sun_cell(px + vec2<f32>(cos(angle), sin(angle)) * r, cell_px, radius_px);
        }
        edge /= f32(taps);
    }
    // When the radius dwarfs a cell the silhouette stops meaning anything, and the exact profile of a
    // blurred disc takes over.
    let ratio = blur_px / max(cell_px, 1.0);
    if ratio > 3.0 {
        let blurred = 1.0 - smoothstep(radius_px - blur_px, radius_px + blur_px, length(px));
        edge = mix(edge, blurred, clamp((ratio - 3.0) / 2.0, 0.0, 1.0));
    }
    if edge <= 0.0 {
        return vec3<f32>(0.0);
    }
    let up_amount = smoothstep(-0.02, 0.06, forward.y);
    let warm = mix(vec3<f32>(1.0, 0.55, 0.26), vec3<f32>(1.0, 0.97, 0.9), smoothstep(0.0, 0.3, forward.y));
    return warm * 1.1 * up_amount * edge;
}

