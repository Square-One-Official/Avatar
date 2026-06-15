// Onboarding 2.0 — optionele high-fidelity-model-download (E04.6, Figma:
// Onboarding / Download now 4030:1131 + Downloading 4030:1149).
//
// HARDE hiërarchie-beslissing (Thierry, vervolg ORMBG-herziening): de
// primaire knop is "Continue with built-in engine" — de download is de
// secundaire actie, niet andersom zoals het frame toont. Skipbaar; een
// gestarte download loopt door in de achtergrond (zelfde OrmbgModelStore
// als Settings > AI & Models, E15.2 — één download-state, twee vensters).
// Modelgrootte = de echte ~78 MB (niet de 1,2 GB uit het frame).
//
// Copy-noot: het bewijs-argument "beter op krullend/fijn haar" is op de
// E02.2-fixtures niet hard aangetoond → zachter geformuleerd (geen harde
// kwaliteitsclaim), conform de story-notitie.

import AvatarUI
import SwiftUI

struct OnboardingDownloadView: View {
    @Bindable var model: OnboardingModel
    @State private var download = HighFidelityModelState()
    private let prefs = PrivacyPreferences2.shared

    private static let totalMB = 78

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 0) {
                VStack(spacing: DSSpacing.gap2) {
                    Text("Sharper hair edges?")
                        .dsTextStyle(.h1)
                        .foregroundStyle(DSColor.Foreground.primary)
                    Text("Download our on-device high-fidelity cutout model for crisper hair and edge detail. It's optional and runs entirely on your Mac — nothing is sent to the cloud.")
                        .dsTextStyle(.bodyMedium)
                        .foregroundStyle(DSColor.Foreground.subtle)
                }
                .multilineTextAlignment(.center)

                progressCard
                    .padding(.top, DSSpacing.gap12)

                buttons
                    .padding(.top, DSSpacing.gap12)
            }
            .frame(width: 332)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .task { download.refreshInstalledState() }
    }

    // Figma-kaart: download-glyph in lime cirkel + voortgangsbalk + label.
    private var progressCard: some View {
        VStack(spacing: DSSpacing.gap3) {
            Circle()
                .fill(DSColor.Background.action)
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: glyph)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(DSColor.Action.onAction)
                }
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .tint(DSColor.Action.primary)
            Text(statusLabel)
                .dsTextStyle(.bodySmall)
                .foregroundStyle(DSColor.Foreground.muted)
        }
        .padding(DSSpacing.gap5)
        .frame(maxWidth: .infinity)
        .background(DSColor.Background.card)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.xl2))
    }

    @ViewBuilder
    private var buttons: some View {
        switch download.phase {
        case .downloading:
            // Download loopt: primair "Continue" (achtergrond), met de
            // background-belofte eronder.
            VStack(spacing: DSSpacing.gap2) {
                DSPrimaryButton("Continue", fullWidth: true) {
                    model.finishFromDownload()
                }
                Text("Your download will continue in the background. Manage it in Settings.")
                    .dsTextStyle(.bodySmall)
                    .foregroundStyle(DSColor.Foreground.muted)
                    .multilineTextAlignment(.center)
            }
        case .installed:
            DSPrimaryButton("Continue", fullWidth: true) {
                model.finishFromDownload()
            }
        case .idle, .failed:
            // HARDE hiërarchie: built-in is primair, download secundair.
            VStack(spacing: DSSpacing.gap2) {
                DSPrimaryButton("Continue with built-in engine", fullWidth: true) {
                    model.finishFromDownload()
                }
                DSGhostButton("Download model (\(Self.totalMB) MB)", fullWidth: true) {
                    download.download { prefs.engine = .downloadedModel }
                }
                if download.phase == .failed {
                    Text("Download failed — you can try again in Settings.")
                        .dsTextStyle(.bodySmall)
                        .foregroundStyle(DSColor.Foreground.muted)
                }
            }
        }
    }

    private var fraction: Double {
        switch download.phase {
        case .downloading(let f): return f
        case .installed: return 1
        default: return 0
        }
    }

    private var glyph: String {
        switch download.phase {
        case .installed: return "checkmark"
        default: return "arrow.down"
        }
    }

    private var statusLabel: String {
        switch download.phase {
        case .downloading(let f):
            return "\(Int(f * Double(Self.totalMB))) of \(Self.totalMB) MB"
        case .installed:
            return "Installed"
        default:
            return "0 of \(Self.totalMB) MB"
        }
    }
}
