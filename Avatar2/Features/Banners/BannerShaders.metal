// E38.1 — Procedurale banner-shaders (Figma-stijl), als SwiftUI `Shader`-API.
// Elke functie is `[[stitchable]]` zodat SwiftUI 'm via `.colorEffect`
// (per-pixel kleur), `.distortionEffect` (positie-warp) of `.layerEffect` kan
// toepassen. Lokaal/gratis/realtime op de GPU — géén cloud, géén assets; de
// gecompileerde library is enkele KB's in de app-bundle. Param-bereiken/-labels
// leven in `ShaderEffect.swift` (de catalogus); de arg-VOLGORDE hier moet exact
// matchen met `ShaderEffect.args`.
//
// Conventies: color-effects krijgen (position, color, <args>); distortion-effects
// krijgen (position, <args>) en geven de bron-positie terug om te samplen.
// `bounds` (float4 = x,y,w,h) komt van SwiftUI's `.boundingRect` zodat patronen/
// warps schaal-relatief zijn (zelfde resultaat op preview én export).

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

namespace {

// Goedkope hash → pseudo-random 0…1.
float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// Value-noise met smoothstep-interpolatie.
float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Fractal brownian motion (5 octaves) — wolkachtige fractal noise.
float fbm(float2 p) {
    float v = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 5; i++) {
        v += amp * valueNoise(p);
        p *= 2.0;
        amp *= 0.5;
    }
    return v;
}

// 4×4 ordered Bayer-drempel (0…1).
float bayer4(int2 c) {
    const float m[16] = {
         0.0/16.0,  8.0/16.0,  2.0/16.0, 10.0/16.0,
        12.0/16.0,  4.0/16.0, 14.0/16.0,  6.0/16.0,
         3.0/16.0, 11.0/16.0,  1.0/16.0,  9.0/16.0,
        15.0/16.0,  7.0/16.0, 13.0/16.0,  5.0/16.0
    };
    int idx = (c.y & 3) * 4 + (c.x & 3);
    return m[idx];
}

float luma(half3 rgb) {
    return dot(float3(rgb), float3(0.299, 0.587, 0.114));
}

} // namespace

// MARK: - Color-effects (bewerken de bestaande pixels)

// Filmkorrel: monochrome ruis bovenop de kleur.
[[stitchable]] half4 bannerGrain(float2 pos, half4 color, float intensity) {
    float n = hash21(pos) - 0.5;
    half3 rgb = clamp(color.rgb + half3(half(n * intensity)), 0.0h, 1.0h);
    return half4(rgb, color.a);
}

// Fractal-noise-overlay: blend fBm-grijs over de kleur (textuur/nevel).
[[stitchable]] half4 bannerNoiseOverlay(float2 pos, half4 color, float4 bounds, float scale, float intensity) {
    float2 uv = (pos - bounds.xy) / max(bounds.zw, float2(1.0));
    float n = fbm(uv * scale);
    half3 rgb = mix(color.rgb, half3(half(n)), half(intensity));
    return half4(rgb, color.a);
}

// Ordered dithering: kwantiseer met een Bayer-drempel (retro/print-look).
[[stitchable]] half4 bannerDither(float2 pos, half4 color, float levels) {
    float L = max(levels, 2.0);
    float t = bayer4(int2(pos)) - 0.5;
    half3 rgb = color.rgb + half(t / L);
    rgb = floor(rgb * half(L) + 0.5h) / half(L);
    return half4(clamp(rgb, 0.0h, 1.0h), color.a);
}

// Halftone: zwarte stippen op wit, dichtheid ~ helderheid (krant-look).
// 37.19 (audit-B6): `intensity` blendt het stippenpatroon over de bronkleur —
// 0 = bron ongemoeid, 1 = puur zwart/wit. Zonder blend gooide de kernel de
// gradient/fill volledig weg en werd tekst onleesbaar (wit banner met stippen).
[[stitchable]] half4 bannerHalftone(float2 pos, half4 color, float scale, float intensity) {
    float s = max(scale, 2.0);
    float2 g = fract(pos / s) - 0.5;
    float radius = sqrt(max(0.0, 1.0 - luma(color.rgb))) * 0.5;
    half ink = length(g) < radius ? 1.0h : 0.0h;
    half3 halftone = mix(half3(1.0h), half3(0.0h), ink);
    half t = half(clamp(intensity, 0.0, 1.0));
    half3 rgb = mix(color.rgb, halftone, t);
    return half4(rgb, color.a);
}

// MARK: - Distortion-effects (verplaatsen de sample-positie)

// Lens (barrel/pincushion): radiale vervorming vanuit het midden.
[[stitchable]] float2 bannerLens(float2 pos, float4 bounds, float strength) {
    float2 size = max(bounds.zw, float2(1.0));
    float2 c = bounds.xy + size * 0.5;
    float2 d = pos - c;
    float r = length(d / (size * 0.5));
    float f = 1.0 + strength * (r * r);
    return c + d * f;
}

// Warp: sinusvormige verplaatsing (golvend), schaal-relatief via bounds.
[[stitchable]] float2 bannerWarp(float2 pos, float4 bounds, float amplitude, float frequency) {
    float2 uv = (pos - bounds.xy) / max(bounds.zw, float2(1.0));
    float dx = sin(uv.y * frequency * 6.28318) * amplitude;
    float dy = cos(uv.x * frequency * 6.28318) * amplitude;
    return pos + float2(dx, dy);
}
