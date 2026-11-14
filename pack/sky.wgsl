// The sky: vanilla's own colour with a pastel veil, the pack's own soft sun and the rainbow after
// rain. Vanilla's clouds are kept, because they are geometry in the world: they hide the sun, they
// move against the ground when you walk, and no sky-stage picture can do that.

override sky_pastel: f32 = 0.7;
override rainbow: bool = true;
override night_mood: f32 = 0.35;

fn hue_rgb(h: f32) -> vec3<f32> {
    let r = abs(h * 6.0 - 3.0) - 1.0;
    let g = 2.0 - abs(h * 6.0 - 2.0);
    let b = 2.0 - abs(h * 6.0 - 4.0);
    return clamp(vec3<f32>(r, g, b), vec3<f32>(0.0), vec3<f32>(1.0));
}

// Vanilla's sun quad is ±30 at a distance of 100 (`celestial_geometry`); `Sun size` multiplies the
// tangent of that, and the disc is quantised onto a grid, which makes the rim stair-step like pixel
// art. What the game actually shows is far smaller than the quad's 33 degrees, so the default is a
// quarter of it, about 8 degrees.
const SUN_TANGENT: f32 = 0.3;

fn sky(input: SkyInput) -> vec4<f32> {
    let d = input.direction;
    var c = input.color.rgb;
    let day = daylight();
    let night = nightfall();
    let low = sun_low();
    let toward = max(dot(d, frame.sun_direction), 0.0);

    // Pastel veil, lilac away from the sun and peach toward it. It is strongest a little above the
    // horizon and softens to nothing at it, so the sky still meets vanilla's fog colour without a
    // seam; a hard edge there reads as the sky sliding under the camera when you walk.
    let band = 1.0 - smoothstep(0.05, 0.55, abs(d.y));
    let peach = vec3<f32>(1.0, 0.82, 0.7);
    let lilac = vec3<f32>(0.93, 0.84, 1.0);
    let veil = mix(lilac, peach, clamp(pow(toward, 1.5) * 0.75 + low * 0.35, 0.0, 1.0));
    let veil_amount = band * (0.16 + 0.3 * low) * sky_pastel * day * (1.0 - 0.4 * frame.wetness);
    c = mix(c, retint(c, veil), veil_amount);
    c += peach * pow(toward, 10.0) * 0.08 * low * day * sky_pastel;

    // Rain washes the sky toward its own grey, as vanilla does, but a little softer.
    c = mix(c, vec3<f32>(luma(c)) * vec3<f32>(0.9, 0.95, 1.02), frame.wetness * 0.55);
    c *= 1.0 - frame.thunder * 0.3;

    // Night: a cooler sky with the brightness kept, so the night stays readable.
    c = mix(c, retint(c, vec3<f32>(0.8, 0.88, 1.14)), night * night_mood * 0.8);
    c = mix(c, c + vec3<f32>(0.004, 0.008, 0.018), night * night_mood);


    // A rainbow opposite the sun while the rain dries: the primary bow, red outside, violet in.
    if rainbow && frame.wetness > 0.05 && frame.sun_direction.y > -0.02 {
        let deg = degrees(acos(clamp(dot(d, -frame.sun_direction), -1.0, 1.0)));
        let bow_band = smoothstep(39.4, 40.6, deg) * (1.0 - smoothstep(42.2, 43.4, deg));
        if bow_band > 0.0 {
            let h = clamp((deg - 40.0) / 2.6, 0.0, 1.0);
            let bow = hue_rgb(mix(0.78, 0.0, h));
            c += bow * bow_band * frame.wetness * daylight() * 0.3;
        }
    }

    return vec4<f32>(clamp(c, vec3<f32>(0.0), vec3<f32>(1.0)), 1.0);
}
