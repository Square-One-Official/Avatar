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
    static let bannersEnabled: Bool = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--enable-banners") { return true }
        #endif
        return false
    }()
}
