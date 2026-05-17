# Metal Shading Language port plan

_Audit MEDIUM #25. Owner: Thierry. Status: **plan only** — actual port
deferred until either Apple announces a deprecation timeline for
`CIColorKernel(source:)` or one of the three kernels needs functional
changes anyway._

## Why this is on the list

`CIColorKernel(source:)` is marked "deprecated since macOS 10.14" in
the SDK headers. We currently silence the warning via
`GCC_PREPROCESSOR_DEFINITIONS: CI_SILENCE_GL_DEPRECATION=1` in
`project.yml`. Apple has shipped the API on every macOS since, including
macOS 26.4 (the current ship target). The deprecation is real but
nothing forces a port today.

The right time to do this work is:

- **When Apple announces removal** (typically signalled at the
  preceding WWDC); or
- **When one of the three kernels needs a functional change** so the
  port cost is amortised into work we'd do anyway; or
- **When we add a fourth kernel** — three is the threshold where the
  CI-vs-Metal interop pattern starts to dominate the boilerplate.

If none of those happens, the plan below is fine as a sleeping doc.

## What needs porting

Three custom GLSL kernels in
[`Avatar/Services/ImageProcessor.swift`](../../Avatar/Services/ImageProcessor.swift):

| # | Constant | Purpose | LOC of GLSL |
|---|---|---|---|
| 1 | `blurFusionKernel` | Blends a sharp foreground with a blurred backdrop on the alpha boundary | ~15 |
| 2 | `computeBlurredBKernel` | Derives a soft mask from the cutout's alpha for the fusion step | ~10 |
| 3 | `colorAttenuationKernel` | Pulls saturation down on edge halos that DeOldify leaves around the silhouette | ~22 |

All three operate per-pixel on RGBA, no neighbourhoods, no LUTs. They
fit MSL's `kernel` function signature 1:1.

## Target architecture

```
Avatar/Shaders/MattingKernels.metal          ← three MSL kernel functions
build/metal-compile.sh                        ← xcrun metal + metallib step
Avatar/Resources/MattingKernels.metallib      ← bundled output (~few KB)
Avatar/Services/ImageProcessor.swift          ← swap GLSL strings for metallib-loaded kernels
```

The Swift side becomes:

```swift
private static let mattingLibrary: CIMetalLibrary? = {
    guard let url = Bundle.main.url(forResource: "MattingKernels", withExtension: "metallib") else { return nil }
    return try? CIMetalLibrary(contentsOf: url)
}()

private static let blurFusionKernel: CIColorKernel? = {
    guard let lib = mattingLibrary else { return nil }
    return try? CIColorKernel(metalLibrary: lib, functionName: "blurFusion")
}()
```

`CIColorKernel(metalLibrary:functionName:)` is the modern, non-deprecated
counterpart that has been around since macOS 10.14 itself; we're just
swapping the source-string overload for the library overload.

## Port steps (when the time comes)

1. **Create `Avatar/Shaders/MattingKernels.metal`** and translate each
   GLSL kernel into MSL. The translation is mostly mechanical:
   - `float4 sample = ...` → `float4 sample = src.sample(samp, coord)`
   - GLSL built-ins (`mix`, `step`, `smoothstep`) exist in MSL with
     identical signatures.
   - GLSL coordinate system origin is bottom-left, CoreImage's MSL
     wrapper is top-left — read the [`CIKernel` MSL docs](https://developer.apple.com/documentation/coreimage/writing_custom_kernels)
     before flipping any V coordinate.
2. **Add a build phase** in `project.yml`:
   ```yaml
   preBuildScripts:
     - name: "Compile matting Metal kernels"
       script: |
         "$SRCROOT/scripts/build-metallib.sh"
       inputFiles:
         - "$(SRCROOT)/Avatar/Shaders/MattingKernels.metal"
       outputFiles:
         - "$(BUILT_PRODUCTS_DIR)/$(PRODUCT_NAME).app/Contents/Resources/MattingKernels.metallib"
   ```
3. **Write `scripts/build-metallib.sh`** that runs
   `xcrun -sdk macosx metal -c $SRC -o $AIR && xcrun -sdk macosx metallib $AIR -o $METALLIB`
   with `-ffast-math` and `-fcikernel` flags (the second one is
   non-negotiable for kernels that go through CoreImage).
4. **Replace the three Swift constants** to load from the metallib
   (snippet above).
5. **Drop the silencing define**:
   `GCC_PREPROCESSOR_DEFINITIONS: CI_SILENCE_GL_DEPRECATION=1`
   in `project.yml` — once the GLSL strings are gone, the deprecation
   warnings stop on their own.
6. **Smoke test**: run the edge benchmark from the existing Debug menu
   (`scripts/dmg-assets/...`); compare A/B against the pre-port DMG.
   Differences should be at most a few LSBs (floating-point reorder).
7. **Ship in a minor release**. Tag the release notes as "Internal
   shader rewrite, no user-facing change."

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Coordinate-system flip producing inverted alpha | High on first attempt | Side-by-side A/B with edge benchmark before merging |
| Build host missing `metal` toolchain (older Xcode) | Low | `xcrun -find metal` check in the build script; fail loud |
| Performance regression vs JIT-compiled GLSL | Very low | MSL is AOT-compiled — usually faster, never observably slower for kernels this short |
| Metal shader cache vs JIT bug interaction | Low | Test against the existing Compositor benchmark before/after |

## When to revisit this plan

- macOS 27 betas dropping support for `CIColorKernel(source:)` → port within the beta window.
- We add a fourth kernel → port all four together.
- A user reports the edge-fusion looking wrong on Apple Silicon → port and re-A/B as part of the fix.

If none of the above happens within 12 months of this doc's date
(2026-05-18), the next annual review of `docs/security/policy.md`
should re-read the deprecation status and decide whether the plan is
still right.
