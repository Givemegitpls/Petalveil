// First glow pass, at a quarter of the world's size: only what is bright enough to glow.

override bloom: f32 = 0.35;

fn karis_weight(c: vec3<f32>) -> f32 {
    return 1.0 / (1.0 + luma(c));
}

fn post(input: PostInput) -> vec4<f32> {
    if bloom <= 0.0 {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    // Four taps, each weighted by a Karis average, so one bright texel does not become a fireball.
    let px = 1.0 / frame.resolution;
    var sum = vec3<f32>(0.0);
    var wsum = 0.0;
    for (var i = 0; i < 4; i++) {
        let o = vec2<f32>(f32(i & 1), f32(i >> 1)) * 2.0 - 1.0;
        let c = textureSampleLevel(previous, linear_sampler, input.uv + o * px * 0.5, 0.0).rgb;
        let w = karis_weight(c);
        sum += c * w;
        wsum += w;
    }
    let c = sum / max(wsum, 0.001);
    // Soft knee: nothing glows below 0.88, and what does glows in proportion.
    let bright = max(luma(c) - 0.88, 0.0);
    return vec4<f32>(c * bright * 1.6, 1.0);
}
