// Framing-doelwaarden (E06.4/E06.5) — 1-op-1 geport uit v1
// CanvasConstants (Avatar/Services/AutoAligner.swift): getunede waarden,
// niet opnieuw raden (besluit Thierry). Alle transforms leven in de
// 1024-units canvasruimte zodat layout resolutie-onafhankelijk is en de
// AutoAligner-port (6.5) dezelfde wiskunde houdt.

import CoreGraphics

enum FramingConstants {
    /// Standaard bewerkingscanvas; offsets/scales zijn in deze ruimte.
    static let editCanvas = CGSize(width: 1024, height: 1024)

    /// Doel-interoogafstand als fractie van de canvashoogte — de
    /// interoogafstand is bij volwassenen vrijwel constant, dus dit maakt
    /// alle hoofden even groot.
    static let targetInterEyeRatio: CGFloat = 0.12

    /// Verticale positie van het oogmidden ("standaard-ooglijn"), gemeten
    /// vanaf de canvastop.
    static let targetEyeCenterY: CGFloat = 0.37

    /// Horizontale positie van het oogmidden (gecentreerd).
    static let targetEyeCenterX: CGFloat = 0.50

    // Zoomgrenzen van het portret binnen de kaart (spec E06.4).
    static let minZoomFactor: Double = 0.5
    static let maxZoomFactor: Double = 3.0

    // MARK: Face-rect-fallback + body (E06.5, v1-waarden)

    /// Doelhoogte van de face-box als fractie van de canvashoogte (fallback
    /// zonder ooglandmarks).
    static let targetFaceHeightRatio: CGFloat = 0.38

    /// Verticale positie van het face-centrum (fallback).
    static let targetFaceCenterY: CGFloat = 0.42

    /// Horizontale positie van het face-centrum (fallback).
    static let targetFaceCenterX: CGFloat = 0.50

    /// Hoe ver de romp voorbij de canvasonderkant moet doorlopen.
    static let bodyOvershoot: CGFloat = 0.03
}
