// E38.1 — ShaderEffect-model + catalogus + SwiftUI-haak voor de banner-shaders.
// Beschrijft elke procedurale shader (uit `BannerShaders.metal`) als een
// value-type: een stabiele `key`, een `displayName`, het Metal-`functionName`,
// hoe 'm toe te passen (`stage`: color of distortion) en een geordende arg-spec
// (`args`) die 1-op-1 matcht met de Metal-signatuur. De slider-params worden uit
// `args` afgeleid. Persistente staat per banner leeft in `BannerShaderLayer`
// (E37.1: key + [param:waarde] + enabled); de catalogus levert defaults/bereiken.
//
// `View.bannerShaders(_:bounds:)` stapelt de ingeschakelde lagen in volgorde op
// een view via de juiste `.colorEffect`/`.distortionEffect` — live op de
// Studio-canvas (E38.2) en mee-gerasterd bij export via `ImageRenderer`.

import SwiftUI

/// Eén instelbare shader-parameter (slider). `key` matcht de sleutel in
/// `BannerShaderLayer.params`.
struct ShaderParam: Identifiable, Equatable, Sendable {
    let key: String
    let label: String
    let range: ClosedRange<Double>
    let defaultValue: Double
    var id: String { key }
}

/// Eén argument van de Metal-functie, in signatuur-volgorde. `.bounds` levert
/// SwiftUI's `.boundingRect` (float4); `.param` is een instelbare slider-waarde.
enum ShaderArg: Equatable, Sendable {
    case bounds
    case param(ShaderParam)
}

/// Eén procedurale shader uit de catalogus.
struct ShaderEffect: Identifiable, Equatable, Sendable {
    /// Hoe SwiftUI 'm toepast.
    enum Stage: Equatable, Sendable { case color, distortion }

    let key: String
    let displayName: String
    let functionName: String
    let stage: Stage
    let args: [ShaderArg]

    var id: String { key }

    /// De instelbare params (afgeleid uit de arg-spec), voor de panel-UI.
    var params: [ShaderParam] {
        args.compactMap { if case let .param(p) = $0 { return p } else { return nil } }
    }

    /// Default-laag voor deze shader (alle params op hun default).
    func makeLayer() -> BannerShaderLayer {
        var values: [String: Double] = [:]
        for p in params { values[p.key] = p.defaultValue }
        return BannerShaderLayer(key: key, params: values, enabled: true)
    }
}

/// De ingebouwde shader-catalogus (Figma-stijl). Lokaal; CMS-presets kunnen later
/// `params` voorvullen (spiegelt RemoteEffect) maar de shader-math blijft hier.
enum ShaderCatalog {
    static let all: [ShaderEffect] = [
        ShaderEffect(key: "grain", displayName: "Grain", functionName: "bannerGrain", stage: .color, args: [
            .param(ShaderParam(key: "intensity", label: "Amount", range: 0...1, defaultValue: 0.25)),
        ]),
        ShaderEffect(key: "noise", displayName: "Fractal noise", functionName: "bannerNoiseOverlay", stage: .color, args: [
            .bounds,
            .param(ShaderParam(key: "scale", label: "Scale", range: 1...60, defaultValue: 18)),
            .param(ShaderParam(key: "intensity", label: "Amount", range: 0...1, defaultValue: 0.35)),
        ]),
        ShaderEffect(key: "dither", displayName: "Dither", functionName: "bannerDither", stage: .color, args: [
            .param(ShaderParam(key: "levels", label: "Levels", range: 2...16, defaultValue: 4)),
        ]),
        // 37.19: `intensity` (arg-volgorde = Metal-signatuur: scale, intensity)
        // blendt de stippen over de bron; default 0.6 laat achtergrond/tekst
        // herkenbaar. Oudere lagen zonder de key vallen terug op de default.
        ShaderEffect(key: "halftone", displayName: "Halftone", functionName: "bannerHalftone", stage: .color, args: [
            .param(ShaderParam(key: "scale", label: "Dot size", range: 4...40, defaultValue: 12)),
            .param(ShaderParam(key: "intensity", label: "Amount", range: 0...1, defaultValue: 0.6)),
        ]),
        ShaderEffect(key: "lens", displayName: "Lens", functionName: "bannerLens", stage: .distortion, args: [
            .bounds,
            .param(ShaderParam(key: "strength", label: "Strength", range: -0.6...0.6, defaultValue: 0.2)),
        ]),
        ShaderEffect(key: "warp", displayName: "Warp", functionName: "bannerWarp", stage: .distortion, args: [
            .bounds,
            .param(ShaderParam(key: "amplitude", label: "Amount", range: 0...40, defaultValue: 12)),
            .param(ShaderParam(key: "frequency", label: "Frequency", range: 1...30, defaultValue: 8)),
        ]),
    ]

    static func effect(for key: String) -> ShaderEffect? { all.first { $0.key == key } }

    /// Grootste sample-offset (punten) die een distortion kan vergen — voedt
    /// `.distortionEffect(maxSampleOffset:)` zodat randpixels niet wegvallen.
    static let maxSampleOffset = CGSize(width: 80, height: 80)
}

extension ShaderEffect {
    /// Bouwt de SwiftUI `Shader` met de waarden uit een laag (val terug op
    /// defaults voor ontbrekende params). Arg-volgorde = `args`-volgorde.
    func shader(values: [String: Double]) -> Shader {
        let fn = ShaderFunction(library: .default, name: functionName)
        let arguments: [Shader.Argument] = args.map { arg in
            switch arg {
            case .bounds:
                return .boundingRect
            case let .param(p):
                return .float(Float(values[p.key] ?? p.defaultValue))
            }
        }
        return Shader(function: fn, arguments: arguments)
    }
}

extension View {
    /// Stapelt de ingeschakelde shader-lagen (in volgorde) op deze view via de
    /// juiste SwiftUI-shader-modifier. macOS 14+ (Shader-API); op de
    /// app-deploymenttarget (14.0) altijd beschikbaar.
    @ViewBuilder
    func bannerShaders(_ layers: [BannerShaderLayer]) -> some View {
        let active = layers.filter(\.enabled)
        if active.isEmpty {
            self
        } else {
            active.reduce(AnyView(self)) { acc, layer in
                guard let effect = ShaderCatalog.effect(for: layer.key) else { return acc }
                let shader = effect.shader(values: layer.params)
                switch effect.stage {
                case .color:
                    return AnyView(acc.colorEffect(shader))
                case .distortion:
                    return AnyView(acc.distortionEffect(shader, maxSampleOffset: ShaderCatalog.maxSampleOffset))
                }
            }
        }
    }
}
