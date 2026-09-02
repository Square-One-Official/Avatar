import Foundation

// MARK: - Language

enum Lang: String, CaseIterable, Identifiable {
    case en, nl
    var id: String { rawValue }
    var label: String {
        switch self {
        case .en: "English"
        case .nl: "Nederlands"
        }
    }

    static var current: Lang {
        Lang(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "en") ?? .en
    }
}

// MARK: - Localised strings

/// All user-facing strings, English by default.
/// Access via `Loc.xxx`. Reads `Lang.current` on every access so views
/// that re-render (e.g. because `appState.language` changed) pick up
/// the new language automatically.
enum Loc {
    private static var en: Bool { Lang.current == .en }

    // MARK: General
    static var cancel: String          { en ? "Cancel" : "Annuleer" }
    static var somethingWentWrong: String {
        en ? "Something went wrong. Please try again."
           : "Er ging iets mis. Probeer het nog eens."
    }
    static var delete: String          { en ? "Delete" : "Verwijder" }
    static var portraitsPlural: String { en ? "Portraits" : "portretten" }
    static func portraitsSelected(_ count: Int) -> String {
        if count == 1 {
            return en ? "1 portrait selected" : "1 portret geselecteerd"
        }
        return en ? "\(count) portraits selected" : "\(count) portretten geselecteerd"
    }
    static var ok: String              { "OK" }
    static var save: String            { en ? "Save" : "Opslaan" }
    static var name: String            { en ? "Name" : "Naam" }
    static var add: String             { en ? "Add" : "Toevoegen" }
    static var close: String           { en ? "Close" : "Sluiten" }
    static var dismiss: String         { en ? "Dismiss" : "Sluiten" }
    static var find: String            { en ? "Find" : "Zoek" }
    static var openEllipsis: String    { en ? "Open…" : "Open…" }
    static var showSidebar: String     { en ? "Show Sidebar" : "Toon zijbalk" }
    static var hideSidebar: String     { en ? "Hide Sidebar" : "Verberg zijbalk" }
    static var showInspector: String   { en ? "Show Inspector" : "Toon inspector" }
    static var hideInspector: String   { en ? "Hide Inspector" : "Verberg inspector" }
    static var error: String           { en ? "Error" : "Fout" }
    static var retry: String           { en ? "Retry" : "Probeer opnieuw" }
    static var relaunch: String        { en ? "Relaunch" : "Opnieuw starten" }
    static var select: String          { en ? "Select" : "Selecteer" }
    static var info: String            { "Info" }

    // MARK: Toolbar / Editor actions
    static var undo: String            { en ? "Undo" : "Stap terug" }
    static var undoHelp: String        { en ? "Undo (⌘Z)" : "Ongedaan maken (⌘Z)" }
    static var redo: String            { en ? "Redo" : "Stap vooruit" }
    static var redoHelp: String        { en ? "Redo (⌘⇧Z)" : "Opnieuw (⌘⇧Z)" }
    static var alignmentGuide: String  { en ? "Alignment Guide" : "Uitlijnhulp" }
    static var alignmentGuideHelp: String { en ? "Toggle the on-canvas guide and align all portraits" : "Schakel de hulplijn in/uit en lijn alle portretten uit" }
    static var alignmentShowGuide: String { en ? "Show guide on canvas" : "Toon hulplijn op canvas" }
    static var inspector: String       { "Inspector" }
    static var inspectorHelp: String   { en ? "Show or hide the inspector" : "Toon of verberg de instellingen" }
    static var export: String          { en ? "Export" : "Exporteer" }
    static var exportHelp: String      { en ? "Export portrait (⌘E)" : "Exporteer portret (⌘E)" }

    // MARK: Editor – Info section
    static var employeeName: String    { en ? "Name" : "Naam" }
    static var role: String            { en ? "Role" : "Rol" }

    // MARK: Editor – Background
    static var background: String      { en ? "Background" : "Achtergrond" }

    // MARK: Editor – Alignment
    static var autoAlignFace: String   { en ? "Auto-align to face" : "Auto-uitlijnen op gezicht" }
    static var autoAlignDisabledHelp: String {
        en ? "No face detected in this portrait."
           : "Geen gezicht gevonden in dit portret."
    }
    /// Undo action name for handle-based scale changes on the canvas.
    static var scale: String           { en ? "Scale" : "Schaal" }

    // MARK: Editor – Edit section
    static var edit: String            { en ? "Edit" : "Bewerken" }
    static var enhanceMenu: String     { en ? "Enhance" : "Verbeteren" }
    static var statusOn: String        { en ? "On" : "Aan" }
    static var statusOff: String       { en ? "Off" : "Uit" }
    static var redoWithMagicCutout: String {
        en ? "Redo with Magic Cutout" : "Opnieuw met Magic Cutout"
    }
    static var redoWithMagicCutoutHelp: String {
        en ? "This cutout was made with the basic model. Re-cut it with Magic Cutout for sharper edges."
           : "Deze uitknip is gemaakt met het basismodel. Knip opnieuw uit met Magic Cutout voor scherpere randen."
    }
    static var magicRetouchDone: String { "Magic Retouch ✓" }
    static var magicRetouch: String    { "Magic Retouch" }
    static var magicRetouchUndo: String {
        en ? "Undo Magic Retouch" : "Magic Retouch ongedaan maken"
    }
    static var magicRetouchAlready: String {
        en ? "Magic Retouch is already on for this portrait."
           : "Magic Retouch staat al aan voor dit portret."
    }
    static var magicRetouchHelp: String {
        en ? "Automatically enhances colors, exposure, and shadows for studio quality."
           : "Verbetert automatisch kleuren, belichting en schaduwen voor studiokwaliteit."
    }
    static var magicRetouchUndoHelp: String {
        en ? "Revert to the original cutout without Magic Retouch."
           : "Herstel de originele uitknip zonder Magic Retouch."
    }

    // MARK: Editor – Pro AI edits (Replicate-backed)
    static var fillBody: String {
        en ? "Fill in body" : "Vul lichaam aan"
    }
    static var fillBodyUndo: String {
        en ? "Undo fill in body" : "Lichaam aanvullen ongedaan maken"
    }
    static var fillBodyHelp: String {
        en ? "Reconstruct shoulders and torso when the photo is cropped."
           : "Reconstrueer schouders en bovenlichaam als de foto is bijgesneden."
    }
    static var fillBodyUndoHelp: String {
        en ? "Revert to the original cutout without the filled-in body."
           : "Herstel de originele uitknip zonder aangevuld lichaam."
    }
    static var fillBodyAlready: String {
        en ? "Body fill is already applied to this portrait."
           : "Lichaam aanvullen staat al aan voor dit portret."
    }
    static var fillBodyFailed: String {
        en ? "Couldn't fill in the body. Please try again."
           : "Kon het lichaam niet aanvullen. Probeer het opnieuw."
    }
    static var fillBodyAlreadyComplete: String {
        en ? "This portrait already looks complete \u{2014} no fill needed."
           : "Dit portret ziet er al compleet uit \u{2014} geen aanvulling nodig."
    }

    static var colorize: String {
        en ? "Colorise" : "Inkleuren"
    }
    static var colorizeUndo: String {
        en ? "Undo colorise" : "Inkleuren ongedaan maken"
    }
    static var colorizeHelp: String {
        en ? "Turn a black-and-white photo into colour with one click."
           : "Maak met één klik kleur van een zwart-witfoto."
    }
    static var colorizeUndoHelp: String {
        en ? "Revert to the original black-and-white cutout."
           : "Herstel de originele zwart-witversie."
    }
    static var colorizeAlready: String {
        en ? "This portrait is already colorised."
           : "Dit portret is al ingekleurd."
    }
    static var colorizeFailed: String {
        en ? "Couldn't colorise the photo. Please try again."
           : "Kon de foto niet inkleuren. Probeer het opnieuw."
    }

    // MARK: Settings – Library back-up (export / import)
    static var librarySectionTitle: String {
        en ? "Library back-up" : "Bibliotheek back-up"
    }
    static var librarySectionDesc: String {
        en ? "Export every portrait \u{2014} including its background, name, role and edits \u{2014} as a single file. Someone else can import that file to load the same library."
           : "Exporteer al je portretten \u{2014} inclusief achtergrond, naam, rol en bewerkingen \u{2014} als één bestand. Iemand anders kan dat bestand importeren om dezelfde bibliotheek te laden."
    }
    static var libraryExportButton: String {
        en ? "Export library\u{2026}" : "Bibliotheek exporteren\u{2026}"
    }
    static var libraryImportButton: String {
        en ? "Import library\u{2026}" : "Bibliotheek importeren\u{2026}"
    }
    static var libraryExportEmpty: String {
        en ? "Nothing to export \u{2014} your library is empty."
           : "Niets om te exporteren \u{2014} je bibliotheek is leeg."
    }
    static func libraryExportSuccess(_ count: Int) -> String {
        if count == 1 {
            return en ? "Exported 1 portrait." : "1 portret geëxporteerd."
        }
        return en ? "Exported \(count) portraits." : "\(count) portretten geëxporteerd."
    }
    static func libraryExportFailed(_ message: String) -> String {
        en ? "Export failed: \(message)" : "Exporteren mislukt: \(message)"
    }
    static var libraryExportFailedGeneric: String {
        en ? "Couldn't write the back-up file." : "Kon het back-upbestand niet schrijven."
    }
    static var libraryImportNotAnArchive: String {
        en ? "That file isn't a readable Aaavatar back-up."
           : "Dit bestand is geen leesbare Aaavatar back-up."
    }
    static var libraryImportMissingManifest: String {
        en ? "This zip doesn't contain an Aaavatar library."
           : "Deze zip bevat geen Aaavatar-bibliotheek."
    }
    static func libraryImportSchemaTooNew(_ version: Int) -> String {
        en ? "This back-up was made with a newer version of Aaavatar (schema v\(version)). Update the app to import it."
           : "Deze back-up is gemaakt met een nieuwere versie van Aaavatar (schema v\(version)). Werk de app bij om hem te importeren."
    }
    static func libraryImportFailed(_ message: String) -> String {
        en ? "Import failed: \(message)" : "Importeren mislukt: \(message)"
    }

    // Conflict-resolution sheet
    static var libraryImportSheetTitle: String {
        en ? "Import library" : "Bibliotheek importeren"
    }
    static func libraryImportSheetSummary(new: Int, conflicts: Int) -> String {
        let newPart = (new == 1)
            ? (en ? "1 new portrait" : "1 nieuw portret")
            : (en ? "\(new) new portraits" : "\(new) nieuwe portretten")
        let conflictPart = (conflicts == 1)
            ? (en ? "1 portrait already exists with the same ID"
                  : "1 portret bestaat al met hetzelfde ID")
            : (en ? "\(conflicts) portraits already exist with the same ID"
                  : "\(conflicts) portretten bestaan al met hetzelfde ID")
        if conflicts == 0 {
            return en ? "Found \(newPart) to add."
                      : "\(newPart) klaar om toe te voegen."
        }
        return en ? "Found \(newPart). \(conflictPart)."
                  : "\(newPart). \(conflictPart)."
    }
    static var libraryImportSheetQuestion: String {
        en ? "How should existing portraits be handled?"
           : "Hoe moeten bestaande portretten worden behandeld?"
    }
    static var libraryImportOptionAlwaysNewTitle: String {
        en ? "Add as new" : "Toevoegen als nieuw"
    }
    static var libraryImportOptionAlwaysNewDesc: String {
        en ? "Imported portraits get a fresh ID, so duplicates may appear next to existing ones. Safe default when importing someone else's library."
           : "Geïmporteerde portretten krijgen een nieuwe ID, dus duplicaten kunnen naast bestaande verschijnen. Veilige standaard bij het importeren van iemand anders' bibliotheek."
    }
    static var libraryImportOptionOverwriteTitle: String {
        en ? "Overwrite existing" : "Bestaande overschrijven"
    }
    static var libraryImportOptionOverwriteDesc: String {
        en ? "Replace existing portraits that share an ID with the imported version. Use to restore your own back-up."
           : "Vervang bestaande portretten met hetzelfde ID door de geïmporteerde versie. Gebruik dit om je eigen back-up terug te zetten."
    }
    static var libraryImportOptionSkipTitle: String {
        en ? "Skip existing" : "Bestaande overslaan"
    }
    static var libraryImportOptionSkipDesc: String {
        en ? "Keep existing portraits as they are. Only portraits with a new ID are added."
           : "Behoud bestaande portretten zoals ze zijn. Alleen portretten met een nieuwe ID worden toegevoegd."
    }
    static var libraryImportConfirm: String {
        en ? "Import" : "Importeren"
    }
    static func libraryImportSummary(added: Int, overwritten: Int, skipped: Int) -> String {
        var parts: [String] = []
        if added > 0 {
            parts.append(en ? "\(added) added" : "\(added) toegevoegd")
        }
        if overwritten > 0 {
            parts.append(en ? "\(overwritten) overwritten" : "\(overwritten) overschreven")
        }
        if skipped > 0 {
            parts.append(en ? "\(skipped) skipped" : "\(skipped) overgeslagen")
        }
        if parts.isEmpty {
            return en ? "Nothing imported." : "Niets geïmporteerd."
        }
        return (en ? "Imported: " : "Geïmporteerd: ") + parts.joined(separator: ", ") + "."
    }
    static var libraryExportFilenamePrefix: String {
        en ? "Aaavatar library" : "Aaavatar-bibliotheek"
    }

    static var proUpgradeSignInFirst: String {
        en ? "Please sign in first to manage your subscription."
           : "Meld je eerst aan om je abonnement te beheren."
    }

    /// Shown as a chip after a Magic Cutout call falls back to the basic
    /// cutout because the user's session expired or was never set up.
    /// Non-blocking — the basic cutout already produced a result.
    static var magicCutoutSignedOut: String {
        en ? "Signed out. Used the basic cutout. Sign in via Settings for Magic Cutout."
           : "Niet aangemeld. We gebruikten de basisuitsnijder. Meld je aan via Instellingen voor Magic Cutout."
    }

    // MARK: First-launch welcome sheet
    static var welcomeTitle: String {
        en ? "Welcome to Aaavatar" : "Welkom bij Aaavatar"
    }
    static var welcomeBody: String {
        en ? "Sign in with Google to keep your Pro subscription and credits in sync across your Macs. Your photos stay on your device — we only store your email and credit balance."
           : "Meld je aan met Google om je Pro-abonnement en credits gesynchroniseerd te houden tussen je Macs. Je foto's blijven op je apparaat — we bewaren alleen je e-mailadres en credits."
    }
    static var welcomeMaybeLater: String {
        en ? "Maybe later" : "Misschien later"
    }
    static var signInWithGoogle: String {
        en ? "Sign in with Google" : "Aanmelden met Google"
    }
    /// Recoverable OAuth failure / abandoned browser flow. Actionable,
    /// no raw SDK text.
    static var signInDidNotFinish: String {
        en ? "Sign-in didn’t finish. Check the browser window and try again."
           : "Aanmelden is niet gelukt. Controleer het browservenster en probeer opnieuw."
    }

    // MARK: Pro recovery sheet (fresh install, paid before signing in)
    static var recoverProLink: String {
        en ? "Already paid? Restore Pro with email" : "Al betaald? Herstel Pro met e-mail"
    }
    static var recoverProTitle: String {
        en ? "Restore Pro on this Mac" : "Pro herstellen op deze Mac"
    }
    static var recoverProBody: String {
        en ? "Enter the email you used to buy Pro. We'll send a sign-in link if we find a matching account."
           : "Voer het e-mailadres in waarmee je Pro hebt gekocht. We sturen een aanmeldlink als we een bijbehorend account vinden."
    }
    static var recoverProEmailLabel: String {
        en ? "Email" : "E-mailadres"
    }
    static var recoverProSendCta: String {
        en ? "Send recovery link" : "Stuur herstellink"
    }
    static var recoverProSent: String {
        en ? "If we have an account for that email, we sent a sign-in link. Check your inbox."
           : "Als we een account voor dat e-mailadres hebben, hebben we een aanmeldlink gestuurd. Bekijk je inbox."
    }
    static var recoverProCancel: String {
        en ? "Cancel" : "Annuleren"
    }

    // MARK: Onboarding — Privacy mode step
    static var onboardingPrivacyTitle: String {
        en ? "How should AI work?" : "Hoe mag AI werken?"
    }
    static var onboardingPrivacyBody: String {
        en ? "You can keep everything on this Mac, or let Aaavatar use cloud AI for higher-quality cutouts and extras. You can change this any time in Settings."
           : "Je kunt alles op deze Mac houden, of Aaavatar cloud-AI laten gebruiken voor scherpere uitsneden en extra's. Je kunt dit altijd wijzigen in Instellingen."
    }
    static var onboardingPrivacyLocalTitle: String {
        en ? "Local only" : "Alleen lokaal"
    }
    static var onboardingPrivacyLocalRecommended: String {
        en ? "Recommended for privacy" : "Aanbevolen voor privacy"
    }
    static var onboardingPrivacyLocalBody: String {
        en ? "Your photos never leave this Mac. Background removal runs entirely on-device. Magic Cutout, Fill in Body, and Colorize are turned off. Free accounts may still check import limits online — no photo bytes are uploaded."
           : "Je foto's verlaten deze Mac nooit. Achtergrond verwijderen gebeurt volledig op je apparaat. Magic Cutout, Fill in Body en Colorize staan uit. Gratis accounts kunnen nog online importlimieten checken — er gaan geen foto-bytes mee."
    }
    static var onboardingPrivacyCloudTitle: String {
        en ? "Allow cloud AI" : "Cloud-AI toestaan"
    }
    static var onboardingPrivacyCloudBody: String {
        en ? "Use Magic Cutout, Fill in Body, and Colorize. Photos are uploaded over HTTPS, processed, and discarded server-side. No sign-in required for the free trial."
           : "Gebruik Magic Cutout, Fill in Body en Colorize. Foto's worden via HTTPS geüpload, verwerkt en server-side verwijderd. Aanmelden niet nodig voor de gratis proefperiode."
    }

    // MARK: Onboarding — Local engine step
    static var onboardingEngineTitle: String {
        en ? "Pick a local engine" : "Kies een lokale engine"
    }
    static var onboardingEngineBody: String {
        en ? "How should background removal run on this Mac?"
           : "Hoe moet achtergrond verwijderen op deze Mac werken?"
    }
    static var onboardingEngineAppleVisionTitle: String {
        en ? "Apple Vision" : "Apple Vision"
    }
    static var onboardingEngineAppleVisionDefault: String {
        en ? "Default" : "Standaard"
    }
    static var onboardingEngineAppleVisionBody: String {
        en ? "Built into macOS. Instant. Hair edges can look chunky on long or curly hair against contrasting backgrounds."
           : "Ingebouwd in macOS. Onmiddellijk. Haarranden kunnen er blokkerig uitzien bij lang of krullend haar tegen een contrasterende achtergrond."
    }
    static var onboardingEngineDownloadedTitle: String {
        en ? "Download enhanced model" : "Verbeterd model downloaden"
    }
    static var onboardingEngineDownloadedBody: String {
        en ? "78 MB download. Cleaner cutout edges than the built-in pipeline, especially on hair. Runs entirely on this Mac. Choosing this starts the download now — it continues in Settings if you leave, and you can remove it there anytime."
           : "78 MB download. Strakkere uitsnede dan de standaard pipeline, met name op haar. Draait volledig op deze Mac. Als je dit kiest, start de download meteen — die loopt door in Instellingen als je weggaat, en je kunt het daar altijd verwijderen."
    }

    // MARK: Onboarding — Generic
    static var onboardingBack: String { en ? "Back" : "Terug" }
    static var onboardingContinue: String { en ? "Continue" : "Doorgaan" }
    static var onboardingDone: String { en ? "Done" : "Klaar" }
    static var onboardingSkip: String { en ? "Skip" : "Overslaan" }
    /// Used in the engine step when the model download fails — clicking
    /// Done falls back to Apple Vision rather than leaving the user
    /// stuck on a broken-download state.
    static var onboardingDoneWithoutEnhanced: String {
        en ? "Continue without enhanced model"
           : "Doorgaan zonder verbeterd model"
    }
    static var onboardingChoiceSelected: String {
        en ? "Selected" : "Geselecteerd"
    }
    static var onboardingChoiceNotSelected: String {
        en ? "Not selected" : "Niet geselecteerd"
    }
    static func onboardingChoiceHint(_ index: Int, of count: Int) -> String {
        en ? "Choice \(index) of \(count)"
           : "Keuze \(index) van \(count)"
    }

    // MARK: Settings — Privacy & AI section
    static var privacyAndAITitle: String {
        en ? "Privacy & AI" : "Privacy & AI"
    }
    static var privacyAndAIDesc: String {
        en ? "Choose whether AI features run locally on this Mac or in the cloud. Local-only disables Magic Cutout, Fill in Body, and Colorize. Your photos stay on this Mac either way; free accounts may still check import limits online."
           : "Kies of AI-functies lokaal op deze Mac draaien of in de cloud. Alleen-lokaal schakelt Magic Cutout, Fill in Body en Colorize uit. Je foto's blijven hoe dan ook op deze Mac; gratis accounts kunnen nog online importlimieten checken."
    }
    static var privacyModePickerLabel: String { en ? "Mode" : "Modus" }
    static var privacyEnginePickerLabel: String { en ? "Engine" : "Engine" }
    static var privacyDisabledInLocalOnly: String {
        en ? "Disabled in Local-only mode."
           : "Uitgeschakeld in modus Alleen lokaal."
    }
    static var magicCutoutLocalOnlySummary: String {
        en ? "Magic Cutout needs cloud AI. Switch mode above to Allow cloud AI, then turn this on."
           : "Magic Cutout heeft cloud-AI nodig. Kies hierboven Cloud-AI toestaan, en zet dit daarna aan."
    }
    static var enableCloudAIInPrivacySettings: String {
        en ? "Allow cloud AI"
           : "Cloud-AI toestaan"
    }
    static var cloudFeatureRequiresCloudAI: String {
        en ? "This feature uses cloud AI."
           : "Deze functie gebruikt cloud-AI."
    }
    static var openPrivacySettingsCTA: String {
        en ? "Privacy & AI"
           : "Privacy & AI"
    }
    // Audit MEDIUM #27. Toggle copy kept for a future telemetry surface;
    // the Settings UI hides the control until something reads the flag.
    static var privacyDiagnosticsTitle: String {
        en ? "Share anonymous diagnostics"
           : "Anonieme diagnostiek delen"
    }
    static var privacyDiagnosticsDesc: String {
        en ? "Aaavatar currently sends no usage analytics. If we add optional telemetry (app version, macOS version, feature usage), this switch governs it. Sign-in events go through Supabase regardless — see Privacy Policy."
           : "Aaavatar verstuurt op dit moment geen gebruiksanalyses. Als we straks optionele telemetrie toevoegen (appversie, macOS-versie, functie­gebruik), bepaalt deze schakelaar of die meegaat. Aanmeldgebeurtenissen lopen sowieso via Supabase — zie het privacybeleid."
    }
    // MARK: Downloadable matting model (ORMBG)
    static var modelDownloadButton: String {
        en ? "Download model" : "Model downloaden"
    }
    static var modelDownloadSizeHint: String {
        en ? "78 MB · stored in this app's container"
           : "78 MB · bewaard in de map van deze app"
    }
    static func modelDownloadingLabel(percent: Int) -> String {
        en ? "Downloading… \(percent)%" : "Downloaden… \(percent)%"
    }
    static var modelDownloadedReady: String {
        en ? "Enhanced model ready" : "Verbeterd model klaar"
    }
    static var modelRemoveButton: String {
        en ? "Remove" : "Verwijderen"
    }
    static var modelDownloadRetryButton: String {
        en ? "Try again" : "Opnieuw proberen"
    }
    /// User-facing download / install failures — recovery-first, no HTTP
    /// codes or hash prefixes (those stay in the log).
    static var modelDownloadFailed: String {
        en ? "Couldn't download the model. Check your connection and try again."
           : "Model downloaden mislukt. Controleer je verbinding en probeer opnieuw."
    }
    static var modelVerificationFailed: String {
        en ? "The download didn’t pass the integrity check. Try again."
           : "De download doorstond de integriteitscheck niet. Probeer opnieuw."
    }
    static var modelUnzipFailed: String {
        en ? "Couldn't extract the model. Try again."
           : "Model uitpakken mislukt. Probeer opnieuw."
    }
    static var modelInstallFailed: String {
        en ? "Couldn't install the model. Try again."
           : "Model installeren mislukt. Probeer opnieuw."
    }
    static var modelMissingFallbackToast: String {
        en ? "Enhanced model isn't downloaded yet. Used Apple Vision for this import. Download in Settings → Privacy & AI."
           : "Het verbeterde model is nog niet gedownload. Apple Vision werd gebruikt voor deze import. Downloaden in Instellingen → Privacy & AI."
    }

    // MARK: Cloud-feature gating toasts (local-only)
    static var reprocessRequiresCloudAI: String {
        en ? "Re-cutout uses cloud AI."
           : "Opnieuw uitsnijden gebruikt cloud-AI."
    }

    // MARK: Account / Pro settings section
    static var accountSectionTitle: String  { en ? "Account" : "Account" }
    static var accountNotSignedIn: String   { en ? "Not signed in" : "Niet aangemeld" }
    static var accountSignInRationale: String {
        en ? "Sign in with Google to unlock Pro features and tie your subscription to your account. Your photos and edits stay on your Mac. We only store your email and credit balance."
           : "Meld je aan met Google om Pro-functies te ontgrendelen en je abonnement aan je account te koppelen. Je foto's en bewerkingen blijven op je Mac. We bewaren alleen je e-mailadres en credits."
    }
    static var accountEmailLabel: String    { en ? "Email" : "E-mail" }
    static var accountEmailFromGoogle: String {
        en ? "Email comes from your Google account. Sign out to use a different one."
           : "Je e-mailadres komt van je Google-account. Meld je af om een ander te gebruiken."
    }
    static var proSectionTitle: String      { en ? "Pro" : "Pro" }
    static var proSectionSubtitle: String {
        en ? "Magic Cutout, monthly credits included"
           : "Magic Cutout, met maandelijkse credits"
    }
    /// Account upgrade blurb when Privacy mode is Local-only — don't pitch
    /// cloud cutout while uploads are off.
    static var proSectionSubtitleLocalOnly: String {
        en ? "Unlimited portraits on this Mac"
           : "Onbeperkt portretten op deze Mac"
    }
    static var proSignInWithGoogle: String  { en ? "Sign in with Google" : "Aanmelden met Google" }
    static var proSignOut: String           { en ? "Sign out" : "Afmelden" }
    static var proCurrentPlan: String       { en ? "Plan" : "Abonnement" }
    static var proCreditsRemaining: String  { en ? "Credits remaining" : "Credits over" }
    static var proRenewsAt: String          { en ? "Renews" : "Vernieuwt op" }
    static var proManageSubscription: String {
        en ? "Manage subscription" : "Beheer abonnement"
    }
    static var proNoSubscription: String {
        en ? "No active subscription." : "Geen actief abonnement."
    }
    static var proUpgradeNow: String         { en ? "Upgrade" : "Upgraden" }

    // MARK: Magic Cutout (Pro)
    static var magicCutoutTitle: String {
        en ? "Magic Cutout" : "Magic Cutout"
    }
    static var magicCutoutSubtitle: String {
        en ? "Premium AI cutout, 1 credit per image"
           : "Premium AI-uitsnede, 1 credit per foto"
    }
    static var magicCutoutDescription: String {
        en ? "Cloud-powered AI cutout with state-of-the-art hair detail and clean body edges. Falls back to the basic cutout when offline."
           : "AI-uitsnede in de cloud met topkwaliteit haardetails en strakke lichaamsranden. Valt terug op de basisuitsnede als je offline bent."
    }
    static var magicCutoutOfflineToast: String {
        en ? "Offline. Magic Cutout needs internet. Using basic cutout for now. No credits used."
           : "Geen verbinding. Magic Cutout is even niet beschikbaar. We gebruiken nu de basisuitsnijder. Geen credits gebruikt."
    }
    static func magicCutoutBatchConfirm(_ count: Int, credits: Int) -> String {
        en ? "Importing \(count) photos will use \(credits) credits. Continue?"
           : "\(count) foto's importeren kost \(credits) credits. Doorgaan?"
    }
    static func magicCutoutUseCredits(_ credits: Int) -> String {
        en ? "Use \(credits) credits" : "Gebruik \(credits) credits"
    }
    static var magicCutoutProBadge: String {
        en ? "Pro" : "Pro"
    }
    static var magicCutoutOutOfCredits: String {
        en ? "You're out of credits. Top up to keep using Magic Cutout."
           : "Je credits zijn op. Koop bij om Magic Cutout te blijven gebruiken."
    }
    static var magicCutoutProRequired: String {
        en ? "Pro required. €4.99/month for 200 credits."
           : "Pro vereist. €4,99/maand voor 200 credits."
    }
    /// Shown when the backend returns an HTTP error code (4xx/5xx other than
    /// 401/402). Status and detail are kept in `print()` logs only — users
    /// see a friendly message that names the fallback and reassures about
    /// billing.
    static func magicCutoutServerError(_ code: Int, _ message: String?) -> String {
        let _ = (code, message) // routed to logs via the call site
        return en
            ? "Magic Cutout had a hiccup. Using the basic cutout instead. No credits charged."
            : "Magic Cutout had even een dipje. We gebruiken nu de basisuitsnijder. Geen credits afgeschreven."
    }
    /// Shown when the backend response can't be decoded (unexpected shape,
    /// invalid base64, etc.). Distinct from the offline toast.
    static var magicCutoutDecodeError: String {
        en ? "Magic Cutout sent something we couldn't read. Using the basic cutout. No credits charged."
           : "Magic Cutout stuurde iets wat we niet konden lezen. We gebruiken nu de basisuitsnijder. Geen credits afgeschreven."
    }
    /// Shown when the input PNG exceeds the Magic Cutout size cap. The cap
    /// is a real transport limit (Supabase Storage), so the copy is
    /// matter-of-fact rather than apologetic — the basic-cutout fallback
    /// reads as intentional, not as a fault.
    static func magicCutoutImageTooLarge(_ mb: Int) -> String {
        en ? "Image is over \(mb) MB. Magic Cutout can't process this size. Using the basic cutout. No credits charged."
           : "De afbeelding is groter dan \(mb) MB. Magic Cutout kan dit formaat niet verwerken. We gebruiken nu de basisuitsnijder. Geen credits afgeschreven."
    }

    // MARK: Pro paywall
    static var proUpgradeTitle: String {
        en ? "Go Pro" : "Word Pro"
    }
    static var proUpgradeHeadline: String {
        en ? "Unlock all the power"
           : "Ontgrendel alle kracht"
    }
    static var proUpgradeSubtitle: String {
        en ? "Unlock all the power. Cancel anytime."
           : "Ontgrendel alle kracht. Op elk moment opzegbaar."
    }
    static var proPlanName: String { "Pro" }
    static var proPlanPrice: String { "€4,99" }
    static var proPerMonth: String {
        en ? "/month" : "/maand"
    }
    static var proPerYear: String {
        en ? "/year" : "/jaar"
    }
    /// "Buy 200 credits" / "Koop 200 credits" — concrete amount on the
    /// CTA so the user sees what they're committing to.
    static func buyCreditsCTA(_ count: Int) -> String {
        en ? "Buy \(count) credits" : "Koop \(count) credits"
    }
    /// Decimal locale for currency formatting (per-credit display in
    /// the top-up paywall). Tracks the in-app language preference so
    /// "€0,040" renders correctly for NL and "€0.040" for EN.
    static var currencyLocale: Locale {
        en ? Locale(identifier: "en_US") : Locale(identifier: "nl_NL")
    }
    static var proSubscribeCTA: String {
        en ? "Subscribe" : "Abonneer"
    }
    static var proPlanDescription: String {
        en ? "200 credits each month. Magic Cutout uses 1 credit. Resets monthly."
           : "200 credits per maand. Magic Cutout kost 1 credit. Reset elke maand."
    }
    static var proPlanFeaturesHeader: String {
        en ? "Includes" : "Inclusief"
    }
    static var proPlanFeatureUnlimited: String {
        en ? "Unlimited portrait library"
           : "Onbeperkte portretbibliotheek"
    }
    static func proPlanFeatureBatch(_ max: Int) -> String {
        en ? "Import up to \(max) photos in one go"
           : "Importeer tot \(max) foto's in één keer"
    }
    static var proPlanFeatureCutout: String {
        en ? "Pristine background removal"
           : "Vlekkeloze vrijstaande foto's"
    }
    static var proPlanFeatureHair: String {
        en ? "Crispy hair, every time"
           : "Haarscherpe randen, elke keer"
    }
    static var proPlanFeatureCredits: String {
        en ? "200 credits per month" : "200 credits per maand"
    }
    /// Paywall bullet when Privacy mode is Local-only — cloud extras stay
    /// available after the user allows cloud AI.
    static var proPlanFeatureCloudWhenAllowed: String {
        en ? "Cloud AI extras when you allow them in Privacy & AI"
           : "Cloud-AI-extra's zodra je die toestaat in Privacy & AI"
    }
    static var proUpgradeFinePrint: String {
        en ? "Cancel anytime. Credits reset at the start of each billing period. Top-up credits never expire."
           : "Op elk moment opzegbaar. Credits resetten aan het begin van elke factuurperiode. Bijgekochte credits vervallen nooit."
    }

    // MARK: Checkout error copy
    /// Generic "tap to retry" CTA used inside the StatusChip after a
    /// checkout failure. Kept short so the chip stays compact.
    static var tryAgain: String {
        en ? "Try again" : "Opnieuw"
    }
    /// Stripe responded with an error (network, tax config, etc.) —
    /// implies a retry might just work.
    static var checkoutStripeUnavailable: String {
        en ? "Stripe is temporarily unreachable. Please try again."
           : "Stripe is even niet bereikbaar. Probeer het zo nog eens."
    }
    /// Generic backend error initialising checkout — Supabase upsert
    /// failure or unhandled exception. Same recovery path as Stripe
    /// errors (retry).
    static var checkoutInitFailed: String {
        en ? "Couldn't start checkout. Please try again."
           : "We konden de checkout niet starten. Probeer het opnieuw."
    }
    /// Pricing env var missing on the backend — only us can fix this.
    /// Don't promise a retry will work; ask the user to contact support.
    static var checkoutPricingMisconfigured: String {
        en ? "Pricing is temporarily unavailable. Please contact support."
           : "Prijzen zijn tijdelijk niet beschikbaar. Neem contact op met support."
    }
    /// 429 from the rate limiter. Retry will work after a short wait.
    static var checkoutRateLimited: String {
        en ? "Too many attempts. Please wait a moment and try again."
           : "Te veel pogingen. Wacht even en probeer het opnieuw."
    }
    /// Transport / URLSession error — phone is offline, DNS failed, etc.
    static var checkoutOffline: String {
        en ? "No internet. Connect to a network and try again."
           : "Geen internet. Maak verbinding en probeer het opnieuw."
    }
    /// Catch-all when none of the above mapped. Stays generic instead of
    /// leaking a raw error code into the chip.
    static var checkoutGenericError: String {
        en ? "Something went wrong. Please try again."
           : "Er ging iets mis. Probeer het opnieuw."
    }

    // MARK: Cross-device sync banner (post pre-auth checkout)
    /// Title shown on the sync banner. Past-tense affirmative — "you ARE
    /// Pro on this Mac" — before pivoting to the call-to-action.
    static var syncBannerTitle: String {
        en ? "Pro is active on this Mac"
           : "Pro is actief op deze Mac"
    }
    /// Body explaining how to extend Pro to other Macs. Includes the
    /// captured email so the user knows which inbox to check.
    static func syncBannerBody(email: String) -> String {
        en ? "Want Pro on your other Macs too? Sign in with \(email) to sync."
           : "Wil je Pro ook op je andere Macs? Meld je aan met \(email) om te synchroniseren."
    }
    /// CTA on the banner. Triggers /v1/account/resend-magic-link.
    static var syncBannerSendLink: String {
        en ? "Email me a sign-in link" : "Stuur me een aanmeldlink"
    }
    /// Brief confirmation toast after the email is sent.
    static func syncBannerLinkSent(email: String) -> String {
        en ? "Sign-in link sent to \(email). Check your inbox."
           : "Aanmeldlink verstuurd naar \(email). Check je inbox."
    }
    /// Error if the resend call fails.
    static var syncBannerSendFailed: String {
        en ? "Couldn't send the sign-in link. Try again."
           : "Aanmeldlink kon niet verstuurd worden. Probeer het opnieuw."
    }

    // MARK: Top-up
    static var topupCardTitle: String {
        en ? "Buy more credits" : "Koop extra credits"
    }
    static var topupCardPrice: String { "€4,99" }
    static var topupCardDescription: String {
        en ? "Extra credits on top of your monthly grant. They never expire."
           : "Extra credits bovenop je maandelijkse tegoed. Vervallen nooit."
    }
    static var topupCTA: String {
        en ? "Buy credits" : "Koop credits"
    }
    static var topupOneTime: String {
        en ? "One-time" : "Eenmalig"
    }

    // Out-of-credits paywall (shown to active Pro users who hit 0 credits).
    static var topupHeadline: String {
        en ? "You're out of credits this month"
           : "Je credits zijn op deze maand"
    }
    static func topupSubtitleResetsOn(_ date: String) -> String {
        en ? "Top up to keep going, or wait until your next renewal on \(date)."
           : "Koop credits bij om door te gaan, of wacht tot je volgende verlenging op \(date)."
    }
    static var topupSubtitleNoDate: String {
        en ? "Top up to keep going, or wait until your next renewal."
           : "Koop credits bij om door te gaan, of wacht tot je volgende verlenging."
    }
    static var buyMoreCredits: String {
        en ? "Buy more credits" : "Koop meer credits"
    }

    // MARK: Settings - credits readout
    static func creditsRemaining(_ n: Int) -> String {
        en ? "\(n) credits remaining" : "\(n) credits over"
    }
    static func creditsResetOn(_ date: String) -> String {
        en ? "Resets \(date)" : "Reset op \(date)"
    }
    static var creditsBalanceTitle: String {
        en ? "Credits" : "Credits"
    }
    static var creditsBalanceDesc: String {
        en ? "Buy extra credits so you can keep editing portraits when your monthly grant runs out. Top-up credits never expire."
           : "Koop extra credits zodat je kunt blijven bewerken als je maandelijkse tegoed op is. Bijgekochte credits vervallen nooit."
    }
    static var creditsBalanceLabel: String {
        en ? "Current balance" : "Huidig saldo"
    }
    static func creditsCount(_ n: Int) -> String {
        en ? (n == 1 ? "1 credit" : "\(n) credits")
           : (n == 1 ? "1 credit" : "\(n) credits")
    }

    // MARK: Legal links
    static var termsOfService: String       { en ? "Terms of Service" : "Algemene voorwaarden" }
    static var privacyPolicy: String        { en ? "Privacy Policy" : "Privacybeleid" }

    // MARK: Editor – Adjustments
    static var colorAdjustments: String { en ? "Color Adjustments" : "Kleuraanpassingen" }
    static var exposure: String        { en ? "Exposure" : "Belichting" }
    static var contrast: String        { "Contrast" }
    static var tint: String            { "Tint" }
    static var saturation: String      { en ? "Saturation" : "Verzadiging" }
    static var temperature: String     { en ? "Temperature" : "Temperatuur" }
    static var highlights: String      { "Highlights" }
    static var shadows: String         { en ? "Shadows" : "Schaduwen" }
    static var resetAdjustments: String { en ? "Reset Adjustments" : "Herstel aanpassingen" }
    static var adjustment: String      { en ? "Adjustment" : "Aanpassing" }
    static var adjustmentTileHint: String {
        en ? "Shows the slider for this adjustment."
           : "Toont de schuifregelaar voor deze aanpassing."
    }

    // MARK: Editor – Sidebar tabs
    static var tabPortrait: String     { en ? "Portrait" : "Portret" }
    static var tabAdjust: String       { en ? "Adjust" : "Afstellen" }

    // MARK: Editor – Library section
    static var library: String         { en ? "Library" : "Bibliotheek" }
    static var alignAllPortraits: String { en ? "Align all portraits" : "Lijn alle portretten uit" }
    static func alignAllHelp(_ count: Int) -> String {
        en ? "Applies the same face size and eye height to \(count) portraits."
           : "Past dezelfde gezichtsgrootte en ooghoogte toe op \(count) portretten."
    }

    // MARK: Editor – Bulk align dialog
    static var alignAllQuestion: String { en ? "Align all portraits?" : "Alle portretten uitlijnen?" }
    static func alignButton(_ count: Int) -> String {
        en ? "Align (\(count))" : "Uitlijnen (\(count))"
    }
    static func alignConfirmMessage(_ count: Int) -> String {
        en ? "This will overwrite manual adjustments for \(count) portraits. You can undo with ⌘Z."
           : "Hiermee worden handmatige aanpassingen overschreven voor \(count) portretten. Je kunt dit ongedaan maken met ⌘Z."
    }
    static var alignComplete: String   { en ? "Alignment complete" : "Uitlijnen voltooid" }
    static func skippedPortraits(_ n: Int) -> String {
        en ? "\(n) \(n == 1 ? "portrait skipped" : "portraits skipped"), no face found."
           : "\(n) \(n == 1 ? "portret overgeslagen" : "portretten overgeslagen"), geen gezicht gevonden."
    }

    // MARK: Editor – Undo action names
    static var moveAction: String      { en ? "Move" : "Verplaats" }
    static var autoAlignAction: String { en ? "Auto-align" : "Auto-uitlijnen" }
    static var backgroundAction: String { en ? "Background" : "Achtergrond" }

    // MARK: Editor – Drop / processing overlays
    static var dropPhotoHere: String {
        en ? "Drop photo here for a new portrait"
           : "Drop foto hier voor een nieuw portret"
    }
    static var processingPhoto: String { en ? "Processing photo…" : "Foto verwerken…" }

    /// Playful rotating status messages shown while a photo is processing.
    /// Opens with a lively line so the loader never reads as generic
    /// "Processing…"; later messages lean into the wait.
    static var processingStatuses: [String] {
        en ? [
            "Warming up the scissors…",
            "Removing the background…",
            "Touching up the hair…",
            "Wow, that's a lot of hair…",
            "Sharpening the details…",
            "Counting every pixel…",
            "Polishing the edges…",
            "Consulting the stylist…",
            "Having second thoughts…",
            "Almost there, promise…",
        ] : [
            "Schaartjes opwarmen…",
            "Achtergrond verwijderen…",
            "Haar bijwerken…",
            "Oef, dat is veel haar…",
            "Details aanscherpen…",
            "Elke pixel tellen…",
            "Randjes polijsten…",
            "De stylist erbij halen…",
            "Even twijfelen…",
            "Bijna klaar, echt waar…",
        ]
    }

    /// Status messages shown during Fill in Body. The cutout-flavoured
    /// scissors/hair copy doesn't fit when the work is reconstructing a
    /// torso, so this set leans into "drawing the rest of the person."
    /// Same length as `processingStatuses` so the per-index dwell times
    /// in `ProcessingStatusView` line up either way.
    static var fillBodyProcessingStatuses: [String] {
        en ? [
            "Sketching the rest of the body…",
            "Adding the shoulders…",
            "Tailoring the shirt…",
            "Did someone order arms?",
            "Filling in the torso…",
            "Smoothing the contours…",
            "Matching the lighting…",
            "Borrowing a dress form…",
            "Polishing the result…",
            "Almost there, promise…",
        ] : [
            "De rest van het lichaam schetsen…",
            "Schouders toevoegen…",
            "Het shirt op maat maken…",
            "Wie had er armen besteld?",
            "Romp invullen…",
            "Contouren bijwerken…",
            "Belichting matchen…",
            "Even een paspop lenen…",
            "Het resultaat polijsten…",
            "Bijna klaar, echt waar…",
        ]
    }

    /// Status messages shown during Colorise. Same length as
    /// `processingStatuses` so dwell times line up.
    static var colorizeProcessingStatuses: [String] {
        en ? [
            "Mixing the paint…",
            "Picking a palette…",
            "Warming up the skin tones…",
            "Choosing a shirt colour…",
            "Adding a touch of saturation…",
            "Bringing the eyes to life…",
            "Balancing the highlights…",
            "Letting the colours settle…",
            "Polishing the result…",
            "Almost there, promise…",
        ] : [
            "De verf mengen…",
            "Een palet kiezen…",
            "Huidtinten opwarmen…",
            "Een kleur voor het shirt kiezen…",
            "Een vleugje verzadiging toevoegen…",
            "De ogen tot leven wekken…",
            "De hooglichten in balans brengen…",
            "Kleuren laten bezinken…",
            "Het resultaat polijsten…",
            "Bijna klaar, echt waar…",
        ]
    }

    /// Status messages shown during Stylize / Effects / Hair / Clothes.
    /// Generic enough to cover all three intents — the actual prompt the
    /// backend ran is hidden from the user.
    static var stylizeProcessingStatuses: [String] {
        en ? [
            "Reading the portrait…",
            "Sketching the new look…",
            "Holding the face steady…",
            "Letting the model think…",
            "Refining the detail…",
            "Matching the lighting…",
            "Cleaning the edges…",
            "Final pass…",
            "Polishing the result…",
            "Almost there, promise…",
        ] : [
            "Het portret lezen…",
            "De nieuwe look schetsen…",
            "Het gezicht vasthouden…",
            "Het model laat denken…",
            "De details bijwerken…",
            "Belichting matchen…",
            "Randen opschonen…",
            "Laatste check…",
            "Het resultaat polijsten…",
            "Bijna klaar, echt waar…",
        ]
    }

    /// Status messages shown during Upscale. Short list — the call is
    /// faster than the generative steps.
    static var upscaleProcessingStatuses: [String] {
        en ? [
            "Boosting resolution…",
            "Sharpening the detail…",
            "Re-attaching the alpha…",
            "Polishing the result…",
        ] : [
            "Resolutie verhogen…",
            "Details verscherpen…",
            "Alpha terugzetten…",
            "Het resultaat polijsten…",
        ]
    }

    /// Returns the message rotation that fits the current processing kind.
    static func processingStatuses(for kind: ProcessingKind) -> [String] {
        switch kind {
        case .cutout:   return processingStatuses
        case .fillBody: return fillBodyProcessingStatuses
        case .colorize: return colorizeProcessingStatuses
        case .stylize:  return stylizeProcessingStatuses
        case .upscale:  return upscaleProcessingStatuses
        }
    }

    // MARK: Editor – Background picker context menu
    static var rename: String          { en ? "Rename…" : "Hernoem…" }
    static var renameBackground: String { en ? "Rename background" : "Achtergrond hernoemen" }
    static var setDefault: String      { en ? "Set as default" : "Maak standaard" }
    static var defaultCheck: String    { en ? "Default ✓" : "Standaard ✓" }

    // MARK: Editor – Color palette
    static var colorBlack: String      { en ? "Black" : "Zwart" }
    static var colorBlue: String       { en ? "Blue" : "Blauw" }
    static var colorGreen: String      { en ? "Green" : "Groen" }
    static var colorYellow: String     { en ? "Yellow" : "Geel" }
    static var colorRed: String        { en ? "Red" : "Rood" }
    static var colorSky: String        { en ? "Sky" : "Hemelblauw" }
    static var colorLavender: String   { en ? "Lavender" : "Lavendel" }
    static var colorIndigo: String     { en ? "Indigo" : "Indigo" }
    static var colorCoral: String      { en ? "Coral" : "Koraal" }

    // MARK: Editor – Add background popover
    static var uploadImage: String     { en ? "Upload image…" : "Upload afbeelding…" }
    static var chooseColor: String     { en ? "Choose a color" : "Kies een kleur" }
    static var color: String           { en ? "Color" : "Kleur" }
    static var customColor: String     { en ? "Custom color" : "Aangepaste kleur" }
    static var customColorTile: String { en ? "Custom…" : "Aangepast…" }
    static var hexLabel: String        { en ? "Hex" : "Hex" }
    static var invalidHex: String      { en ? "Enter a 6-digit hex value" : "Voer een 6-cijferige hex-waarde in" }

    // MARK: Settings – Tabs
    static var settingsGeneral: String { en ? "General" : "Algemeen" }
    static var settingsAccount: String { en ? "Account" : "Account" }
    static var appearance: String      { en ? "Appearance" : "Weergave" }
    static var appearanceDesc: String {
        en ? "Choose how Aaavatar looks. Dark uses a deeper near-black palette."
           : "Kies hoe Aaavatar eruitziet. Donker gebruikt een dieper bijna-zwart palet."
    }

    // MARK: Settings – Backgrounds tab
    static var backgrounds: String     { en ? "Backgrounds" : "Achtergronden" }
    static var addImage: String        { en ? "Add image" : "Voeg afbeelding toe" }
    static var addColor: String        { en ? "Add color" : "Voeg kleur toe" }
    static var setAsDefault: String    { en ? "Set as default" : "Stel in als standaard" }

    // MARK: Settings – Export presets tab
    static var exportPresets: String   { en ? "Export Presets" : "Export presets" }
    static var new: String             { en ? "New" : "Nieuw" }
    static var addPreset: String       { en ? "Add" : "Voeg toe" }
    static var width: String           { en ? "Width" : "Breedte" }
    static var height: String          { en ? "Height" : "Hoogte" }
    static var shape: String           { en ? "Shape" : "Vorm" }
    static var square: String          { en ? "Square" : "Vierkant" }
    static var circle: String          { en ? "Circle" : "Cirkel" }

    // (Legacy "Settings – AI Model tab" strings removed. They referenced
    // the bundled 250 MB BiRefNet model that was deleted in build 6
    // and the Settings tab that surfaced it, which the local-first
    // pivot replaced with the Privacy & AI section + the optional
    // downloadable ORMBG engine. The strings had no remaining call
    // sites at the time of removal — confirmed via grep before
    // dropping them.)
    static var advancedModelToggleHelp: String {
        en ? "When enabled, new and re-cut portraits are processed with the advanced model. Existing portraits are not automatically reprocessed. Use 'Re-cutout' in the editor."
           : "Wanneer ingeschakeld worden nieuwe en opnieuw uitgeknipte portretten verwerkt met het geavanceerde model. Bestaande portretten worden niet automatisch opnieuw verwerkt. Gebruik 'Opnieuw uitknippen' in de editor."
    }

    // MARK: Settings – Updates tab
    static var updates: String         { "Updates" }
    static var currentVersion: String  { en ? "Current version" : "Huidige versie" }
    static var autoCheckUpdates: String {
        en ? "Check for updates automatically"
           : "Controleer automatisch op updates"
    }
    static var checkNow: String        { en ? "Check now" : "Controleer nu" }
    static func lastChecked(_ date: String) -> String {
        en ? "Last checked: \(date) ago" : "Laatst gecontroleerd: \(date) geleden"
    }
    static func versionReady(_ version: String) -> String {
        en ? "Version \(version) is ready to install"
           : "Versie \(version) is klaar om te installeren"
    }

    // MARK: Settings – Language tab
    static var language: String        { en ? "Language" : "Taal" }
    static var languageDesc: String {
        en ? "Choose the display language for the app."
           : "Kies de weergavetaal voor de app."
    }

    // MARK: Export sheet
    static var exportPortrait: String  { en ? "Export portrait" : "Exporteer portret" }
    static var exportHere: String      { en ? "Export here" : "Exporteer hier" }
    static var noImageToExport: String { en ? "Nothing to export yet." : "Nog niets om te exporteren." }
    static func exportFailed(_ names: String) -> String {
        en ? "Couldn't export: \(names)"
           : "Niet gelukt om te exporteren: \(names)"
    }
    static func filesSaved(_ count: Int) -> String {
        en ? "\(count) file\(count == 1 ? "" : "s") saved"
           : "\(count) bestand\(count == 1 ? "" : "en") opgeslagen"
    }
    static var portrait: String        { en ? "Portrait" : "Portret" }
    static func exportCount(_ count: Int) -> String {
        en ? "Export\(count > 0 ? " (\(count))" : "")"
           : "Exporteer\(count > 0 ? " (\(count))" : "")"
    }

    // MARK: Library
    static var searchPlaceholder: String { en ? "Search by name or role" : "Zoek op naam of rol" }
    static var noPortraitsYet: String  { en ? "No portraits yet" : "Nog geen portretten" }
    static var noResults: String       { en ? "No results" : "Geen resultaten" }
    static var importToStart: String   { en ? "Import a photo to get started." : "Importeer een foto om te beginnen." }
    static var adjustSearch: String    { en ? "Adjust your search." : "Pas je zoekopdracht aan." }
    static var processing: String      { en ? "Processing…" : "Verwerken…" }
    static var unnamed: String         { en ? "(unnamed)" : "(naamloos)" }
    static var share: String           { en ? "Share…" : "Deel…" }
    static var shareHelp: String {
        en ? "Share the selected export presets"
           : "Deel de geselecteerde exportpresets"
    }
    static var quickLook: String       { en ? "Quick Look" : "Quick Look" }
    static var dockRecent: String      { en ? "Recent Portraits" : "Recente portretten" }

    // MARK: Main window
    static var importPhoto: String     { en ? "Import photo" : "Importeer foto" }
    static var importPhotoHelp: String { en ? "Import a new portrait photo" : "Importeer een nieuwe portretfoto" }

    // MARK: Import drop zone
    static var dropHere: String {
        en ? "Drop one or multiple portrait photos here"
           : "Sleep één of meerdere portretfoto's hierheen"
    }
    static var orBrowseFiles: String {
        en ? "or browse files" : "of blader bestanden"
    }
    // MARK: Sidebar update card
    static func updatedTo(_ version: String) -> String {
        en ? "Updated to \(version)" : "Bijgewerkt naar \(version)"
    }
    static var relaunchToApply: String { en ? "Relaunch to apply" : "Start opnieuw om toe te passen" }

    // MARK: Sidebar Pro quota card / Pro upsell toast
    static func proQuotaTitle(remaining: Int, total: Int) -> String {
        if remaining == 0 {
            return en ? "Library full, \(total) of \(total) used"
                      : "Bibliotheek vol, \(total) van \(total) gebruikt"
        }
        return en ? "\(remaining) of \(total) left"
                  : "\(remaining) van \(total) over"
    }
    /// Row label for the AI (Magic Cutout) portion of the free trial.
    /// Plural-aware ("1 AI generation" vs "N AI generations").
    /// Headline number for the sidebar quota card. Single unified counter:
    /// AI and basic generations both spend the same slot.
    static func proQuotaTotalRemaining(remaining: Int, total: Int) -> String {
        en ? "\(remaining) of \(total) portraits left"
           : "Nog \(remaining) van \(total) portretten"
    }
    /// Copy that wraps the inline `Pro` badge in the upsell line.
    static var proQuotaUpgradeBeforeBadge: String {
        en ? "Upgrade to" : "Upgrade naar"
    }
    static var proQuotaUpgradeAfterBadge: String {
        en ? "to unlock more" : "om meer te ontgrendelen"
    }
    /// Upsell line when Privacy mode is Local-only — avoid pitching
    /// Magic Cutout; unlimited portraits still apply on-device.
    static var proQuotaUpgradeBeforeBadgeLocalOnly: String {
        en ? "Upgrade to" : "Upgrade naar"
    }
    static var proQuotaUpgradeAfterBadgeLocalOnly: String {
        en ? "for unlimited portraits" : "voor onbeperkt portretten"
    }
    static var proQuotaTooltipLocalOnly: String {
        en ? "Free accounts get \(FreeTier.maxPortraits) portraits on this Mac. Upgrade to Pro for unlimited. Cloud AI stays off until you allow it in Settings → Privacy & AI."
           : "Gratis accounts krijgen \(FreeTier.maxPortraits) portretten op deze Mac. Upgrade naar Pro voor onbeperkt. Cloud-AI blijft uit tot je die toestaat in Instellingen → Privacy & AI."
    }
    static var proQuotaSubtitle: String {
        en ? "Upgrade to Pro to unlock more"
           : "Upgrade naar Pro om meer te ontgrendelen"
    }
    static var proQuotaTooltip: String {
        en ? "Free accounts get \(FreeTier.maxPortraits) portraits. Upgrade to Pro for unlimited."
           : "Gratis accounts krijgen \(FreeTier.maxPortraits) portretten. Upgrade naar Pro voor onbeperkt."
    }
    static var proQuotaUpgradeCTA: String {
        en ? "Upgrade" : "Upgrade"
    }

    // MARK: Yearly plan
    static var yearlyPlanTitle: String {
        en ? "Pro Annual" : "Pro Jaarlijks"
    }
    static var yearlyPlanSavings: String {
        // Concrete months > abstract %  (Emil: users feel concrete numbers)
        en ? "2 months free" : "2 maanden gratis"
    }
    static func yearlyPlanMonthlyEquiv(_ perMonth: String) -> String {
        en ? "\(perMonth)/mo billed annually"
           : "\(perMonth)/maand bij jaarlijks"
    }
    static var monthlyPlanTitle: String {
        en ? "Pro Monthly" : "Pro Maandelijks"
    }
    static var billingIntervalMonth: String {
        en ? "Monthly" : "Maandelijks"
    }
    static var billingIntervalYear: String {
        en ? "Yearly" : "Jaarlijks"
    }

    // MARK: Credit pack ladder
    static var packBestValueBadge: String {
        en ? "Best value" : "Beste waarde"
    }
    static var packStarterLabel: String {
        en ? "Starter" : "Starter"
    }
    static var packStandardLabel: String {
        en ? "Standard" : "Standaard"
    }
    static var packBestValueLabel: String {
        en ? "Best value" : "Voordelig"
    }
    /// Per-pack descriptor under the price (e.g. "50 credits · €0,040 each").
    static func packCreditsDescriptor(credits: Int, perCredit: String) -> String {
        en ? "\(credits) credits · \(perCredit) each"
           : "\(credits) credits · \(perCredit) per stuk"
    }
    /// Soft upsell shown when a free user drops more images than they
    /// have free imports left — the batch is partially processed (the
    /// first `processed` items run) and this nudges them to upgrade for
    /// the rest. Single-message form: we don't want a toast per dropped
    /// item, just one summary that names the cap they just hit.
    static func proUpsellPartialBatch(processed: Int, requested: Int) -> String {
        en ? "Imported \(processed) of \(requested). Upgrade to Pro for unlimited imports."
           : "\(processed) van \(requested) geïmporteerd. Upgrade naar Pro voor onbeperkt."
    }
    static func proBatchCapExceeded(_ max: Int) -> String {
        en ? "Imports are capped at \(max) at a time to keep things smooth. Try again with fewer."
           : "Imports zijn beperkt tot \(max) tegelijk om alles soepel te houden. Probeer het met minder."
    }

    // MARK: Import flow errors
    //
    // Voice rules (apply to anything the user reads when something goes wrong):
    //   1. Lead with what happened in plain words ("That image" not "The dropped resource")
    //   2. Suggest a next step when one exists ("Try a different file")
    //   3. Use "we" not "the system"; use "couldn't" not "cannot"
    //   4. Never paste raw exception strings unless we already understand they
    //      are user-readable (POSIX file errors are; stack traces aren't)
    static var dropPhotoNotFound: String {
        en ? "We couldn't find that photo. Try dragging it again."
           : "We konden die foto niet vinden. Sleep hem nog eens."
    }
    static var dropImageUnreadable: String {
        en ? "That image looks unreadable. Try a different file."
           : "Die afbeelding lijkt onleesbaar. Probeer een ander bestand."
    }
    static var imported: String              { en ? "Imported" : "Geïmporteerd" }
    static var unknownFileType: String {
        en ? "That isn't an image we can use. JPEG, PNG, or HEIC works best."
           : "Dat is geen afbeelding die we kunnen gebruiken. JPEG, PNG of HEIC werkt het beste."
    }
    static func cannotReadFile(_ err: String) -> String {
        en ? "Couldn't open that file. \(err)"
           : "Kon dat bestand niet openen. \(err)"
    }
    static var cannotDecodeImage: String {
        en ? "Couldn't open that image. JPEG, PNG, or HEIC works best."
           : "Kon die afbeelding niet openen. JPEG, PNG of HEIC werkt het beste."
    }
    static var noOriginalForRecutout: String {
        en ? "The original photo wasn't saved, so we can't redo the cutout."
           : "De originele foto is niet bewaard, dus we kunnen de uitknip niet opnieuw maken."
    }
    static var cannotDecodeOriginal: String {
        en ? "Couldn't reopen the original photo for this portrait."
           : "Kon de originele foto van dit portret niet opnieuw openen."
    }
    static var portraitNotFound: String {
        en ? "That portrait isn't here anymore."
           : "Dat portret is hier niet meer."
    }
    static func recutoutFailed(_ err: String) -> String {
        en ? "Magic Cutout couldn't finish. \(err)"
           : "Magic Cutout kon niet worden voltooid. \(err)"
    }
    static var noCutoutAvailable: String {
        en ? "No cutout to enhance yet."
           : "Nog geen uitknip om te verfraaien."
    }
    static var magicRetouchFailed: String {
        en ? "Magic Retouch didn't take. Try again."
           : "Magic Retouch lukte niet. Probeer het nog eens."
    }
    static func processingFailed(_ err: String) -> String {
        en ? "We hit a snag processing this photo. \(err)"
           : "We liepen vast bij het verwerken van deze foto. \(err)"
    }

    // MARK: Editor dimensions caption
    static func dimensionsLabel(_ w: Int, _ h: Int) -> String {
        en ? "\(w) × \(h) px" : "\(w) × \(h) px"
    }

}
