import Foundation

/// Release-tijd feature flags voor Aaavatar 2.0 (GTM-cut 2026-08-16).
///
/// Compile-time constanten (geen runtime-toggle): één plek om een feature voor
/// de release uit te zetten zonder de code te verwijderen. Flip de constante en
/// rebuild om de feature weer aan te zetten.
///
/// GTM-cut: Effects blijft AAN (USP). Face, custom Create, AI Generate
/// Background en Boost Online staan UIT tot ze een eigen kwaliteitsbar
/// halen. Banners blijven UIT tot er gebruikersvraag is. In DEBUG elk pad
/// aan te zetten met een launch-arg zonder de release-default te raken.
enum AppFeatureFlags {

    /// De volledige Banners-suite. DEBUG: `--enable-banners`.
    static let bannersEnabled: Bool = launchEnabled(argument: "--enable-banners")

    /// Face-capsule (Whiten teeth / Apply make-up / Reduce wrinkles).
    /// DEBUG: `--enable-face`.
    static let faceEnabled: Bool = launchEnabled(argument: "--enable-face")

    /// "Create" in het Effects-paneel. DEBUG: `--enable-custom-effects`.
    static let customEffectsEnabled: Bool = launchEnabled(argument: "--enable-custom-effects")

    /// AI Generate Background. Gallery + Unsplash blijven. DEBUG:
    /// `--enable-generate-background`.
    static let generateBackgroundEnabled: Bool = launchEnabled(argument: "--enable-generate-background")

    /// Boost Online (Topaz). On-device / 1-credit Boost blijft.
    /// DEBUG: `--enable-boost-online`.
    static let boostOnlineEnabled: Bool = launchEnabled(argument: "--enable-boost-online")

    /// Launch-hidden flags fail closed. In DEBUG mag een launch-arg ze openen
    /// voor smoke-runs; release-builds negeren die args.
    private static func launchEnabled(argument: String) -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(argument) { return true }
        #endif
        return false
    }
}
