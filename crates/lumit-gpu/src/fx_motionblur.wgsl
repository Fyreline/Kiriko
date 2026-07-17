// Flow motion blur (docs/08-EFFECTS.md §3.2): smear each pixel along its own
// motion vector. Mirrors lumit_core::fx::cpu::motion_blur op-for-op (§1.6: the
// CPU is the oracle) — the same tap count, the same evenly spaced bilinear
// taps in the same order, box weighted and normalised, edges clamped.
//
// The motion is a dense flow field (per-pixel forward vectors, in raster
// pixels) the decode worker computed between the current source frame and the
// next (§3.1). It arrives as a two-channel texture the same size as the input;
// binding 2 samples it. binding 0 is the source (the taps sample it), binding
// 1 the same texture read as the unprocessed original for the host Mix — the
// shared 2-input convention, with the flow texture the one extra binding
// (modelled on fx_adjust.wgsl's third input).

struct Params {
    shutter_frac: f32, // shutter / 360: streak length as a fraction of motion
    samples: i32,      // taps along the streak (== cpu::motion_blur's samples)
    mix_amt: f32,      // 0..1, blended against the unprocessed input
    _pad0: f32,
};

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var orig: texture_2d<f32>;
@group(0) @binding(2) var flow: texture_2d<f32>;
@group(0) @binding(3) var dst: texture_storage_2d<rgba16float, write>;
@group(0) @binding(4) var<uniform> p: Params;

// Clamp-addressed bilinear at continuous pixel-centre coordinates (== the
// cpu::bilinear rule the reference uses, same arithmetic order): the texel at
// index x covers [x, x+1), centre x+0.5; out-of-frame taps read the edge.
fn bilinear_clamp(sx: f32, sy: f32, size: vec2<i32>) -> vec4<f32> {
    let fx = sx - 0.5;
    let fy = sy - 0.5;
    let x0 = floor(fx);
    let y0 = floor(fy);
    let tx = fx - x0;
    let ty = fy - y0;
    let x0i = i32(x0);
    let y0i = i32(y0);
    let c00 = textureLoad(src, vec2<i32>(clamp(x0i, 0, size.x - 1), clamp(y0i, 0, size.y - 1)), 0);
    let c10 = textureLoad(src, vec2<i32>(clamp(x0i + 1, 0, size.x - 1), clamp(y0i, 0, size.y - 1)), 0);
    let c01 = textureLoad(src, vec2<i32>(clamp(x0i, 0, size.x - 1), clamp(y0i + 1, 0, size.y - 1)), 0);
    let c11 = textureLoad(src, vec2<i32>(clamp(x0i + 1, 0, size.x - 1), clamp(y0i + 1, 0, size.y - 1)), 0);
    let top = c00 * (1.0 - tx) + c10 * tx;
    let bottom = c01 * (1.0 - tx) + c11 * tx;
    return top * (1.0 - ty) + bottom * ty;
}

@compute @workgroup_size(8, 8)
fn motion_blur(@builtin(global_invocation_id) gid: vec3<u32>) {
    let size = vec2<i32>(textureDimensions(src));
    let xy = vec2<i32>(gid.xy);
    if (xy.x >= size.x || xy.y >= size.y) {
        return;
    }
    let pos = vec2<f32>(xy) + vec2<f32>(0.5);
    // This pixel's inter-frame motion, shortened by the shutter fraction —
    // the full streak vector; taps span it centred on the pixel.
    let sv = textureLoad(flow, xy, 0).xy * p.shutter_frac;
    let n = p.samples;
    let nf = f32(n);
    var acc = vec4<f32>(0.0);
    for (var k = 0; k < n; k++) {
        let t = (f32(k) + 0.5) / nf - 0.5;
        acc += bilinear_clamp(pos.x + t * sv.x, pos.y + t * sv.y, size);
    }
    let o = textureLoad(orig, xy, 0);
    let v = acc / nf;
    textureStore(dst, xy, mix(o, v, p.mix_amt));
}
