// The terrain's colour: vanilla everywhere the pack has nothing to say, which is every dimension
// but the Overworld, and every surface that is not water.

fn material(input: MaterialInput) -> Surface {
    // The Nether and the End keep vanilla's look exactly.
    if frame.dimension != 0 {
        return Surface(input.albedo * input.tint * vec4<f32>(input.lightmap, 1.0));
    }
    // Lava and anything else that is not water: vanilla's own emissive look.
    if input.fluid == 2u {
        return Surface(vec4<f32>(input.albedo.rgb * input.tint.rgb, input.albedo.a * input.tint.a));
    }
    if input.fluid == 1u {
        return Surface(water_surface(input));
    }
    return Surface(lit_terrain(input));
}
