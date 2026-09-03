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

    /// Ondergrens voor de interoogafstand als fractie van de Vision-face-box-
    /// hoogte. Frontaal meet Vision ~0.40 (pupil-tot-pupil / wenkbrauw-tot-kin);
    /// bij een gedraaid hoofd (driekwart-profiel) krimpt de 2D-interoogafstand
    /// met cos(yaw) terwijl de boxhoogte gelijk blijft, en zou de eye-based
    /// schaal het portret ver inzoomen (Match framing 2026-09-03: 33° yaw →
    /// 25% te groot hoofd). De boxhoogte vangt dat op; frontale gezichten
    /// blijven ongemoeid omdat ze boven de grens zitten.
    static let minInterEyeToFaceHeight: CGFloat = 0.38

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

    /// E24.18: frame-ademruimte — het onderwerp vult standaard niet edge-to-edge
    /// maar laat een marge binnen het frame (circle/square). Gedeeld door de
    /// fill-fit-fallbacks (AutoFramer.fitTransform + EditorCanvasView.fitTransform)
    /// zodat de marge overal gelijk is. 0.85 = ~15% marge (haar raakt de cirkel
    /// niet meer). Figma-TODO: exacte marge bevestigen.
    static let frameFitPadding: CGFloat = 0.85
}
