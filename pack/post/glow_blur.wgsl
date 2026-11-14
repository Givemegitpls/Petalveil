// Second glow pass: a small blur of the quarter-size glow, so it spreads as light does instead of
// as a box. Nine taps in two rings.

override bloom: f32 = 0.35;

fn post(input: PostInput) -> vec4<f32> {
    if bloom <= 0.0 {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    let texel = 1.0 / vec2<f32>(max(textureDimensions(petal_glow_a), vec2<u32>(1u, 1u)));
    let uv = input.uv;
    var sum = textureSampleLevel(petal_glow_a, linear_sampler, uv, 0.0).rgb * 0.25;
    // Ring one: the four neighbours.
    sum += textureSampleLevel(petal_glow_a, linear_sampler, uv + vec2<f32>(texel.x, 0.0) * 1.4, 0.0).rgb * 0.125;
    sum += textureSampleLevel(petal_glow_a, linear_sampler, uv - vec2<f32>(texel.x, 0.0) * 1.4, 0.0).rgb * 0.125;
    sum += textureSampleLevel(petal_glow_a, linear_sampler, uv + vec2<f32>(0.0, texel.y) * 1.4, 0.0).rgb * 0.125;
    sum += textureSampleLevel(petal_glow_a, linear_sampler, uv - vec2<f32>(0.0, texel.y) * 1.4, 0.0).rgb * 0.125;
    // Ring two: the four diagonals.
    let diag = vec2<f32>(texel.x, texel.y) * 1.9;
    sum += textureSampleLevel(petal_glow_a, linear_sampler, uv + diag, 0.0).rgb * 0.0625;
    sum += textureSampleLevel(petal_glow_a, linear_sampler, uv - diag, 0.0).rgb * 0.0625;
    sum += textureSampleLevel(petal_glow_a, linear_sampler, uv + vec2<f32>(diag.x, -diag.y), 0.0).rgb * 0.0625;
    sum += textureSampleLevel(petal_glow_a, linear_sampler, uv + vec2<f32>(-diag.x, diag.y), 0.0).rgb * 0.0625;
    return vec4<f32>(sum, 1.0);
}
