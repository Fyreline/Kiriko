// Hue shift (docs/08-EFFECTS.md §3.17). Mirrors lumit_core::fx::cpu::hue_shift
// op-for-op (§1.6: the CPU is the oracle): a row-major linear 3×3 colour
// matrix on RGB, alpha untouched. The matrix is computed host-side
// (lumit_core::fx::hue_matrix) so the CPU and this kernel multiply by
// identical coefficients. The nine coefficients are passed as individual f32
// fields, not a WGSL array/matrix, so their tight 4-byte packing matches the
// Rust `[f32; 9]` uniform exactly (a uniform array would stride at 16 bytes).

struct Params {
    m0: f32, m1: f32, m2: f32,
    m3: f32, m4: f32, m5: f32,
    m6: f32, m7: f32, m8: f32,
    mix_amt: f32,
    _pad0: f32,
    _pad1: f32,
};

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var orig: texture_2d<f32>;
@group(0) @binding(2) var dst: texture_storage_2d<rgba16float, write>;
@group(0) @binding(3) var<uniform> p: Params;

@compute @workgroup_size(8, 8)
fn hue_shift(@builtin(global_invocation_id) gid: vec3<u32>) {
    let size = vec2<i32>(textureDimensions(src));
    let xy = vec2<i32>(gid.xy);
    if (xy.x >= size.x || xy.y >= size.y) {
        return;
    }
    let o = textureLoad(src, xy, 0);
    let c = vec3<f32>(
        p.m0 * o.r + p.m1 * o.g + p.m2 * o.b,
        p.m3 * o.r + p.m4 * o.g + p.m5 * o.b,
        p.m6 * o.r + p.m7 * o.g + p.m8 * o.b,
    );
    let outv = o.rgb * (1.0 - p.mix_amt) + c * p.mix_amt;
    textureStore(dst, xy, vec4<f32>(outv, o.a));
}
