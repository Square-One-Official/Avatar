// Apple Intelligence / Image Playground beschikbaarheid (Tier 2 gate).
// Herkennt macOS-versie, Apple Silicon en Image Playground runtime-status.

import AppKit
import Foundation
import Observation

enum AppleIntelligenceSupportStatus: Equatable, Sendable {
    case supported
    case unsupportedMacOS(requiredVersion: String)
    case unsupportedHardware
    case appleIntelligenceUnavailable

    var footnote: String {
        switch self {
        case .supported:
            return ""
        case .unsupportedMacOS(let version):
            return "Requires macOS \(version) or later"
        case .unsupportedHardware:
            return "Requires Apple Silicon"
        case .appleIntelligenceUnavailable:
            return "Apple Intelligence is off or unavailable in your language or region."
        }
    }

    /// Tier 2-footnote kan een directe link naar System Settings krijgen.
    var offersSystemSettingsShortcut: Bool {
        self == .appleIntelligenceUnavailable
    }
}

enum AppleIntelligenceAvailability {

    /// Minimale macOS-versie voor Image Playground API (Apple: 15.1+).
    static let requiredMacOSMajor = 15
    static let requiredMacOSMinor = 1

    static var requiredMacOSVersionLabel: String {
        "\(requiredMacOSMajor).\(requiredMacOSMinor)"
    }

    /// Volledige ondersteuningscheck — bron voor Tier 2 enabled/disabled.
    /// Leest via de observable store: SwiftUI-body's die dit lezen hertekenen
    /// vanzelf na `refresh()` (app terug in focus na System Settings).
    static var status: AppleIntelligenceSupportStatus {
        AppleIntelligenceAvailabilityStore.shared.status
    }

    /// Her-evalueer de runtime-status (Apple Intelligence aan/uit gezet in
    /// System Settings). Alleen views die `status`/`supportsApplePrivateCloud`
    /// lezen hertekenen — de rest van de view-tree (en z'n @State) blijft staan.
    static func refresh() {
        AppleIntelligenceAvailabilityStore.shared.refresh()
    }

    static var supportsApplePrivateCloud: Bool {
        status == .supported
    }

    /// Footnote onder de uitgeschakelde Apple Private Cloud-rij.
    static var tierDisabledFootnote: String {
        let note = status.footnote
        return note.isEmpty ? "Not available on this Mac" : note
    }

    /// Human-readable samenvatting voor Settings (wanneer Tier 2 niet kan).
    static var settingsSummary: String? {
        switch status {
        case .supported:
            return nil
        case .unsupportedMacOS:
            return "Apple Private Cloud needs macOS \(requiredMacOSVersionLabel) or later. Update macOS to unlock this tier."
        case .unsupportedHardware:
            return "Apple Private Cloud needs a Mac with Apple Silicon."
        case .appleIntelligenceUnavailable:
            return "This Mac supports Apple Private Cloud, but Apple Intelligence is off or unavailable in your language or region. Turn it on in System Settings."
        }
    }

    static func evaluateSupport() -> AppleIntelligenceSupportStatus {
        #if !arch(arm64)
        return .unsupportedHardware
        #else
        guard isMacOSAtLeast(major: requiredMacOSMajor, minor: requiredMacOSMinor) else {
            return .unsupportedMacOS(requiredVersion: requiredMacOSVersionLabel)
        }
        #if canImport(ImagePlayground)
        if #available(macOS 15.1, *) {
            return ImagePlaygroundBridge.isAvailable
                ? .supported
                : .appleIntelligenceUnavailable
        }
        #endif
        return .unsupportedMacOS(requiredVersion: requiredMacOSVersionLabel)
        #endif
    }

    static func isMacOSAtLeast(major: Int, minor: Int) -> Bool {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        if version.majorVersion > major { return true }
        if version.majorVersion < major { return false }
        return version.minorVersion >= minor
    }

    /// Opent het Apple Intelligence & Siri-paneel in System Settings (Tier 2 uit).
    static func openAppleIntelligenceSettings() {
        // macOS Sequoia+: "Apple Intelligence & Siri" = Siri-Settings extension
        // (zie sigo/macos-settings-urls). Oudere kandidaten openen alleen Settings
        // root — NSWorkspace.open retourneert dan alsnog true.
        let candidates = [
            "x-apple.systempreferences:com.apple.Siri-Settings.extension",
            "x-apple.systempreferences:com.apple.Siri",
        ]
        for raw in candidates {
            guard let url = URL(string: raw), NSWorkspace.shared.open(url) else { continue }
            return
        }
        if let url = URL(string: "x-apple.systempreferences:") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Observable cache van de support-status. Bug-fix 2026-09-03: de refresh bij
/// app-activatie ging via `.id(tick)` op de hele ShellView, wat élke @State in
/// de shell wiste (editor-camera sprong terug naar fit bij een venster-wissel).
/// Nu is de status zelf observable, dus een refresh raakt alleen de lezers.
@Observable
final class AppleIntelligenceAvailabilityStore {
    static let shared = AppleIntelligenceAvailabilityStore()

    private(set) var status: AppleIntelligenceSupportStatus

    private init() {
        status = AppleIntelligenceAvailability.evaluateSupport()
    }

    func refresh() {
        let fresh = AppleIntelligenceAvailability.evaluateSupport()
        if fresh != status { status = fresh }
    }
}
