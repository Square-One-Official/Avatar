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
    static var ok: String              { "OK" }
    static var name: String            { en ? "Name" : "Naam" }
    static var add: String             { en ? "Add" : "Toevoegen" }
    static var close: String           { en ? "Close" : "Sluiten" }
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
    /// Undo action name for handle-based scale changes on the canvas.
    static var scale: String           { en ? "Scale" : "Schaal" }

    // MARK: Editor – Edit section
    static var edit: String            { en ? "Edit" : "Bewerken" }
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

    // MARK: Editor – More magic edits (dropdown of Replicate-backed Pro tools)
    static var moreMagicEdits: String {
        en ? "More" : "Meer"
    }
    static var moreMagicEditsHelp: String {
        en ? "Pro AI edits — fill in body and more."
           : "Pro AI-bewerkingen — vul lichaam aan en meer."
    }
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

    // MARK: Settings – Labs (experimental features, off by default)
    static var labsTitle: String { en ? "Labs" : "Labs" }
    static var labsDesc: String {
        en ? "Experimental features under active development. May change, break, or disappear without notice."
           : "Experimentele functies in ontwikkeling. Kunnen veranderen, kapotgaan of verdwijnen zonder aankondiging."
    }
    static var labsFillBodyTitle: String {
        en ? "Fill in Body (preview)" : "Vul lichaam aan (preview)"
    }
    static var labsFillBodyDesc: String {
        en ? "Show the \u{201C}More\u{201D} dropdown in the editor with the Fill in Body action. Off by default while we tune quality."
           : "Toon het \u{201C}Meer\u{201D}-menu in de editor met Vul lichaam aan. Standaard uit terwijl we de kwaliteit afstellen."
    }

    static var proUpgradeSignInFirst: String {
        en ? "Please sign in first to manage your subscription."
           : "Meld je eerst aan om je abonnement te beheren."
    }

    static var proUpgradeSignInToContinue: String {
        en ? "Sign in to start your subscription."
           : "Meld je aan om je abonnement te starten."
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
        en ? "Welcome to Avatar" : "Welkom bij Avatar"
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
    static var proUpgradeFinePrint: String {
        en ? "Cancel anytime. Credits reset at the start of each billing period. Top-up credits never expire."
           : "Op elk moment opzegbaar. Credits resetten aan het begin van elke factuurperiode. Bijgekochte credits vervallen nooit."
    }

    // MARK: Top-up
    static var topupCardTitle: String {
        en ? "Buy 200 credits" : "Koop 200 credits"
    }
    static var topupCardPrice: String { "€4,99" }
    static var topupCardDescription: String {
        en ? "200 extra credits, on top of your monthly grant. They never expire."
           : "200 extra credits, bovenop je maandelijkse tegoed. Vervallen nooit."
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

    /// Returns the message rotation that fits the current processing kind.
    static func processingStatuses(for kind: ProcessingKind) -> [String] {
        switch kind {
        case .cutout:   return processingStatuses
        case .fillBody: return fillBodyProcessingStatuses
        }
    }

    // MARK: Editor – Background picker context menu
    static var rename: String          { en ? "Rename…" : "Hernoem…" }
    static var setDefault: String      { en ? "Set as default" : "Maak standaard" }
    static var defaultCheck: String    { en ? "Default ✓" : "Standaard ✓" }

    // MARK: Editor – Color palette
    static var white: String           { en ? "White" : "Wit" }
    static var lightGray: String       { en ? "Light gray" : "Licht grijs" }
    static var warmWhite: String       { en ? "Warm white" : "Warm wit" }
    static var softBlue: String        { en ? "Soft blue" : "Zacht blauw" }
    static var softGreen: String       { en ? "Soft green" : "Zacht groen" }
    static var peach: String           { en ? "Peach" : "Perzik" }
    static var deepBlue: String        { en ? "Deep blue" : "Diep blauw" }
    static var anthracite: String      { en ? "Anthracite" : "Antraciet" }

    // MARK: Editor – Add background popover
    static var uploadImage: String     { en ? "Upload image…" : "Upload afbeelding…" }
    static var chooseColor: String     { en ? "Choose a color" : "Kies een kleur" }
    static var color: String           { en ? "Color" : "Kleur" }

    // MARK: Settings – Tabs
    static var settingsGeneral: String { en ? "General" : "Algemeen" }
    static var settingsAccount: String { en ? "Account" : "Account" }
    static var appearance: String      { en ? "Appearance" : "Weergave" }
    static var appearanceDesc: String {
        en ? "Choose how Avatar looks. Dark uses a deeper near-black palette."
           : "Kies hoe Avatar eruitziet. Donker gebruikt een dieper bijna-zwart palet."
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

    // MARK: Settings – AI Model tab
    static var aiHairQuality: String   { en ? "AI Hair Quality" : "AI Haarkwaliteit" }
    static var advancedCutoutModel: String { en ? "Advanced cutout model" : "Geavanceerd uitknipmodel" }
    static var advancedModelDesc: String {
        en ? "Uses a specialized AI model (BiRefNet) for better hair quality when removing backgrounds. Especially visible with fine hair, curls, and hair against a busy background."
           : "Gebruikt een gespecialiseerd AI-model (BiRefNet) voor betere haarkwaliteit bij het vrijstaand maken. Vooral zichtbaar bij fijn haar, krullen en haar tegen een drukke achtergrond."
    }
    static var modelNotInstalled: String { en ? "Model not installed" : "Model niet geinstalleerd" }
    static var downloadModelPrompt: String {
        en ? "Download the BiRefNet model (~250 MB) for better hair quality when removing backgrounds."
           : "Download het BiRefNet model (~250 MB) voor betere haarkwaliteit bij het vrijstaand maken."
    }
    static var installModel: String    { en ? "Install model" : "Installeer model" }
    static var downloading: String     { en ? "Downloading…" : "Downloaden..." }
    static var modelAvailable: String  { en ? "Model available" : "Model beschikbaar" }
    static var useAdvancedModel: String {
        en ? "Use advanced model for cutout"
           : "Gebruik geavanceerd model bij uitknippen"
    }
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
    static var searchPlaceholder: String { en ? "Search by name or tag" : "Zoek op naam of tag" }
    static var noPortraitsYet: String  { en ? "No portraits yet" : "Nog geen portretten" }
    static var noResults: String       { en ? "No results" : "Geen resultaten" }
    static var importToStart: String   { en ? "Import a photo to get started." : "Importeer een foto om te beginnen." }
    static var adjustSearch: String    { en ? "Adjust your search." : "Pas je zoekopdracht aan." }
    static var processing: String      { en ? "Processing…" : "Verwerken…" }
    static var unnamed: String         { en ? "(unnamed)" : "(naamloos)" }

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
    static var dropZoneProTitle: String {
        en ? "Magic Cutout" : "Magic Cutout"
    }
    /// Subtitle shown while the free user still has trial cutouts left.
    /// `n` = remaining free calls, normally 1 or 2. The "first 2 are on us"
    /// framing is what makes the toggle land — switch off → save your trial,
    /// switch on → use Pro now.
    static func dropZoneProFreeRemaining(_ n: Int) -> String {
        en ? "First \(FreeTier.freeMagicCutoutAllowance) are on us · \(n) left"
           : "De eerste \(FreeTier.freeMagicCutoutAllowance) zijn van ons · nog \(n)"
    }
    /// Subtitle once the free trial is exhausted — banner flips back to the
    /// classic Upgrade pill.
    static var dropZoneProExhausted: String {
        en ? "Free trial used — Upgrade to keep using"
           : "Gratis proef opgebruikt — upgrade om door te gaan"
    }
    static var dropZoneProUpgrade: String {
        en ? "Upgrade" : "Upgrade"
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
    static var proQuotaSubtitle: String {
        en ? "Upgrade to Pro to unlock more"
           : "Upgrade naar Pro om meer te ontgrendelen"
    }
    static var proQuotaTooltip: String {
        en ? "Free accounts can keep up to \(FreeTier.maxPortraits) portraits. Upgrade to Pro for unlimited."
           : "Gratis accounts kunnen tot \(FreeTier.maxPortraits) portretten bewaren. Upgrade naar Pro voor onbeperkt."
    }
    static var proQuotaUpgradeCTA: String {
        en ? "Upgrade" : "Upgrade"
    }
    static func proUpsellBatchLimit(_ max: Int) -> String {
        en ? "Importing more than \(max) at once is a Pro feature."
           : "Meer dan \(max) tegelijk importeren is een Pro-functie."
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
