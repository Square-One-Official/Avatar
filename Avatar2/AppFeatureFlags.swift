import Foundation

/// Release-tijd feature flags voor Aaavatar 2.0.
///
/// Compile-time constanten (geen runtime-toggle): één plek om een feature voor
/// de release uit te zetten zonder de code te verwijderen. Flip de constante en
/// rebuild om de feature weer aan te zetten.
enum AppFeatureFlags {

    /// De volledige Banners-suite — Banner Studio, de Banners-bibliotheek, de
    /// banner-secties op Home, en "een banner als portret-achtergrond"
    /// (E35–E40). Staat voor de eerste release UIT tot de feature sterk genoeg
    /// is. De code blijft bestaan; alleen de entry points zijn verborgen.
    ///
    /// Wat bewust WÉL blijft als dit `false` is: in de Social Preview kun je nog
    /// steeds de banner — die de portret-achtergrond matcht — exporteren als
    /// LinkedIn/X-cover. Je kunt er alleen geen eigen banner meer maken/kiezen.
    ///
    /// In DEBUG aan te zetten met de launch-arg `--enable-banners` (smoke-runs,
    /// banner-development) zonder de release-default te raken.
    static let bannersEnabled: Bool = enabledInDebug(flag: "banners")

    /// Face-paneel (beauty-edits). Staat UIT tot de face-bakeoff (E32.0) een
    /// go geeft. CMS-flag `face_enabled` is een extra kill-switch daarbovenop.
    /// DEBUG: `--enable-face` of `--open-panel face`.
    static let faceEnabled: Bool = enabledInDebug(flag: "face", openPanel: "face")

    /// Hair-paneel (kapselwissel). Zelfde release-gate als Face.
    /// DEBUG: `--enable-hair` of `--open-panel hair`.
    static let hairEnabled: Bool = enabledInDebug(flag: "hair", openPanel: "hair")

    /// Clothing-paneel (kledingwissel). Zelfde release-gate als Face.
    /// DEBUG: `--enable-clothes` of `--open-panel clothing`.
    static let clothesEnabled: Bool = enabledInDebug(flag: "clothes", openPanel: "clothing")

    /// DEBUG-only: `--enable-<flag>`, of `--open-panel <value>` zodat bestaande
    /// smoke-runs het paneel nog kunnen openen zonder extra args.
    private static func enabledInDebug(flag: String, openPanel: String? = nil) -> Bool {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--enable-\(flag)") { return true }
        if let openPanel,
           let i = args.firstIndex(of: "--open-panel"),
           args.indices.contains(i + 1),
           args[i + 1] == openPanel {
            return true
        }
        #endif
        return false
    }
}
