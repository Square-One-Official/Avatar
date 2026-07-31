// Gedeelde scrim onder kaartlabels (UXS-3 / UX5).
//
// Kaarttitels staan wit ín de kaart, bovenop een willekeurige foto. De oude
// scrim liep `.clear → .black.opacity(0.55)` van het midden naar de ONDERrand;
// het label zit door zijn padding niet op die onderrand maar hálverwege de
// ramp, dus de effectieve dekking onder de tekst lag ruim lager dan 0.55. Op
// een lichte cutout in light mode zakte het contrast daarmee onder 4.5:1.
//
// Deze scrim maakt de dekking foto-ONAFHANKELIJK: de ramp is klaar vóórdat de
// tekstzone begint en houdt daar een vlak plateau aan. Zwart is hier bewust
// géén thema-token — het label is altijd wit, dus de ondergrond moet in beide
// themes donker zijn.

import SwiftUI

public struct DSCardLabelScrim: View {
    /// Dekking in de tekstzone. Wit (#FFF) hierop, in het slechtste geval over
    /// een zuiver witte foto, haalt ≥ 4.5:1 — zie `DSCardLabelScrim.contrastRatioOnWhite`.
    public static let plateauOpacity: Double = 0.78

    /// Waar de ramp begint, als fractie van de scrim-hoogte (0 = bovenaan).
    private let startFraction: Double
    /// Waar het plateau begint; alles daaronder heeft `plateauOpacity`.
    private let plateauFraction: Double

    public init(startFraction: Double = 0.35, plateauFraction: Double = 0.72) {
        self.startFraction = startFraction
        self.plateauFraction = plateauFraction
    }

    public var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: startFraction),
                .init(color: .black.opacity(Self.plateauOpacity * 0.45),
                      location: (startFraction + plateauFraction) / 2),
                .init(color: .black.opacity(Self.plateauOpacity), location: plateauFraction),
                .init(color: .black.opacity(Self.plateauOpacity), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }
}

public extension DSCardLabelScrim {
    /// Contrast van wit tekst op deze scrim over een zuiver witte ondergrond —
    /// het slechtst denkbare geval. Pure functie zodat de 4.5:1-ondergrens in
    /// een test geborgd is i.p.v. met het oog geschat.
    static func contrastRatioOnWhite(opacity: Double = plateauOpacity) -> Double {
        // Zwart met `opacity` over wit → sRGB-kanaalwaarde (1 - opacity).
        let channel = 1 - opacity
        let linear = channel <= 0.04045
            ? channel / 12.92
            : pow((channel + 0.055) / 1.055, 2.4)
        // Relatieve luminantie is voor grijs gelijk aan de lineaire kanaalwaarde.
        return 1.05 / (linear + 0.05)
    }
}
