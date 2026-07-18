// Depth-of-field lens blur (foundation for docs/08-EFFECTS.md's planned DoF
// effects). A variable-radius "scatter-as-gather" blur: each output pixel's
// circle-of-confusion radius comes from how far its depth is from the focus
// plane, and it averages a disc of that radius from the source. Mirrors the
// CPU reference tap-for-tap (§1.6: the CPU is the oracle) — the same CoC
// maths, the same integer disc taps in the same row-major order, box
// weighted and normalised, edges clamped.
//
// The per-pixel depth is a single-channel field (R32Float, exact f32, same
// size as the input) the caller supplies — for now a synthetic/stand-in map,
// since a real depth layer input is a separate, larger change (see the impl
// notes and report). binding 0 is the source (the taps sample it), binding 1
// the unprocessed original read back for the host Mix, binding 2 the depth
// field — the shared three-sampled-input shape it borrows from Motion blur,
// with the depth texture the one extra binding over the two-input convention.

struct Params {
    focus: f32,     // in-focus depth in [0,1]
    range: f32,     // half-width of the sharp band, [0,1]
    aperture: f32,  // max circle-of-confusion radius, raster px
    mix_amt: f32,   // 0..1, blended against the unprocessed input
};

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var orig: texture_2d<f32>;
@group(0) @binding(2) var depth: texture_2d<f32>;
@group(0) @binding(3) var dst: texture_storage_2d<rgba16float, write>;
@group(0) @binding(4) var<uniform> p: Params;

// Circle-of-confusion radius (raster px) for a depth sample. Zero inside the
// sharp band |depth-focus| <= range, then ramps smoothstep to `aperture` as
// the depth distance reaches the far extreme (1.0). Written with explicit
// min/max/mul/sub — NOT the built-in smoothstep, whose exact form is not
// guaranteed to match the CPU — so the oracle reproduces it bit-for-bit.
fn coc_radius(d: f32) -> f32 {
    let dist = abs(d - p.focus);
    let denom = max(1.0 - p.range, 1e-4);
    let e = min(max((dist - p.range) / denom, 0.0), 1.0);
    let s = e * e * (3.0 - 2.0 * e); // smoothstep ramp
    return p.aperture * s;
}

@compute @workgroup_size(8, 8)
fn dof(@builtin(global_invocation_id) gid: vec3<u32>) {
    let size = vec2<i32>(textureDimensions(src));
    let xy = vec2<i32>(gid.xy);
    if (xy.x >= size.x || xy.y >= size.y) {
        return;
    }
    let d = textureLoad(depth, xy, 0).x;
    let coc = coc_radius(d);
    let coc2 = coc * coc;
    // Integer disc radius: every tap whose squared pixel distance is within
    // coc² is included, box weighted. The centre (r²=0 <= coc²>=0) is always
    // in, so the running weight is never zero.
    let ri = i32(ceil(coc));
    var acc = vec4<f32>(0.0);
    var wsum = 0.0;
    for (var dy = -ri; dy <= ri; dy++) {
        for (var dx = -ri; dx <= ri; dx++) {
            let r2 = f32(dx * dx + dy * dy);
            if (r2 <= coc2) {
                let sx = clamp(xy.x + dx, 0, size.x - 1);
                let sy = clamp(xy.y + dy, 0, size.y - 1);
                acc += textureLoad(src, vec2<i32>(sx, sy), 0);
                wsum += 1.0;
            }
        }
    }
    let v = acc / wsum;
    let o = textureLoad(orig, xy, 0);
    textureStore(dst, xy, mix(o, v, p.mix_amt));
}
